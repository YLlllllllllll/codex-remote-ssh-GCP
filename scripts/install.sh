#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCAL_USER="$(id -un)"
REAL_HOME="$(dscl . -read "/Users/${LOCAL_USER}" NFSHomeDirectory 2>/dev/null | awk '{ print $2; exit }')"
HOME_DIR="${CODEX_GCP_INSTALL_HOME:-${REAL_HOME:-${HOME:?}}}"
CONFIG_DIR="$HOME_DIR/.config/codex-gcp-refresh"
BIN_DIR="$HOME_DIR/bin"
LAUNCH_DIR="$HOME_DIR/Library/LaunchAgents"

mkdir -p "$CONFIG_DIR" "$BIN_DIR" "$LAUNCH_DIR"

if [[ ! -f "$CONFIG_DIR/config.env" ]]; then
  cp "$ROOT/config.env.example" "$CONFIG_DIR/config.env"
  echo "Created $CONFIG_DIR/config.env; edit it before running refresh commands."
fi

install -m 0755 "$ROOT/bin/kinit-refresh" "$BIN_DIR/kinit-refresh"
install -m 0755 "$ROOT/bin/codex-gcp-remote" "$BIN_DIR/codex-gcp-remote"
install -m 0755 "$ROOT/bin/codex-gcp-forward-session" "$BIN_DIR/codex-gcp-forward-session"
install -m 0755 "$ROOT/bin/codex-gcp-monitor" "$BIN_DIR/codex-gcp-monitor"
install -m 0755 "$ROOT/bin/codex-gcp-autoheal" "$BIN_DIR/codex-gcp-autoheal"
install -m 0755 "$ROOT/bin/codex-workspace-proxy" "$BIN_DIR/codex-workspace-proxy"
install -m 0755 "$ROOT/bin/stay-awake.sh" "$BIN_DIR/stay-awake.sh"

swiftc "$ROOT/app/kinit-refresh-status.swift" -o "$BIN_DIR/kinit-refresh-status"

sed "s#@HOME@#$HOME_DIR#g" "$ROOT/launchd/com.example.kinit-refresh.plist" > "$LAUNCH_DIR/com.example.kinit-refresh.plist"
sed "s#@HOME@#$HOME_DIR#g" "$ROOT/launchd/com.example.kinit-refresh-status.plist" > "$LAUNCH_DIR/com.example.kinit-refresh-status.plist"
sed "s#@HOME@#$HOME_DIR#g" "$ROOT/launchd/com.example.stay-awake.plist" > "$LAUNCH_DIR/com.example.stay-awake.plist"
sed "s#@HOME@#$HOME_DIR#g" "$ROOT/launchd/com.example.codex-gcp-forward.plist" > "$LAUNCH_DIR/com.example.codex-gcp-forward.plist"
sed "s#@HOME@#$HOME_DIR#g" "$ROOT/launchd/com.example.codex-gcp-monitor.plist" > "$LAUNCH_DIR/com.example.codex-gcp-monitor.plist"
sed "s#@HOME@#$HOME_DIR#g" "$ROOT/launchd/com.example.codex-gcp-autoheal.plist" > "$LAUNCH_DIR/com.example.codex-gcp-autoheal.plist"

launchctl bootout "gui/$(id -u)" "$LAUNCH_DIR/com.example.kinit-refresh.plist" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$LAUNCH_DIR/com.example.kinit-refresh.plist" 2>/dev/null || true
launchctl kickstart -k "gui/$(id -u)/com.example.kinit-refresh" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$LAUNCH_DIR/com.example.kinit-refresh-status.plist" 2>/dev/null || true
launchctl kickstart -k "gui/$(id -u)/com.example.kinit-refresh-status" 2>/dev/null || true
launchctl bootout "gui/$(id -u)" "$LAUNCH_DIR/com.example.codex-gcp-monitor.plist" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$LAUNCH_DIR/com.example.codex-gcp-monitor.plist" 2>/dev/null || true
launchctl kickstart -k "gui/$(id -u)/com.example.codex-gcp-monitor" 2>/dev/null || true
launchctl bootout "gui/$(id -u)" "$LAUNCH_DIR/com.example.codex-gcp-autoheal.plist" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$LAUNCH_DIR/com.example.codex-gcp-autoheal.plist" 2>/dev/null || true
launchctl kickstart -k "gui/$(id -u)/com.example.codex-gcp-autoheal" 2>/dev/null || true

cat <<EOF
Installed.

Next:
  1. Edit $CONFIG_DIR/config.env
  2. Run: kinit-refresh save-password
  3. Run: kinit-refresh remote-gcp
  4. Monitor: codex-gcp-monitor status
  5. Autoheal: codex-gcp-autoheal status
EOF
