# Network Matrix

The app has to handle four moving parts:

- Physical network: company Wi-Fi, home Wi-Fi, phone hotspot.
- Feilian/VPN: off or on.
- macOS route to the GCP VM.
- SSH ControlMaster and remote `ssh -R` state.

## Company Wi-Fi, Feilian Off

This is the simplest state. Company SSH usually works directly through the normal route. The GCP host route should use the current Wi-Fi gateway, not a VPN interface.

Expected refresh path:

```text
kinit -> kgetcred -> SSH probe -> local 1080/7890 -> remote 10800
```

## Company Wi-Fi, Feilian On

This is a common failure state after forgetting to turn off Feilian. The default route may still look usable, but the GCP host route can be captured by `utun*` or left pinned to an old gateway.

The route helper repairs only the single GCP host route:

```text
route -n change -host $GCP_HOST $CURRENT_DEFAULT_GATEWAY
```

It does not change the system proxy and does not route general traffic through GCP.

## Home Wi-Fi, Feilian On

Company SSH generally needs VPN. GCP should still bypass the VPN through a pinned host route when possible. If the route goes through the VPN, the GCP tunnel can be slow or unstable.

## Phone Hotspot, Feilian On

This works, but latency and packet loss can be higher. First refresh after switching networks may be fast because old ControlMasters still answer. The second refresh can be slow if an old remote `10800` listener remains but its data plane is dead.

## Why Switching Back Can Be Slow

The problematic state is:

```text
remote 127.0.0.1:10800 LISTEN exists
but ssh -R data plane no longer reaches local 127.0.0.1:7890
```

The repair script resets stale ControlMasters, cancels old remote forwards, and retries the probe. If the local SOCKS tunnel was created before the network switch, it may also need to be rebuilt.
