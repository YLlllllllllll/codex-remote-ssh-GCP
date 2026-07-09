# Codex GCP Refresh App

macOS menu-bar helper and shell tooling for keeping a remote Codex development box on a controlled GCP egress path.

The intended path is:

```text
remote Codex -> remote 127.0.0.1:10800 HTTP
             -> ssh -R to local 127.0.0.1:7890
             -> local privoxy
             -> local 127.0.0.1:1080 SOCKS
             -> ssh -D to GCP VM on port 443
             -> GCP egress
```

The remote wrapper keeps the official OpenAI provider, model catalog, and
ChatGPT login. It disables ChatGPT Apps initialization and skips the online
remote plugin catalog refresh; installed local plugins and skills remain
available. Privoxy uses a 30-minute socket timeout so valid long-reasoning
silence on Responses WebSockets is not mistaken for a dead tunnel.
Fresh remote SSH monitor probes use a separate 10-second timeout and retry up
to three times so a single workspace-gateway banner delay is not reported as a
broken Codex path.

The menu-bar app reads `/tmp/kinit-refresh.status` and exposes:

- `一键恢复波动`: the normal incident button for Codex reconnecting, ChatGPT
  `000`, local `1080` data-plane hangs, local `7890` failures, and remote
  `10800` socket storms. It runs `debug-fast`, uses the monitor to choose the
  smallest repair, then finishes with `verify-fast` and a final monitor sample.
- `智能修复`: samples current state, verifies the local official Codex app/config, then chooses the smallest targeted repair for Cursor SSH, local `1080`, local `7890`, remote `10800`, or version/wrapper drift.
- `登录/更新 kinit`: prompts once for the Kerberos password, saves it to macOS Keychain, then verifies SSH.
- `保持唤醒` / `关闭防休眠`: toggles the LaunchAgent-backed stay-awake helper.
- `Codex Sessions`: expands to remote `codex exec`, `10800`, and app-server session details.
- `高级`: contains read-only GCP validation, diagnosis, incident logs, auto-heal controls, SSH refresh, and manual Cursor SSH reset.

`一键恢复波动` is the button to use during an active reconnecting incident. It
first runs `codex-gcp-remote debug-fast`, which snapshots the live path and only
repairs what is already broken. It then samples `codex-gcp-monitor`, runs
`智能修复` if the path is still unhealthy, clears dangerous remote `10800` stale
sockets only after the local data plane is healthy, and finishes with
`codex-gcp-remote verify-fast`.

`智能修复` is the targeted repair engine behind that button. It first checks whether local Cursor Remote SSH has a stuck install/tunnel process group and resets only that group when needed. It then runs `codex-gcp-monitor sample`, reads `monitor-latest.env`, and maps the failure cause to a narrow command: `repair-local-socks` for local `1080` missing or `local_1080_bad_egress`, `repair-local-http` for local `7890`, `repair-remote-forward` for remote `10800`/ChatGPT data-plane failures, and `repair-remote-sockets` for excessive dangerous stale remote `10800` sockets. It only escalates to `deep-repair` when the narrow repair and `repair-fast` do not recover the path, or when local/remote Codex version, default model, or wrapper checks detect drift.

The local official Codex check verifies `/Applications/Codex.app` is signed by OpenAI, the `codex` CLI points at `/Applications/Codex.app/Contents/Resources/codex`, and `~/.codex/config.toml` does not contain provider overrides such as `model_provider`, `model_providers`, `base_url`, `OPENAI_BASE_URL`, ModelHub/Azure endpoints, `CODEX_HOME=~/.codex-modelhub`, or legacy `18080/18081` proxy state. A notification hook path under `.codex-modelhub` is not treated as provider pollution. If a shell launches with `CODEX_HOME=~/.codex-modelhub`, the check logs that as a warning because Codex CLI from that shell will read the modelhub home instead of the official `~/.codex` home.

Cursor Remote SSH remains separate from Codex GCP. The independent `cursor-remote-reset` helper only resets Cursor Remote SSH process groups; it does not repair, sample, or stop Codex GCP. `智能修复` only calls it when the status probe sees stuck Cursor Remote SSH install/tunnel groups.

When `智能修复` succeeds it writes `~/.codex-gcp-tunnel/gcp.enabled`. `stop-gcp` removes that marker. The auto-heal LaunchAgent uses this marker plus the live listener state to decide whether GCP was meant to be on, so it can repair a broken open path without reopening GCP after you intentionally stopped it.

The menu also shows `Codex Sessions: N`. Expand that item to compare the monitor's remote `codex exec` workers against the work you expect to be running. The submenu lists PID, parent PID, age, CPU, memory, and command summary, with buttons to open or copy the latest detail log.

