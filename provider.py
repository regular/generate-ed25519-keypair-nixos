import asyncio, os, socket, sys
from pathlib import Path

# Simple in-memory key/value source (replace with Vault/KMS fetch if you like)
def get_secret(unit_name: str, cred_name: str) -> bytes:
    # Example: allow per-unit overrides via /etc/cred-provider.d/<unit>/<name>
    p = Path(f"/etc/cred-provider.d/{unit_name}/{cred_name}")
    if p.is_file():
        return p.read_bytes()
    # Fallback to env file values
    val = os.environ.get(cred_name.upper())
    if val is None:
        raise KeyError(f"no secret for {cred_name} (unit {unit_name})")
    return val.encode("utf-8")

def parse_peername(writer) -> tuple[str, str]:
    """
    systemd exposes service + credential in the UNIX peer info.
    Peer name looks like: ".../<service>.service/<credential>"
    """
    peer = writer.get_extra_info("peername")
    if not peer:
        raise RuntimeError("no peername from systemd")
    s = peer.decode("utf-8")
    # defensively split from the right
    parts = s.rsplit("/", 2)
    if len(parts) < 3:
        raise RuntimeError(f"bad peername: {s}")
    _, service, cred = parts
    # Normalize service name "foo.service" -> "foo"
    if service.endswith(".service"):
        service = service[:-8]
    return service, cred

async def handle(reader, writer):
    try:
        unit, cred = parse_peername(writer)
        data = get_secret(unit, cred)
        writer.write(data)
        await writer.drain()
    except Exception as e:
        # Don’t leak details to caller; just fail closed
        sys.stderr.write(f"cred-provider error: {e}\n")
    finally:
        writer.close()
        try:
            await writer.wait_closed()
        except Exception:
            pass

async def main():
    # Socket activation: take FD 3
    LISTEN_FDS = int(os.environ.get("LISTEN_FDS", "0"))
    LISTEN_FDS_START = 3
    if LISTEN_FDS < 1:
        print("No socket passed (LISTEN_FDS=0)", file=sys.stderr)
        sys.exit(0)

    # Load env file if present
    envfile = "/etc/cred-provider.env"
    if os.path.exists(envfile):
        for line in Path(envfile).read_text().splitlines():
            if not line.strip() or line.strip().startswith("#"): continue
            k, _, v = line.partition("=")
            os.environ.setdefault(k.strip(), v)

    sock = socket.socket(fileno=LISTEN_FDS_START)
    server = await asyncio.start_unix_server(lambda r, w: asyncio.create_task(handle(r, w)), sock=sock)
    async with server:
        await server.serve_forever()

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
