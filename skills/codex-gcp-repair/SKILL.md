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

Use this when the user reports reconnecting or wants the live GCP tunnel repaired. It captures a health snapshot, keeps healthy layers, performs the smallest required repair, and verifies the result:

```bash
REAL_HOME="$(dscl . -read "/Users/$(id -un)" NFSHomeDirectory 2>/dev/null | awk '{print $2; exit}')"
REAL_HOME="${REAL_HOME:-/Users/$(id -un)}"
"$REAL_HOME/bin/kinit-refresh" recover-flap
```

The status-bar app's `一键恢复波动` menu item runs the same command. Use
`remote-gcp` only when an explicit full rebuild is required.

Manual repair also cleans stale remote state. It may reset local `1080/7890`, remote `10800`, stale SSH tunnel sessions, remote app-server/proxy state, and `codex exec` workers older than `STALE_CODEX_EXEC_MIN_AGE`. It must not blindly kill every remote Codex process, because fresh user work may still be legitimate.

## Emergency Stop / Cost Control

Use this when the user reports unexpected GCP billing, high traffic, or says no Codex jobs should be running. This stops the local GCP data plane, cleans stale remote `codex exec` workers, and verifies the GCP interface traffic dropped:

```bash
REAL_HOME="$(dscl . -read "/Users/$(id -un)" NFSHomeDirectory 2>/dev/null | awk '{print $2; exit}')"
REAL_HOME="${REAL_HOME:-/Users/$(id -un)}"
"$REAL_HOME/bin/kinit-refresh" stop-gcp
```

Then validate:

```bash
lsof -nP -iTCP:1080 -sTCP:LISTEN
lsof -nP -iTCP:7890 -sTCP:LISTEN
"$REAL_HOME/bin/codex-gcp-remote" traffic-sample 20
REMOTE_HOST="$(
  . "$REAL_HOME/.config/codex-gcp-refresh/config.env"
  printf '%s\n' "${REMOTE_HOST:-${SSH_PROBE_TARGET:-}}"
)"
ssh "$REMOTE_HOST" 'ps -eo args | awk "/codex exec/ && !/awk/ {c++} END {print c+0}"'
```

Expected result:

- No local `1080` or `7890` listener.
- `traffic-sample` reports `traffic_status=ok` with only small byte deltas.
- Remote stale `codex exec` count is `0`, or only fresh jobs younger than `STALE_CODEX_EXEC_MIN_AGE` remain.

Important: scheduled Kerberos refresh must run `kinit-refresh ssh-only`, not bare `kinit-refresh`, otherwise it will periodically reopen the GCP tunnel.

## Fake Repair CI

Use this for script/app/skill edits and for your own validation. It must be the default test path because it does not kill processes, change routes, bind ports, SSH to the remote workspace, or touch Codex.app:

```bash
scripts/fake-repair-ci.sh
```

Do not run the live one-shot repair merely to test code changes. Run the live repair only when the user explicitly wants the actual tunnel fixed or when the user has accepted the disruption.

## Live Egress CI

Use this only when the user explicitly asks for a full live test. It briefly opens the GCP path, verifies that requested Codex traffic goes through remote `10800`, creates marker-scoped fake stale workers, then stops GCP egress and verifies low traffic:

```bash
scripts/live-egress-ci.sh --yes
```

The live CI must end by running `kinit-refresh stop-gcp`. If it fails midway, inspect `/tmp/kinit-refresh.status`, local `1080/7890`, remote `codex exec`, and `codex-gcp-remote traffic-sample 20`.

Use `scripts/live-egress-ci.sh --dry-run` first when validating changes or reviewing a new configuration.

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

After changing any GCP path script or config, run the post-change stability gate before declaring the path stable:

```bash
"$REAL_HOME/bin/codex-gcp-stability-check" --duration 600 --interval 60
```

Expected result:

- `verify-fast` passes.
- Full remote `codex exec` returns `openai-ok`.
- Monitor samples stay `STATUS=ok`.
- `GCP_TCP=ok`, proving the tunnel can be rebuilt after company WiFi and external WiFi + VPN route changes.
- Remote `10800` dangerous stale sockets stay below threshold.
- Local `TIME_WAIT` stays below the configured headroom limits.

## If It Still Fails

Run the passive monitor history and read-only diagnosis first:

```bash
REAL_HOME="$(dscl . -read "/Users/$(id -un)" NFSHomeDirectory 2>/dev/null | awk '{print $2; exit}')"
REAL_HOME="${REAL_HOME:-/Users/$(id -un)}"
"$REAL_HOME/bin/codex-gcp-monitor" status
"$REAL_HOME/bin/codex-gcp-monitor" tail 120
```

Then run diagnosis:

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

## Passive Monitor

The monitor is intended to collect evidence before random disconnects:

```bash
"$REAL_HOME/bin/codex-gcp-monitor" status
"$REAL_HOME/bin/codex-gcp-monitor" tail 120
```

It writes JSONL to `$REAL_HOME/.codex-gcp-tunnel/monitor.jsonl` and a latest summary to `$REAL_HOME/.codex-gcp-tunnel/monitor-latest.env`. It is read-only and must not be used as a repair mechanism.

The monitor splits remote `10800` sockets into active, total stale,
dangerous stale (`CLOSE-WAIT`/`FIN-WAIT`/`LAST-ACK`/`CLOSING`), and
`TIME-WAIT`. Treat dangerous stale growth as a real socket leak signal.
Plain `TIME-WAIT` alone is normal short-lived traffic and must not trigger
session-disrupting repairs while the data plane is healthy.

Fresh workspace SSH connections have a different latency distribution from
HTTP probes. The monitor uses a separate 10-second SSH timeout with up to three
bounded attempts so one delayed banner is not reported as a broken data plane;
three failed attempts still produce `remote_ssh_fail_255`.

For Codex CLI 0.144 and later, keep Privoxy `socket-timeout 1800`. The old
30-second timeout can terminate a valid silent reasoning interval and surface
as repeated `Reconnecting` on `gpt-5.6-sol`. Keep the built-in `openai`
provider and official model catalog; do not add a custom transport provider.
The remote wrapper may disable Apps initialization and online remote-plugin
catalog refresh, while installed plugins and skills remain available.

The status-bar app reads `monitor-latest.env` and shows GCP traffic next to `修复 GCP` as `今日 ... / 24h ...`. Treat warning or critical traffic as a cost investigation signal before running another repair.

It also shows `Codex Sessions: N`. This is the remote `codex exec` worker count. Expand it to inspect `$REAL_HOME/.codex-gcp-tunnel/active-sessions.txt`, which includes PID, PPID, age, CPU, memory, and command summary for mismatch debugging.
