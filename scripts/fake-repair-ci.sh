#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() {
  printf 'fake-repair-ci: %s\n' "$*" >&2
  exit 1
}

need_pattern() {
  local pattern="$1"
  local file="$2"
  rg -q "$pattern" "$file" || fail "missing pattern in $file: $pattern"
}

reject_pattern() {
  local pattern="$1"
  local file="$2"
  if rg -q "$pattern" "$file"; then
    fail "forbidden pattern in $file: $pattern"
  fi
}

printf '== static syntax ==\n'
bash -n bin/kinit-refresh bin/codex-gcp-remote bin/codex-gcp-forward-session bin/codex-gcp-monitor bin/codex-gcp-autoheal bin/codex-workspace-proxy bin/stay-awake.sh scripts/install.sh scripts/fake-repair-ci.sh scripts/live-egress-ci.sh
bin/codex-gcp-monitor self-test
bin/codex-gcp-autoheal self-test
swiftc -parse app/kinit-refresh-status.swift
plutil -lint launchd/com.example.kinit-refresh.plist launchd/com.example.kinit-refresh-status.plist launchd/com.example.stay-awake.plist launchd/com.example.codex-gcp-forward.plist launchd/com.example.codex-gcp-monitor.plist launchd/com.example.codex-gcp-autoheal.plist >/dev/null
python3 -m py_compile tools/codex-http-to-socks.py
reject_pattern '<string>@/bin/' launchd/com.example.kinit-refresh-status.plist
need_pattern 'com.example.kinit-refresh.plist' scripts/install.sh
need_pattern 'com.example.kinit-refresh"' scripts/install.sh

printf '== app menu contract ==\n'
need_pattern 'title: "修复 GCP".*refreshRemoteGCP' app/kinit-refresh-status.swift
need_pattern 'title: "刷新 SSH".*refreshSSH' app/kinit-refresh-status.swift
need_pattern 'title: "登录/更新 kinit".*loginKinit' app/kinit-refresh-status.swift
need_pattern 'save-password' app/kinit-refresh-status.swift
need_pattern 'trafficSummary' app/kinit-refresh-status.swift
need_pattern 'TRAFFIC_TODAY_HUMAN' app/kinit-refresh-status.swift
need_pattern 'TRAFFIC_24H_HUMAN' app/kinit-refresh-status.swift
need_pattern 'TRAFFIC_RATE_HUMAN' app/kinit-refresh-status.swift
need_pattern '当前' app/kinit-refresh-status.swift
need_pattern 'sessionsItem' app/kinit-refresh-status.swift
need_pattern 'Codex Sessions' app/kinit-refresh-status.swift
need_pattern 'REMOTE_CODEX_EXEC_COUNT' app/kinit-refresh-status.swift
need_pattern 'REMOTE_10800_SOCKET_COUNT' app/kinit-refresh-status.swift
need_pattern 'openSessionsLog' app/kinit-refresh-status.swift
need_pattern 'copySessionsLog' app/kinit-refresh-status.swift
need_pattern 'toggleStayAwake' app/kinit-refresh-status.swift
reject_pattern '强制清理 Remote GCP|完整验证 Remote GCP|打开日志|退出状态栏' app/kinit-refresh-status.swift

printf '== repair command contract ==\n'
need_pattern 'codex-workspace-proxy' scripts/install.sh
need_pattern 'WORKSPACE_JUMP_HOST' bin/codex-workspace-proxy
need_pattern 'JUMP_PROXY_SERVICE' bin/codex-workspace-proxy
need_pattern '/usr/bin/nc -G' bin/codex-workspace-proxy
need_pattern '^[[:space:]]*-4' bin/codex-workspace-proxy
need_pattern '^[[:space:]]*-6' bin/codex-workspace-proxy
need_pattern 'gcp\|remote-gcp\|codex-gcp\|refresh-gcp' bin/kinit-refresh
need_pattern 'KINIT_LIFETIME' bin/kinit-refresh
need_pattern 'KINIT_RENEWABLE_LIFE' bin/kinit-refresh
need_pattern 'run_single_kinit_with_timeout' bin/kinit-refresh
need_pattern 'stop-gcp\|stop-egress\|limit-gcp\|limit-egress' bin/kinit-refresh
need_pattern 'stop_codex_gcp_egress' bin/kinit-refresh
need_pattern 'mark_gcp_enabled' bin/kinit-refresh
need_pattern 'mark_gcp_disabled' bin/kinit-refresh
need_pattern 'verify_codex_chain_clean_fast' bin/kinit-refresh
need_pattern 'clean-repair-fast' bin/codex-gcp-remote
need_pattern 'stop-egress' bin/codex-gcp-remote
need_pattern 'limit-egress' bin/codex-gcp-remote
need_pattern 'clean-workers' bin/codex-gcp-remote
need_pattern 'traffic-sample' bin/codex-gcp-remote
need_pattern 'force_reset_local_proxy' bin/codex-gcp-remote
need_pattern 'force_reset_remote_proxy' bin/codex-gcp-remote
need_pattern 'clean_stale_remote_codex_exec' bin/codex-gcp-remote
need_pattern 'STALE_CODEX_EXEC_MIN_AGE' bin/codex-gcp-remote
need_pattern 'CODEX_EXEC_CLEAN_MARKER' bin/codex-gcp-remote
need_pattern 'restart_remote_codex_app_server' bin/codex-gcp-remote
need_pattern 'start_remote_forward' bin/codex-gcp-remote
need_pattern 'REMOTE_FORWARD_PID_FILE' bin/codex-gcp-remote
need_pattern 'REMOTE_FORWARD_LABEL' bin/codex-gcp-remote
need_pattern 'codex-gcp-forward-session' scripts/install.sh
need_pattern 'com.example.codex-gcp-forward.plist' scripts/install.sh
need_pattern 'KeepAlive' launchd/com.example.codex-gcp-forward.plist
need_pattern 'ControlMaster=no' bin/codex-gcp-forward-session
need_pattern 'start_dedicated_remote_forward' bin/codex-gcp-remote
need_pattern 'stop_dedicated_remote_forward' bin/codex-gcp-remote
need_pattern 'launchctl bootstrap' bin/codex-gcp-remote

