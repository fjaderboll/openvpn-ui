# OpenVPN UI

A self-contained Docker image running OpenVPN with a web-based admin panel for managing clients.

## Features

- **Web Admin UI** — Alpine.js + Tailwind CSS frontend served by FastAPI
- **Client Management** — Generate, download, and revoke client `.ovpn` configurations
- **Persistent IPs** — Each client gets a fixed VPN IP address across reconnections
- **Backup & Restore** — Download/upload full configuration backups as zip files
- **Log Viewer** — View OpenVPN logs in real-time from the browser
- **Connected Clients** — See which clients are online and their assigned IPs
- **Easy-RSA PKI** — Certificate management using Easy-RSA
- **Single Volume** — All state stored in one Docker volume (`/data`)

## Quick Start

```bash
docker run -d \
  --name openvpn-ui \
  --cap-add=NET_ADMIN \
  --sysctl net.ipv4.ip_forward=1 \
  --device /dev/net/tun \
  -p 1194:1194/udp \
  -p 8080:80 \
  -v openvpn-data:/data \
  -e ADMIN_PASSWORD=changeme \
  -e VPN_HOST=your.public.ip.or.hostname \
  ghcr.io/YOUR_USERNAME/openvpn-ui:latest
```

Then open `http://localhost:8080` and log in with `admin` / `changeme`.

> **First startup** takes a few minutes while DH parameters are generated.

## Environment Variables

| Variable | Default | Description |
|---|---|---|
| `ADMIN_USERNAME` | `admin` | Admin login username |
| `ADMIN_PASSWORD` | *(required)* | Admin login password |
| `VPN_HOST` | `vpn.example.com` | Public hostname/IP for client configs |
| `VPN_PORT` | `1194` | OpenVPN listen port |
| `VPN_PROTO` | `udp` | OpenVPN protocol (`udp` or `tcp`) |
| `VPN_SUBNET` | `10.8.0.0` | VPN subnet |
| `VPN_SUBNET_MASK` | `255.255.255.0` | VPN subnet mask |
| `DNS_SERVERS` | `8.8.8.8,8.8.4.4` | DNS servers pushed to clients |

## Required Docker Permissions

- `--cap-add=NET_ADMIN` — Required for TUN device and iptables
- `--sysctl net.ipv4.ip_forward=1` — Required for routing VPN traffic
- `--device /dev/net/tun` — Required for OpenVPN tunnel interface

## Volume

All configuration and state is stored in `/data`:

```
/data/
├── pki/            # Easy-RSA PKI (CA, certs, keys)
├── ccd/            # Client-config-dir (persistent IPs)
├── config/         # server.conf
├── clients/        # Generated .ovpn files
├── logs/           # OpenVPN logs and status
└── ip_assignments.json
```

## Building Locally

```bash
docker build -t openvpn-ui .

docker run -it \
  --name openvpn-ui \
  --cap-add=NET_ADMIN \
  --sysctl net.ipv4.ip_forward=1 \
  --device /dev/net/tun \
  -p 1194:1194/udp \
  -p 8080:80 \
  -v openvpn-data:/data \
  -e ADMIN_PASSWORD=changeme \
  -e VPN_HOST=localhost \
  openvpn-ui
```

## CI/CD

The GitHub Actions workflow builds and pushes the Docker image to GitHub Container Registry on every push to `main` or tagged release.
