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
```

To stop egress immediately:

```bash
kill "$(lsof -tiTCP:1080 -sTCP:LISTEN)" "$(lsof -tiTCP:7890 -sTCP:LISTEN)" 2>/dev/null || true
```

That disables remote Codex GCP egress until `kinit-refresh remote-gcp` is run again.
