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
bash -n bin/kinit-refresh bin/codex-gcp-remote bin/stay-awake.sh scripts/install.sh scripts/fake-repair-ci.sh
swiftc -parse app/kinit-refresh-status.swift
plutil -lint launchd/com.example.kinit-refresh.plist launchd/com.example.kinit-refresh-status.plist launchd/com.example.stay-awake.plist >/dev/null
python3 -m py_compile tools/codex-http-to-socks.py

printf '== app menu contract ==\n'
need_pattern 'title: "修复 GCP".*refreshRemoteGCP' app/kinit-refresh-status.swift
need_pattern 'title: "刷新 SSH".*refreshSSH' app/kinit-refresh-status.swift
need_pattern 'toggleStayAwake' app/kinit-refresh-status.swift
reject_pattern '强制清理 Remote GCP|完整验证 Remote GCP|打开日志|退出状态栏' app/kinit-refresh-status.swift

printf '== repair command contract ==\n'
need_pattern 'gcp\|remote-gcp\|codex-gcp\|refresh-gcp' bin/kinit-refresh
need_pattern 'verify_codex_chain_clean_fast' bin/kinit-refresh
need_pattern 'clean-repair-fast' bin/codex-gcp-remote
need_pattern 'force_reset_local_proxy' bin/codex-gcp-remote
need_pattern 'force_reset_remote_proxy' bin/codex-gcp-remote
need_pattern 'restart_remote_codex_app_server' bin/codex-gcp-remote
need_pattern 'start_remote_forward' bin/codex-gcp-remote

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