printf '== live CI contract ==\n'
need_pattern 'scripts/fake-repair-ci.sh' scripts/live-egress-ci.sh
need_pattern 'KINIT_SCRIPT.*stop-gcp' scripts/live-egress-ci.sh
need_pattern 'repair-fast' scripts/live-egress-ci.sh
need_pattern 'verify-fast' scripts/live-egress-ci.sh
need_pattern 'CODEX_EXEC_CLEAN_MARKER=.*CI_MARKER' scripts/live-egress-ci.sh
need_pattern 'STALE_CODEX_EXEC_MIN_AGE=1' scripts/live-egress-ci.sh
reject_pattern '/home/tiger/.local.*/codex exec|/Applications/Codex.app|launchctl setenv|open -a Codex' scripts/live-egress-ci.sh

printf '== passive monitor contract ==\n'
need_pattern 'codex-gcp-monitor \[sample\|status\|tail \[n\]\|path\|self-test\]' bin/codex-gcp-monitor
need_pattern 'monitor.jsonl' bin/codex-gcp-monitor
need_pattern 'monitor-latest.env' bin/codex-gcp-monitor
need_pattern 'gcp_counter_ok' bin/codex-gcp-monitor
need_pattern 'GCP_RX_BYTES' bin/codex-gcp-monitor
need_pattern 'TRAFFIC_TODAY_BYTES' bin/codex-gcp-monitor
need_pattern 'TRAFFIC_24H_BYTES' bin/codex-gcp-monitor
need_pattern 'TRAFFIC_STATUS' bin/codex-gcp-monitor
need_pattern 'active-sessions.txt' bin/codex-gcp-monitor
need_pattern 'REMOTE_CODEX_EXEC_COUNT' bin/codex-gcp-monitor
need_pattern 'REMOTE_10800_SOCKET_COUNT' bin/codex-gcp-monitor
need_pattern 'StartInterval' launchd/com.example.codex-gcp-monitor.plist
reject_pattern 'kinit-refresh remote-gcp|clean-repair-fast|killall|pkill|launchctl setenv|/Applications/Codex.app' bin/codex-gcp-monitor

printf '== autoheal contract ==\n'
need_pattern 'codex-gcp-autoheal \[run\|status\|self-test\]' bin/codex-gcp-autoheal
need_pattern 'CODEX_GCP_AUTOHEAL_ENABLED' bin/codex-gcp-autoheal
need_pattern 'AUTOHEAL_MIN_CONSECUTIVE_FAILS' bin/codex-gcp-autoheal
need_pattern 'AUTOHEAL_COOLDOWN_SECONDS' bin/codex-gcp-autoheal
need_pattern 'GCP_ENABLED_FILE' bin/codex-gcp-autoheal
need_pattern 'gcp_intended_on' bin/codex-gcp-autoheal
need_pattern 'sync_enabled_marker_if_healthy' bin/codex-gcp-autoheal
need_pattern 'cause_autohealable' bin/codex-gcp-autoheal
need_pattern 'consecutive_fail_count' bin/codex-gcp-autoheal
need_pattern 'kinit-refresh' bin/codex-gcp-autoheal
need_pattern 'codex-gcp-autoheal' scripts/install.sh
need_pattern 'com.example.codex-gcp-autoheal.plist' scripts/install.sh
need_pattern 'StartInterval' launchd/com.example.codex-gcp-autoheal.plist
need_pattern 'CODEX_GCP_AUTOHEAL_ENABLED' config.env.example
reject_pattern 'killall|pkill|launchctl setenv|/Applications/Codex.app' bin/codex-gcp-autoheal

printf '== clean repair ordering ==\n'
python3 - <<'PY'
from pathlib import Path

text = Path("bin/codex-gcp-remote").read_text()
start = text.index("clean_repair_fast()")
end = text.index("\n}\n\nverify_fast", start)
body = text[start:end]
order = [
    "force_reset_local_proxy",
    "force_reset_remote_proxy",
    "restart_remote_codex_app_server",
    "start_local_socks",
    "start_local_http",
    "clean_stale_remote_codex_exec",
    "start_remote_forward",
]
positions = [body.index(item) for item in order]
if positions != sorted(positions):
    raise SystemExit("clean_repair_fast order is unsafe")
PY

printf '== sensitive information guard ==\n'
if rg -n -g '!scripts/fake-repair-ci.sh' 'LYC|luyucheng|35\.252|119246|BYTEDANCE|ssh-candy|jump-proxy-arnold|/Users/bytedance' .; then
  fail "repository contains local/private identifiers"
fi

printf 'fake-repair-ci: ok\n'
