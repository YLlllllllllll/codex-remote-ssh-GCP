#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCAL_USER="$(id -un)"
REAL_HOME="$(dscl . -read "/Users/${LOCAL_USER}" NFSHomeDirectory 2>/dev/null | awk '{ print $2; exit }')"
REAL_HOME="${REAL_HOME:-${HOME:?}}"

REMOTE_SCRIPT="${REAL_HOME}/bin/codex-gcp-remote"
KINIT_SCRIPT="${REAL_HOME}/bin/kinit-refresh"
CI_MARKER=""

fail() {
  printf 'live-egress-ci: %s\n' "$*" >&2
  exit 1
}

log() {
  printf '\n== %s ==\n' "$*"
}

require_executable() {
  [[ -x "$1" ]] || fail "missing executable: $1"
}

listener_count() {
  { lsof -tiTCP:"$1" -sTCP:LISTEN 2>/dev/null || true; } | wc -l | tr -d ' '
}

assert_no_local_egress() {
  local socks_count http_count
  socks_count="$(listener_count 1080)"
  http_count="$(listener_count 7890)"
  [[ "$socks_count" == "0" ]] || fail "local 1080 still listening"
  [[ "$http_count" == "0" ]] || fail "local 7890 still listening"
}

assert_remote_no_workers_or_sockets() {
  local out workers sockets
  out="$(ssh codex-candy-workspace 'printf "workers="; ps -eo args | awk "/codex exec/ && !/awk/ {c++} END {print c+0}"; printf "sockets="; ss -tnp 2>/dev/null | grep "127.0.0.1:10800" | wc -l')"
  printf '%s\n' "$out"
  workers="$(awk -F= '$1=="workers" {print $2}' <<<"$out" | tr -d '[:space:]')"
  sockets="$(awk -F= '$1=="sockets" {print $2}' <<<"$out" | tr -d '[:space:]')"
  [[ "${workers:-0}" == "0" ]] || fail "remote codex exec workers remain: ${workers}"
  [[ "${sockets:-0}" == "0" ]] || fail "remote 10800 sockets remain: ${sockets}"
}

assert_status_stopped() {
  local status proxy codex
  status="$(awk -F= '$1=="STATUS" {print $2; exit}' /tmp/kinit-refresh.status 2>/dev/null || true)"
  proxy="$(awk -F= '$1=="PROXY" {print $2; exit}' /tmp/kinit-refresh.status 2>/dev/null || true)"
  codex="$(awk -F= '$1=="CODEX" {print $2; exit}' /tmp/kinit-refresh.status 2>/dev/null || true)"
  [[ "$status" == "stopped" ]] || fail "expected STATUS=stopped, got ${status:-empty}"
  [[ "$proxy" == "stopped" ]] || fail "expected PROXY=stopped, got ${proxy:-empty}"
  [[ "$codex" == "stopped" ]] || fail "expected CODEX=stopped, got ${codex:-empty}"
}

spawn_fake_stale_worker() {
  local marker="$1"
  ssh codex-candy-workspace "marker='$marker' bash -s" <<'REMOTE'
set -Eeuo pipefail
nohup bash -c 'exec -a "/tmp/codex-egress-ci/bin/codex exec resume ${marker}" sleep 600' >/dev/null 2>&1 &
printf '%s\n' "$!"
REMOTE
}

count_marker_workers() {
  local marker="$1"
  ssh codex-candy-workspace "marker='$marker' bash -s" <<'REMOTE'
ps -eo args= 2>/dev/null | awk -v marker="$marker" '/\/bin\/codex exec/ && index($0, marker) {count++} END {print count + 0}'
REMOTE
}

cleanup_marker_workers() {
  local marker="$1"
  ssh codex-candy-workspace "marker='$marker' bash -s" <<'REMOTE' || true
pids="$(ps -eo pid=,args= 2>/dev/null | awk -v marker="$marker" '/\/bin\/codex exec/ && index($0, marker) {print $1}')"
if [ -n "$pids" ]; then
  kill $pids 2>/dev/null || true
  sleep 1
  kill -9 $pids 2>/dev/null || true
fi
REMOTE
}

main() {
  cd "$ROOT"
  require_executable "$REMOTE_SCRIPT"
  require_executable "$KINIT_SCRIPT"

  CI_MARKER="codex-egress-ci-$(date +%s)-$$"

  cleanup() {
    if [[ -n "${CI_MARKER:-}" ]]; then
      cleanup_marker_workers "$CI_MARKER"
    fi
    "$KINIT_SCRIPT" stop-gcp >/dev/null 2>&1 || true
  }
  trap cleanup EXIT

  log "fake CI"
  scripts/fake-repair-ci.sh

  log "baseline stop and low traffic"
  "$KINIT_SCRIPT" stop-gcp
  assert_no_local_egress
  assert_status_stopped
  "$REMOTE_SCRIPT" traffic-sample 10
  assert_remote_no_workers_or_sockets

  log "marker-scoped stale worker cleanup"
  spawn_fake_stale_worker "$CI_MARKER"
  sleep 2
  [[ "$(count_marker_workers "$CI_MARKER")" == "1" ]] || fail "fake marker worker was not created"
  CODEX_EXEC_CLEAN_MARKER="$CI_MARKER" STALE_CODEX_EXEC_MIN_AGE=999999 "$REMOTE_SCRIPT" clean-workers
  [[ "$(count_marker_workers "$CI_MARKER")" == "1" ]] || fail "high age threshold should preserve fake worker"
  CODEX_EXEC_CLEAN_MARKER="$CI_MARKER" STALE_CODEX_EXEC_MIN_AGE=1 "$REMOTE_SCRIPT" clean-workers
  [[ "$(count_marker_workers "$CI_MARKER")" == "0" ]] || fail "marker worker cleanup failed"

  log "requested Codex GCP path works"
  "$REMOTE_SCRIPT" repair-fast
  "$REMOTE_SCRIPT" verify-fast
  curl -sS --connect-timeout 3 --max-time 8 -x http://127.0.0.1:7890 https://api.ipify.org >/dev/null

  log "final stop and leak check"
  "$KINIT_SCRIPT" stop-gcp
  assert_no_local_egress
  assert_status_stopped
  "$REMOTE_SCRIPT" traffic-sample 10
  assert_remote_no_workers_or_sockets

  trap - EXIT
  printf '\nlive-egress-ci: ok\n'
}

main "$@"
