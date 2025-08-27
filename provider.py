import asyncio, os, socket, sys
import argparse, base64, json
from pathlib import Path

ap = argparse.ArgumentParser(description="Provide keypairs for tre-kiosk")
ap.add_argument("--machine-key", required=True, help="input filename with two hex-encoded lines")
ap.add_argument("--session-key", required=True, help="input filename with two hex-encoded lines")
args = ap.parse_args()

# Simple in-memory key/value source (replace with Vault/KMS fetch if you like)
def get_secret(unit_name: str, cred_name: str) -> bytes:
    machineKeys = readFile(args.machine_key)
    sessionKeys = readFile(args.session_key)

    # for tre-server, we return the keypair,
    # and the session public key in authorizedKeys
    serverConfig = json.dumps({
        "keys": {
            "curve":"ed25519",
            "private": machineKeys[0] + ".ed25519",
            "public": machineKeys[1] + ".ed25519",
            "id": '@' + machineKeys[1] + ".ed25519",
        },
        "authorizedKeys": ["@" + sessionKeys[1]+".ed25519:*"]
    }, separators=(",", ":"))

    browserConfig = json.dumps({
        "keys": {
            "curve":"ed25519",
            "private": sessionKeys[0] + ".ed25519",
            "public": sessionKeys[1] + ".ed25519",
            "id": '@' + sessionKeys[1] + ".ed25519",
        }
    }, separators=(",", ":"))

    val = None
    if cred_name == "server": 
        val = serverConfig
    else:
        if cred_name == "browser":
            val = browserConfig

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

def hex_to_b64(s: str) -> str:
    s = s.strip()
    if s.startswith(("0x", "0X")):
        s = s[2:]
    if len(s) % 2 != 0:
        raise ValueError("hex string must have an even number of digits")
    b = bytes.fromhex(s)
    # Standard RFC 4648 base64 (same as Node.js Buffer.from(...).toString('base64'))
    return base64.b64encode(b).decode("ascii")

def readFile(input):
    p = Path(input)
    try:
        with p.open("r", encoding="utf-8") as f:
            # take first two non-empty lines
            lines = [ln.strip() for ln in f if ln.strip()][:2]
    except OSError as e:
        print(f"error: cannot read {p}: {e}", file=sys.stderr)
        sys.exit(1)

    if len(lines) < 2:
        print("error: need at least two non-empty lines of hex", file=sys.stderr)
        sys.exit(2)

    try:
        # in ssb, the private key contains the public key at the end
        private_b64 = hex_to_b64(lines[0] + lines[1])
        public_b64 = hex_to_b64(lines[1])
    except ValueError as e:
        print(f"error: {e}", file=sys.stderr)
        sys.exit(3)
    return [private_b64, public_b64]

async def main():
    # Socket activation: take FD 3
    LISTEN_FDS = int(os.environ.get("LISTEN_FDS", "0"))
    LISTEN_FDS_START = 3
    if LISTEN_FDS < 1:
        print("No socket passed (LISTEN_FDS=0)", file=sys.stderr)
        sys.exit(0)

    sock = socket.socket(fileno=LISTEN_FDS_START)
    server = await asyncio.start_unix_server(lambda r, w: asyncio.create_task(handle(r, w)), sock=sock)
    async with server:
        await server.serve_forever()

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
