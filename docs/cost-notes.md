# Cost Notes

The GCP VM is used as an SSH-based egress proxy. Expensive activity usually comes from traffic volume:

- Codex app-server reconnect loops.
- Multiple long-lived remote Codex sessions.
- Repeated `codex exec` validation attempts.
- Large WebSocket or backend API traffic through the proxy.
- Leaving the tunnel active while many remote processes keep using it.

CPU can spike during encrypted SSH forwarding, but normal idle CPU should be near zero.

Useful checks:

```bash
ssh gcp-codex-443 'uptime; ps -eo pid,ppid,user,stat,etime,%cpu,%mem,args --sort=-%cpu | head -30'
ssh gcp-codex-443 'cat /proc/net/dev'
lsof -nP -iTCP:1080 -iTCP:7890
cat ~/.codex-gcp-tunnel/active-sessions.txt
```

To stop egress immediately:

```bash
kinit-refresh stop-gcp
```

That disables remote Codex GCP egress until `kinit-refresh remote-gcp` is run again.

Lower-level controls:

```bash
codex-gcp-remote stop-egress       # stop local 1080/7890 only
codex-gcp-remote clean-workers     # kill stale remote codex exec workers
codex-gcp-remote traffic-sample 20 # sample GCP interface counters
codex-gcp-remote limit-egress      # stop, clean, then verify traffic drop
```

Default guardrails:

- `STALE_CODEX_EXEC_MIN_AGE=1800`: only stale remote `codex exec` workers older than 30 minutes are cleaned.
- `CODEX_EXEC_CLEAN_MARKER`: optional marker used by live CI to clean only test workers.
- `GCP_TRAFFIC_SAMPLE_SECONDS=20`: traffic verification sample window.
- `GCP_TRAFFIC_LIMIT_BYTES=10485760`: total RX+TX bytes allowed during the sample before the command exits non-zero.
- `TRAFFIC_24H_WARN_BYTES=1073741824`: menu traffic status turns warning at 1 GiB/24h.
- `TRAFFIC_24H_CRITICAL_BYTES=3221225472`: menu traffic status turns critical at 3 GiB/24h.

Regression checks:

```bash
scripts/fake-repair-ci.sh  # no side effects
scripts/live-egress-ci.sh  # opens GCP briefly, verifies, then stops it
```