The `智能修复` menu title also shows read-only GCP traffic counters from the passive monitor:

```text
智能修复    流量 今日 12.3 MiB / 24h 18.7 MiB / 当前 32.0 KiB/s
```

The displayed total is RX+TX on the GCP VM interface. It is meant as an anomaly indicator: normal text-only Codex usage should stay far below GiB/day; multi-GiB/day means stale sessions or reconnect loops are likely.

## Install

1. Copy `config.env.example` to `~/.config/codex-gcp-refresh/config.env`.
2. Fill in the real principal, remote workspace host, GCP VM host, user, and key path.
3. Run:

```bash
scripts/install.sh
```

4. Save the Kerberos password to Keychain if needed, either from the menu-bar app with `登录/更新 kinit`, or manually:

```bash
kinit-refresh save-password
```

By default the helper requests a `24h` Kerberos ticket with a `7d` renewable window (`KINIT_LIFETIME=24h`, `KINIT_RENEWABLE_LIFE=7d`). The company KDC policy is authoritative: if renewable tickets are not allowed, the script falls back to a normal kinit so SSH recovery still works when the company network is reachable.

## Manual Commands

```bash
kinit-refresh status
kinit-refresh --dry-run smart-repair
kinit-refresh ssh-only
kinit-refresh smart-repair
kinit-refresh recover-flap
kinit-refresh remote-gcp
kinit-refresh stop-gcp
kinit-refresh log
codex-gcp-autoheal status
codex-gcp-remote --dry-run clean-repair-fast
codex-gcp-remote --dry-run deep-repair
codex-gcp-remote diagnose
codex-gcp-remote limit-egress
codex-gcp-remote clean-workers
codex-gcp-remote traffic-sample 20
codex-gcp-remote repair-local-socks
codex-gcp-remote repair-local-http
codex-gcp-remote repair-remote-forward
codex-gcp-remote repair-remote-sockets
codex-gcp-remote version-status
codex-gcp-remote restart-remote-app-server
codex-gcp-remote deep-repair
codex-gcp-remote clean-repair-fast
codex-gcp-remote verify-fast
```

## Passive Monitor

`codex-gcp-monitor` is installed as a LaunchAgent and samples the GCP path every 60 seconds. It is read-only: it does not repair, kill processes, bind ports, change routes, or touch Codex.app.

It records:

- local listeners and egress IPs on `1080` and `7890`
- route/interface used for the GCP VM
- GCP VM interface RX/TX counters, today total, 24h total, and recent rate
- remote `codex exec` worker count and latest session detail log
- local `1080` and `7890` egress IPs
- remote `10800` listener and egress IP
- ChatGPT endpoint HTTP code through remote `10800`
- remote `10800` socket state split into active, total stale, dangerous stale
  (`CLOSE-WAIT`/`FIN-WAIT`/`LAST-ACK`/`CLOSING`), and `TIME-WAIT`
- remote app-server and SSH notty process counts
- latest `/tmp/kinit-refresh.status`

Common commands:

```bash
codex-gcp-monitor status
codex-gcp-monitor tail
codex-gcp-monitor incidents
codex-gcp-monitor incident-path
codex-gcp-monitor path
```

Logs are stored under `~/.codex-gcp-tunnel/`:

```text
monitor.jsonl
monitor-latest.env
active-sessions.txt
autoheal.log
incidents/
```

When a sample fails, `codex-gcp-monitor` writes a durable incident bundle under
`~/.codex-gcp-tunnel/incidents/`. Each bundle includes the failing
`monitor-latest.env`, session details, local route/proxy state, local
`1080/7890` TCP states, launchd state, direct and proxied reachability probes,
remote `10800` socket state, and tails of the monitor, auto-heal, and SOCKS
logs. `incidents/incidents.jsonl` is append-only and is not rotated with
`monitor.jsonl`, so transient failures can be analyzed later without manually
reproducing them.

## Auto-Heal

`codex-gcp-autoheal` is installed as a separate LaunchAgent and runs every 60 seconds. It is intentionally separate from the passive monitor.

It runs a targeted repair only when all of these are true:

- auto-heal is enabled with `CODEX_GCP_AUTOHEAL_ENABLED=1`
- the latest monitor sample is fresh
- GCP was already intended to be on, either by `gcp.enabled` or existing `1080/7890/10800` listeners
- the monitor has at least `AUTOHEAL_MIN_CONSECUTIVE_FAILS` consecutive failures
- the latest failure cause is a repairable data-plane cause, such as `local_7890_bad_egress`, `remote_10800_bad_egress`, or `chatgpt_unreachable_*`
- the cooldown window has passed

