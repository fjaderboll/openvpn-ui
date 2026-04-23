import os
import subprocess
import json
from pathlib import Path
from typing import List, Dict

DATA_DIR = Path(os.environ.get("DATA_DIR", "/data"))
PKI_DIR = DATA_DIR / "pki"
CCD_DIR = DATA_DIR / "ccd"
CONFIG_DIR = DATA_DIR / "config"
CLIENTS_DIR = DATA_DIR / "clients"
LOGS_DIR = DATA_DIR / "logs"
IP_FILE = DATA_DIR / "ip_assignments.json"
EASYRSA = "/usr/share/easy-rsa/easyrsa"
STATUS_FILE = LOGS_DIR / "openvpn-status.log"


def get_ip_assignments() -> Dict[str, str]:
    if IP_FILE.exists():
        return json.loads(IP_FILE.read_text())
    return {}


def save_ip_assignments(assignments: Dict[str, str]):
    IP_FILE.write_text(json.dumps(assignments, indent=2))


def allocate_ip(client_name: str) -> str:
    assignments = get_ip_assignments()
    if client_name in assignments:
        return assignments[client_name]

    subnet = os.environ.get("VPN_SUBNET", "10.8.0.0")
    prefix = ".".join(subnet.split(".")[:3])

    used_ips = set(assignments.values())
    for i in range(2, 255):
        ip = f"{prefix}.{i}"
        if ip not in used_ips:
            assignments[client_name] = ip
            save_ip_assignments(assignments)
            return ip

    raise RuntimeError("No available IP addresses in subnet")


def create_ccd_file(client_name: str, ip: str):
    mask = os.environ.get("VPN_SUBNET_MASK", "255.255.255.0")
    ccd_file = CCD_DIR / client_name
    ccd_file.write_text(f"ifconfig-push {ip} {mask}\n")


def build_ovpn(name: str) -> str:
    host = os.environ.get("VPN_HOST", "vpn.example.com")
    port = os.environ.get("VPN_PORT", "1194")
    proto = os.environ.get("VPN_PROTO", "udp")

    ca = (PKI_DIR / "ca.crt").read_text().strip()
    cert = (PKI_DIR / "issued" / f"{name}.crt").read_text().strip()
    key = (PKI_DIR / "private" / f"{name}.key").read_text().strip()

    template_path = CONFIG_DIR / "client.ovpn.template"
    template = template_path.read_text()

    ovpn = (template
        .replace("{{proto}}", proto)
        .replace("{{host}}", host)
        .replace("{{port}}", port)
        .replace("{{ca}}", ca)
        .replace("{{cert}}", cert)
        .replace("{{key}}", key)
    )

    # Include tls-crypt key if available
    tc_key_path = PKI_DIR / "tc.key"
    if tc_key_path.exists():
        tc_key = tc_key_path.read_text().strip()
        ovpn += f"<tls-crypt>\n{tc_key}\n</tls-crypt>\n"

    return ovpn


def generate_client(name: str) -> str:
    """Generate a new client certificate and .ovpn file."""
    env = os.environ.copy()
    env["EASYRSA_BATCH"] = "1"
    result = subprocess.run(
        [EASYRSA, f"--pki-dir={PKI_DIR}", "build-client-full", name, "nopass"],
        env=env,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise RuntimeError(f"Failed to generate client cert: {result.stderr}")

    ip = allocate_ip(name)
    create_ccd_file(name, ip)

    ovpn = build_ovpn(name)
    ovpn_path = CLIENTS_DIR / f"{name}.ovpn"
    ovpn_path.write_text(ovpn)

    return ovpn


def revoke_client(name: str):
    """Revoke a client certificate and clean up files."""
    env = os.environ.copy()
    env["EASYRSA_BATCH"] = "1"

    result = subprocess.run(
        [EASYRSA, f"--pki-dir={PKI_DIR}", "revoke", name],
        env=env,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise RuntimeError(f"Failed to revoke client: {result.stderr}")

    result = subprocess.run(
        [EASYRSA, f"--pki-dir={PKI_DIR}", "gen-crl"],
        env=env,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise RuntimeError(f"Failed to regenerate CRL: {result.stderr}")

    # Make CRL readable by OpenVPN
    crl_path = PKI_DIR / "crl.pem"
    if crl_path.exists():
        os.chmod(crl_path, 0o644)

    # Remove client files
    ovpn_file = CLIENTS_DIR / f"{name}.ovpn"
    if ovpn_file.exists():
        ovpn_file.unlink()

    ccd_file = CCD_DIR / name
    if ccd_file.exists():
        ccd_file.unlink()

    # Remove IP assignment
    assignments = get_ip_assignments()
    assignments.pop(name, None)
    save_ip_assignments(assignments)


def get_connected_clients() -> Dict[str, dict]:
    """Parse OpenVPN status file to find connected clients."""
    if not STATUS_FILE.exists():
        return {}

    connected = {}
    content = STATUS_FILE.read_text()
    lines = content.strip().split("\n")

    section = None
    for line in lines:
        if line.startswith("OpenVPN CLIENT LIST"):
            section = "clients"
            continue
        if line.startswith("ROUTING TABLE"):
            section = "routing"
            continue
        if line.startswith("GLOBAL STATS"):
            section = None
            continue
        if line.startswith("Updated,") or line.startswith("Common Name,") or line.startswith("Virtual Address,"):
            continue

        if section == "clients":
            parts = line.split(",")
            if len(parts) >= 5:
                name = parts[0]
                connected[name] = {
                    "real_address": parts[1],
                    "bytes_received": int(parts[2]),
                    "bytes_sent": int(parts[3]),
                    "connected_since": parts[4],
                }

        if section == "routing":
            parts = line.split(",")
            if len(parts) >= 4:
                vip = parts[0]
                name = parts[1]
                if name in connected:
                    connected[name]["virtual_address"] = vip

    return connected


def list_clients() -> List[dict]:
    """List all clients with their connection status."""
    assignments = get_ip_assignments()
    connected = get_connected_clients()

    clients = []
    for name, ip in assignments.items():
        conn_info = connected.get(name, {})
        clients.append(
            {
                "name": name,
                "ip": ip,
                "connected": name in connected,
                "real_address": conn_info.get("real_address"),
                "virtual_address": conn_info.get("virtual_address"),
                "bytes_received": conn_info.get("bytes_received"),
                "bytes_sent": conn_info.get("bytes_sent"),
                "connected_since": conn_info.get("connected_since"),
            }
        )

    return clients


def get_logs(lines: int = 100) -> str:
    """Get the last N lines of the OpenVPN log."""
    log_file = LOGS_DIR / "openvpn.log"
    if not log_file.exists():
        return "No log file found. OpenVPN may not have started yet."

    result = subprocess.run(
        ["tail", "-n", str(lines), str(log_file)],
        capture_output=True,
        text=True,
    )
    return result.stdout


def restart_openvpn():
    """Restart the OpenVPN process via supervisord."""
    subprocess.run(["supervisorctl", "restart", "openvpn"], capture_output=True)
