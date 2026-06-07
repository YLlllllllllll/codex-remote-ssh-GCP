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
- `刷新 SSH`: refresh/verify Kerberos and company SSH only.
- `保持唤醒` / `关闭防休眠`: toggles the LaunchAgent-backed stay-awake helper.

The `修复 GCP` menu title also shows read-only GCP traffic counters from the passive monitor:

```text
修复 GCP    流量 今日 12.3 MiB / 24h 18.7 MiB
```

The displayed total is RX+TX on the GCP VM interface. It is meant as an anomaly indicator: normal text-only Codex usage should stay far below GiB/day; multi-GiB/day means stale sessions or reconnect loops are likely.

## Install

1. Copy `config.env.example` to `~/.config/codex-gcp-refresh/config.env`.
2. Fill in the real principal, remote workspace host, GCP VM host, user, and key path.
3. Run:

```bash
scripts/install.sh
```

4. Save the Kerberos password to Keychain if needed:

```bash
kinit-refresh save-password
```

## Manual Commands

```bash
kinit-refresh status
kinit-refresh ssh-only
kinit-refresh remote-gcp
kinit-refresh stop-gcp
kinit-refresh log
codex-gcp-remote diagnose
codex-gcp-remote limit-egress
codex-gcp-remote clean-workers
codex-gcp-remote traffic-sample 20
codex-gcp-remote clean-repair-fast
codex-gcp-remote verify-fast
```

## Passive Monitor

`codex-gcp-monitor` is installed as a LaunchAgent and samples the GCP path every 60 seconds. It is read-only: it does not repair, kill processes, bind ports, change routes, or touch Codex.app.

It records:

- local listeners on `1080` and `7890`
- route/interface used for the GCP VM
- GCP VM interface RX/TX counters, today total, 24h total, and recent rate
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
```

## Non-Disruptive CI

Use this when editing the scripts. It does not kill processes, change routes, bind ports, SSH to the remote workspace, or touch Codex.app:

```bash
scripts/fake-repair-ci.sh
```

For an explicit live smoke test, use:

```bash
scripts/live-egress-ci.sh
```

This one is intentionally named as live CI because it briefly opens the GCP egress path, verifies remote `10800` and ChatGPT endpoint reachability, creates marker-scoped fake stale workers, then runs `kinit-refresh stop-gcp` and verifies the tunnel is closed with low GCP traffic. Do not run it while real long-running `codex exec` jobs are expected to remain active.

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
