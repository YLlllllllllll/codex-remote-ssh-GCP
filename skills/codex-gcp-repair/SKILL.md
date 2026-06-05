---
name: codex-gcp-repair
description: Use when fixing, refreshing, diagnosing, or stabilizing the user's Codex Remote GCP egress path, including kinit-refresh, local 1080/7890, remote 10800, SSH reverse forwarding, or Codex reconnecting caused by the remote GCP proxy path. Always separate the ModelHub Codex session from the official local Codex.app and never modify local official Codex app state.
metadata:
  short-description: Repair Codex Remote GCP egress
---

# Codex GCP Repair

## Boundaries

- The current agent may run inside ModelHub Codex. Its `$HOME` can be a ModelHub home and must not be treated as the official local Codex home.
- Do not launch, quit, kill, reinstall, reset, or change environment for `/Applications/Codex.app`.
- Do not modify or delete the official local Codex state under the real user home, including `.codex`, `Library/Application Support/Codex`, Keychain, cookies, or app login data.
- Do not set or unset user `launchctl` environment variables for `HOME`, `CODEX_HOME`, `HTTP_PROXY`, `HTTPS_PROXY`, `ALL_PROXY`, or related proxy variables.
- Stay inside the remote GCP repair surface: `$REAL_HOME/bin/kinit-refresh`, `$REAL_HOME/bin/codex-gcp-remote`, local `127.0.0.1:1080`, local `127.0.0.1:7890`, remote `127.0.0.1:10800`, and the remote Codex app-server processes.

## One-Shot Repair

Use this only when the user wants the live GCP tunnel repaired. It is intentionally the simplest supported path and maps to forced cleanup, rebuild, and verification:

```bash
REAL_HOME="$(dscl . -read "/Users/$(id -un)" NFSHomeDirectory 2>/dev/null | awk '{print $2; exit}')"
REAL_HOME="${REAL_HOME:-/Users/$(id -un)}"
"$REAL_HOME/bin/kinit-refresh" remote-gcp
```

The status-bar app's `修复 GCP` menu item should run the same command. Do not choose alternate repair variants unless the user explicitly asks for debugging.

## Fake Repair CI

Use this for script/app/skill edits and for your own validation. It must be the default test path because it does not kill processes, change routes, bind ports, SSH to the remote workspace, or touch Codex.app:

```bash
scripts/fake-repair-ci.sh
```

Do not run the live one-shot repair merely to test code changes. Run the live repair only when the user explicitly wants the actual tunnel fixed or when the user has accepted the disruption.

## Required Validation

Do not trust a stale green menu icon by itself. After a live repair, verify the data plane:

```bash
REAL_HOME="$(dscl . -read "/Users/$(id -un)" NFSHomeDirectory 2>/dev/null | awk '{print $2; exit}')"
REAL_HOME="${REAL_HOME:-/Users/$(id -un)}"
sed -n '1,80p' /tmp/kinit-refresh.status
"$REAL_HOME/bin/codex-gcp-remote" verify-fast
```

Expected result:

- `/tmp/kinit-refresh.status` has `STATUS=ok`, `PROXY=ok`, and `CODEX=ok`.
- Remote `127.0.0.1:10800` returns the configured GCP egress IP through `https://api.ipify.org`.
- `https://chatgpt.com/backend-api/codex/responses` through remote `10800` returns a reachable HTTP status, normally `405`.

## If It Still Fails

Run read-only diagnosis first:

```bash
REAL_HOME="$(dscl . -read "/Users/$(id -un)" NFSHomeDirectory 2>/dev/null | awk '{print $2; exit}')"
REAL_HOME="${REAL_HOME:-/Users/$(id -un)}"
"$REAL_HOME/bin/codex-gcp-remote" diagnose
```

Then repair once more with the one-shot command. Report the failing layer only after those checks:

- local SOCKS `1080`
- local HTTP `7890`
- remote `10800`
- SSH ControlMaster/reverse forward
- remote Codex app-server environment
- GCP egress reachability

Keep the fix focused on those layers.