Defaults:

```bash
CODEX_GCP_AUTOHEAL_ENABLED=1
AUTOHEAL_MIN_CONSECUTIVE_FAILS=2
AUTOHEAL_COOLDOWN_SECONDS=900
AUTOHEAL_TARGETED_COOLDOWN_SECONDS=90
AUTOHEAL_BAD_EGRESS_CONSECUTIVE_FAILS=2
AUTOHEAL_CHATGPT_CONSECUTIVE_FAILS=2
AUTOHEAL_MAX_SAMPLE_AGE_SECONDS=300
AUTOHEAL_REPAIR_MODE=remote-gcp
AUTOHEAL_STALE_SOCKET_THRESHOLD=20
AUTOHEAL_ALLOW_APP_SERVER_RESTART=0
```

Auto-heal uses the monitor's dangerous stale socket count, not plain `TIME-WAIT`, to avoid treating normal short-lived traffic as a socket storm. If the data plane is still healthy, it records the high socket count and skips repair rather than disrupting active Codex sessions.

With `AUTOHEAL_ALLOW_APP_SERVER_RESTART=0`, eligible remote `10800` data-plane failures use `codex-gcp-remote repair-remote-sockets`, which rebuilds only the forward/socket layer and leaves Codex app-server processes running. Setting `AUTOHEAL_ALLOW_APP_SERVER_RESTART=1` allows the heavier `reset-socket-storm` path, which can interrupt active sessions and should only be used for controlled recovery windows.

After changing the GCP path scripts or config, run the post-change stability gate before declaring the path stable:

```bash
codex-gcp-stability-check --duration 600 --interval 60
```

The gate runs `verify-fast`, full remote `openai-ok` validation, repeated monitor samples, dangerous stale socket checks, and local `TIME_WAIT` headroom checks.

`kinit-refresh smart-repair` also checks whether a running remote Codex app-server still points at a replaced or deleted CLI binary after an update. In that case it runs `codex-gcp-remote restart-remote-app-server`, which restarts only the remote Codex runtime so the installed CLI version and the UI's running CLI version converge.

Disable it locally by setting `CODEX_GCP_AUTOHEAL_ENABLED=0` in `~/.config/codex-gcp-refresh/config.env`.

## Deep Repair

Use this when Codex Remote is stuck reconnecting, the remote `10800` socket count is high, or local `1080/7890` curls fail with timeout or `Can't assign requested address`:

```bash
codex-gcp-remote deep-repair
```

The command deliberately stops remote consumers before resetting the local data plane. This avoids the reconnect loop where remote `10800` keeps opening new connections while local `1080/7890` is being rebuilt. TCP `TIME_WAIT` sockets cannot be killed directly; the repair stops the sources of new connections, verifies the local TCP `msl` and ephemeral port range settings, waits briefly with `CODEX_TCP_SETTLE_SECONDS`, and then verifies the rebuilt path. If verification fails once, it repeats the isolated rebuild one time before returning failure. Repair and validation commands share a local lock with auto-heal so two repair flows do not reset the same proxy chain concurrently.

## Non-Disruptive CI

Use this when editing the scripts. It does not kill processes, change routes, bind ports, SSH to the remote workspace, or touch Codex.app:

```bash
scripts/fake-repair-ci.sh
```

For an explicit live smoke test, use:

```bash
scripts/live-egress-ci.sh --yes
```

This one is intentionally named as live CI because it briefly opens the GCP egress path, verifies remote `10800` and ChatGPT endpoint reachability, creates marker-scoped fake stale workers, then runs `kinit-refresh stop-gcp` and verifies the tunnel is closed with low GCP traffic. Do not run it while real long-running `codex exec` jobs are expected to remain active.

Preview live or destructive flows first with `--dry-run`:

```bash
kinit-refresh --dry-run smart-repair
codex-gcp-remote --dry-run clean-repair-fast
codex-gcp-remote --dry-run deep-repair
scripts/live-egress-ci.sh --dry-run
```

## Cost Controls

The GCP VM is an egress proxy. Cost is usually dominated by network traffic, not CPU. Stop the tunnel when it is not needed:

```bash
kinit-refresh stop-gcp
```

That disables remote Codex GCP egress until `kinit-refresh remote-gcp` is run again. It also cleans stale remote `codex exec` workers older than `STALE_CODEX_EXEC_MIN_AGE` and samples the GCP VM interface to verify the traffic drop.

Manual lower-level commands:

```bash
codex-gcp-remote stop-egress
codex-gcp-remote clean-workers
codex-gcp-remote traffic-sample 20
```

See `docs/network-matrix.md` and `docs/cost-notes.md`.
