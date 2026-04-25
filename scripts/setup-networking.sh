#!/bin/bash
set -e

VPN_SUBNET="${1:-10.8.0.0}"
TUN_DEV="${2:-tun-ovpn-ui}"

echo "=== Setting up networking rules ==="

# Enable IP forwarding (may fail if /proc/sys is read-only; use --sysctl at docker run)
sysctl -w net.ipv4.ip_forward=1 2>/dev/null || echo ">>> ip_forward already enabled or read-only (ensure --sysctl net.ipv4.ip_forward=1 is set)"

# Setup NAT — VPN clients reaching external networks
iptables -t nat -C POSTROUTING -s "${VPN_SUBNET}/24" -j MASQUERADE 2>/dev/null || \
    iptables -t nat -A POSTROUTING -s "${VPN_SUBNET}/24" -j MASQUERADE

# LAN reaching VPN clients — rewrite source so clients reply through the tunnel
iptables -t nat -C POSTROUTING -o "$TUN_DEV" -j MASQUERADE 2>/dev/null || \
    iptables -t nat -A POSTROUTING -o "$TUN_DEV" -j MASQUERADE

# Allow forwarding to/from the VPN subnet (needed for LAN-to-VPN routing)
iptables -C FORWARD -i "$TUN_DEV" -j ACCEPT 2>/dev/null || \
    iptables -A FORWARD -i "$TUN_DEV" -j ACCEPT
iptables -C FORWARD -o "$TUN_DEV" -j ACCEPT 2>/dev/null || \
    iptables -A FORWARD -o "$TUN_DEV" -j ACCEPT

# Allow replies to server-initiated connections
iptables -C INPUT -i "$TUN_DEV" -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || \
    iptables -A INPUT -i "$TUN_DEV" -m state --state ESTABLISHED,RELATED -j ACCEPT

# Allow ICMP (ping) from clients so they can verify connectivity
iptables -C INPUT -i "$TUN_DEV" -p icmp -j ACCEPT 2>/dev/null || \
    iptables -A INPUT -i "$TUN_DEV" -p icmp -j ACCEPT

# Drop all new/client-initiated traffic to the server over the tunnel
iptables -C INPUT -i "$TUN_DEV" -m state --state NEW -j DROP 2>/dev/null || \
    iptables -A INPUT -i "$TUN_DEV" -m state --state NEW -j DROP

echo ">>> Networking rules configured"
