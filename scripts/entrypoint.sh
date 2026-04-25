#!/bin/bash
set -e

DATA_DIR="/data"
PKI_DIR="$DATA_DIR/pki"
CCD_DIR="$DATA_DIR/ccd"
CONFIG_DIR="$DATA_DIR/config"
CLIENTS_DIR="$DATA_DIR/clients"
LOGS_DIR="$DATA_DIR/logs"

VPN_SUBNET="${VPN_SUBNET:-10.8.0.0}"
TUN_DEV="tun-ovpn-ui"

echo "=== OpenVPN UI - Starting up ==="

# Create directories
mkdir -p "$CCD_DIR" "$CONFIG_DIR" "$CLIENTS_DIR" "$LOGS_DIR"

# Initialize PKI if needed
if [ ! -d "$PKI_DIR" ]; then
    echo ">>> Initializing PKI (first run)..."
    /usr/share/easy-rsa/easyrsa --pki-dir="$PKI_DIR" init-pki

    echo ">>> Building CA..."
    EASYRSA_BATCH=1 /usr/share/easy-rsa/easyrsa --pki-dir="$PKI_DIR" build-ca nopass

    echo ">>> Generating server certificate..."
    EASYRSA_BATCH=1 /usr/share/easy-rsa/easyrsa --pki-dir="$PKI_DIR" build-server-full server nopass

    echo ">>> Generating DH parameters (this may take a while)..."
    /usr/share/easy-rsa/easyrsa --pki-dir="$PKI_DIR" gen-dh

    echo ">>> Generating CRL..."
    EASYRSA_BATCH=1 /usr/share/easy-rsa/easyrsa --pki-dir="$PKI_DIR" gen-crl

    echo ">>> Generating TLS-crypt key..."
    openvpn --genkey secret "$PKI_DIR/tc.key"

    # Make CRL readable by OpenVPN
    chmod 644 "$PKI_DIR/crl.pem"

    echo ">>> PKI initialization complete."
fi

# Generate server.conf from template if not exists
if [ ! -f "$CONFIG_DIR/server.conf" ]; then
    echo ">>> Generating server.conf from template..."
    VPN_PORT="${VPN_PORT:-1194}"
    VPN_PROTO="${VPN_PROTO:-udp}"
    VPN_SUBNET_MASK="${VPN_SUBNET_MASK:-255.255.255.0}"
    
    sed -e "s|{{port}}|$VPN_PORT|g" \
        -e "s|{{proto}}|$VPN_PROTO|g" \
        -e "s|{{subnet}}|$VPN_SUBNET|g" \
        -e "s|{{subnet_mask}}|$VPN_SUBNET_MASK|g" \
        /app/config/server.conf.template > "$CONFIG_DIR/server.conf"
    echo ">>> server.conf generated from template with VPN_SUBNET=$VPN_SUBNET, VPN_PORT=$VPN_PORT, VPN_PROTO=$VPN_PROTO"
fi

# Copy default client template if not exists
if [ ! -f "$CONFIG_DIR/client.ovpn.template" ]; then
    echo ">>> Copying default client.ovpn.template..."
    cp /app/config/client.ovpn.template "$CONFIG_DIR/client.ovpn.template"
    echo ">>> client.ovpn.template copied. Edit $CONFIG_DIR/client.ovpn.template to customize."
fi

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

echo "=== Starting services ==="
exec supervisord -n -c /etc/supervisor/conf.d/supervisord.conf
