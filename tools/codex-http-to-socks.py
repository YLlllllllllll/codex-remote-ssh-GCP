#!/usr/bin/env python3
import argparse
import asyncio
import ipaddress
import signal
import struct
from urllib.parse import urlsplit


def parse_host_port(value, default_port):
    if value.startswith("["):
        host, rest = value[1:].split("]", 1)
        port = int(rest[1:]) if rest.startswith(":") else default_port
        return host, port
    if ":" in value:
        host, port = value.rsplit(":", 1)
        return host, int(port)
    return value, default_port


async def socks_connect(socks_host, socks_port, target_host, target_port):
    reader, writer = await asyncio.open_connection(socks_host, socks_port)
    writer.write(b"\x05\x01\x00")
    await writer.drain()
    data = await reader.readexactly(2)
    if data != b"\x05\x00":
        raise RuntimeError("SOCKS auth negotiation failed")

    try:
        ip = ipaddress.ip_address(target_host)
    except ValueError:
        host_bytes = target_host.encode("idna")
        atyp = b"\x03"
        addr = bytes([len(host_bytes)]) + host_bytes
    else:
        atyp = b"\x01" if ip.version == 4 else b"\x04"
        addr = ip.packed

    writer.write(b"\x05\x01\x00" + atyp + addr + struct.pack("!H", target_port))
    await writer.drain()
    head = await reader.readexactly(4)
    if head[1] != 0:
        raise RuntimeError(f"SOCKS connect failed: {head[1]}")
    atyp = head[3]
    if atyp == 1:
        await reader.readexactly(4)
    elif atyp == 3:
        size = await reader.readexactly(1)
        await reader.readexactly(size[0])
    elif atyp == 4:
        await reader.readexactly(16)
    await reader.readexactly(2)
    return reader, writer


async def pipe(reader, writer):
    try:
        while True:
            data = await reader.read(65536)
            if not data:
                break
            writer.write(data)
            await writer.drain()
    finally:
        try:
            writer.close()
            await writer.wait_closed()
        except Exception:
            pass


async def handle_client(client_reader, client_writer, socks_host, socks_port):
    upstream_writer = None
    try:
        header = await asyncio.wait_for(client_reader.readuntil(b"\r\n\r\n"), timeout=10)
        lines = header.split(b"\r\n")
        method, target, version = lines[0].decode("latin1").split(" ", 2)
        method_upper = method.upper()

        if method_upper == "CONNECT":
            host, port = parse_host_port(target, 443)
            upstream_reader, upstream_writer = await socks_connect(socks_host, socks_port, host, port)
            client_writer.write(b"HTTP/1.1 200 Connection established\r\n\r\n")
            await client_writer.drain()
        else:
            url = urlsplit(target)
            if not url.scheme or not url.hostname:
                client_writer.write(b"HTTP/1.1 405 Method Not Allowed\r\nConnection: close\r\n\r\n")
                await client_writer.drain()
                return
            port = url.port or (443 if url.scheme == "https" else 80)
            upstream_reader, upstream_writer = await socks_connect(socks_host, socks_port, url.hostname, port)
            path = url.path or "/"
            if url.query:
                path += "?" + url.query
            lines[0] = f"{method_upper} {path} {version}".encode("latin1")
            upstream_writer.write(b"\r\n".join(lines) + b"\r\n\r\n")
            await upstream_writer.drain()

        await asyncio.gather(
            pipe(client_reader, upstream_writer),
            pipe(upstream_reader, client_writer),
        )
    except Exception:
        try:
            client_writer.write(b"HTTP/1.1 502 Bad Gateway\r\nConnection: close\r\n\r\n")
            await client_writer.drain()
        except Exception:
            pass
    finally:
        for writer in (client_writer, upstream_writer):
            if writer is not None:
                try:
                    writer.close()
                    await writer.wait_closed()
                except Exception:
                    pass


async def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--listen-host", default="127.0.0.1")
    parser.add_argument("--listen-port", type=int, default=10800)
    parser.add_argument("--socks-host", default="127.0.0.1")
    parser.add_argument("--socks-port", type=int, default=10801)
    args = parser.parse_args()

    server = await asyncio.start_server(
        lambda r, w: handle_client(r, w, args.socks_host, args.socks_port),
        args.listen_host,
        args.listen_port,
    )
    loop = asyncio.get_running_loop()
    stop = asyncio.Event()
    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, stop.set)
    async with server:
        await stop.wait()


if __name__ == "__main__":
    asyncio.run(main())
