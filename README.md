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

- `刷新 SSH`: refresh/verify Kerberos and company SSH only.
- `刷新 Remote GCP`: repair the local GCP tunnel and remote Codex proxy path.
- `强制清理 Remote GCP`: kill stale local/remote proxy state and rebuild the fast path.
- `完整验证 Remote GCP`: also checks remote wrapper/config drift.
- `开启/停止防休眠`: controls the LaunchAgent-backed stay-awake helper.
- `打开日志`: opens `/tmp/kinit-refresh.log`.

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
kinit-refresh remote-gcp-clean
kinit-refresh remote-gcp-full
kinit-refresh log
codex-gcp-remote diagnose
codex-gcp-remote repair-fast
codex-gcp-remote clean-repair-fast
codex-gcp-remote verify-fast
```

## Cost Controls

The GCP VM is an egress proxy. Cost is usually dominated by network traffic, not CPU. Stop the tunnel when it is not needed:

```bash
kill "$(lsof -tiTCP:1080 -sTCP:LISTEN)" "$(lsof -tiTCP:7890 -sTCP:LISTEN)" 2>/dev/null || true
```

See `docs/network-matrix.md` and `docs/cost-notes.md`.
