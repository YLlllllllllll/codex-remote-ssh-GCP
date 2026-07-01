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

The menu-bar app reads `/tmp/kinit-refresh.status` and exposes:

- `修复 GCP`: one-shot forced cleanup, rebuild, and validation for the remote Codex GCP path.
- `验证 GCP`: read-only validation of local `1080/7890`, remote `10800`, the GCP egress IP, and the ChatGPT Codex endpoint.
- `诊断 GCP`: writes the local listener state, remote `10800` state, wrapper/config drift, app-server environment, and recent logs to `~/.codex-gcp-tunnel/gcp-diagnose-latest.log`.
- `触发 Auto-Heal`: runs one auto-heal decision cycle without bypassing the consecutive-failure and cooldown guards.
- `查看 Auto-Heal 状态`: writes the latest auto-heal decision and log tail to `~/.codex-gcp-tunnel/autoheal-status-latest.log`.
- `登录/更新 kinit`: prompts once for the Kerberos password, saves it to macOS Keychain, then verifies SSH.
- `刷新 SSH`: refresh/verify Kerberos and company SSH only.
- `重置 Cursor SSH`: runs the independent `cursor-remote-reset` helper so Cursor can reconnect, without touching Codex GCP or quitting the Cursor app.
- `保持唤醒` / `关闭防休眠`: toggles the LaunchAgent-backed stay-awake helper.

`修复 GCP` runs the deep one-shot repair path. It compares the local and remote Codex CLI versions, installs the local version on the remote when they drift, rewrites the remote `10800` proxy wrappers after npm changes, checks local TCP `TIME_WAIT` headroom, stops remote `10800` consumers before resetting local `1080/7890`, lets local TCP pressure settle, rebuilds the full SSH chain, and finishes with `openai-ok`. If final validation itself creates a `10800` socket storm, it captures socket/TCP state, performs one isolated rebuild, and retries validation. It removes stale `codex exec` workers older than `STALE_CODEX_EXEC_MIN_AGE`, stale SSH tunnel sessions, and stale app-server/proxy state. It does not blindly kill every Codex process, so fresh real work is not treated as disposable.

Cursor Remote SSH is deliberately separate from Codex GCP. `修复 GCP`, `remote-gcp`, and auto-heal do not reset Cursor; `重置 Cursor SSH` does not repair, sample, or stop Codex GCP.

When `修复 GCP` succeeds it writes `~/.codex-gcp-tunnel/gcp.enabled`. `stop-gcp` removes that marker. The auto-heal LaunchAgent uses this marker plus the live listener state to decide whether GCP was meant to be on, so it can repair a broken open path without reopening GCP after you intentionally stopped it.

The menu also shows `Codex Sessions: N`. Expand that item to compare the monitor's remote `codex exec` workers against the work you expect to be running. The submenu lists PID, parent PID, age, CPU, memory, and command summary, with buttons to open or copy the latest detail log.

The `修复 GCP` menu title also shows read-only GCP traffic counters from the passive monitor:

```text
修复 GCP    流量 今日 12.3 MiB / 24h 18.7 MiB / 当前 32.0 KiB/s
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
kinit-refresh --dry-run remote-gcp
kinit-refresh ssh-only
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
codex-gcp-remote deep-repair
codex-gcp-remote clean-repair-fast
codex-gcp-remote verify-fast
```

## Passive Monitor

`codex-gcp-monitor` is installed as a LaunchAgent and samples the GCP path every 60 seconds. It is read-only: it does not repair, kill processes, bind ports, change routes, or touch Codex.app.

It records:

- local listeners on `1080` and `7890`
- route/interface used for the GCP VM
- GCP VM interface RX/TX counters, today total, 24h total, and recent rate
- remote `codex exec` worker count and latest session detail log
- local `7890` egress IP
- remote `10800` listener and egress IP
- ChatGPT endpoint HTTP code through remote `10800`
- remote app-server and SSH notty process counts
- latest `/tmp/kinit-refresh.status`

Common commands:

```bash
codex-gcp-monitor status
codex-gcp-monitor tail
codex-gcp-monitor path
```

Logs are stored under `~/.codex-gcp-tunnel/`:

```text
monitor.jsonl
monitor-latest.env
active-sessions.txt
autoheal.log
```

## Auto-Heal

`codex-gcp-autoheal` is installed as a separate LaunchAgent and runs every 60 seconds. It is intentionally separate from the passive monitor.

It runs `kinit-refresh remote-gcp` only when all of these are true:

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
AUTOHEAL_MAX_SAMPLE_AGE_SECONDS=300
AUTOHEAL_REPAIR_MODE=remote-gcp
```

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
kinit-refresh --dry-run remote-gcp
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
