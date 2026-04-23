#!/bin/bash
set -e

DATA_DIR="/data"
PKI_DIR="$DATA_DIR/pki"
CCD_DIR="$DATA_DIR/ccd"
CONFIG_DIR="$DATA_DIR/config"
CLIENTS_DIR="$DATA_DIR/clients"
LOGS_DIR="$DATA_DIR/logs"

VPN_SUBNET="${VPN_SUBNET:-10.8.0.0}"

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

# Copy default server.conf if not exists
if [ ! -f "$CONFIG_DIR/server.conf" ]; then
    echo ">>> Copying default server.conf..."
    cp /app/config/server.conf "$CONFIG_DIR/server.conf"
    echo ">>> server.conf copied. Edit $CONFIG_DIR/server.conf to customize."
fi

# Enable IP forwarding (may fail if /proc/sys is read-only; use --sysctl at docker run)
sysctl -w net.ipv4.ip_forward=1 2>/dev/null || echo ">>> ip_forward already enabled or read-only (ensure --sysctl net.ipv4.ip_forward=1 is set)"

# Setup NAT
iptables -t nat -C POSTROUTING -s "${VPN_SUBNET}/24" -j MASQUERADE 2>/dev/null || \
    iptables -t nat -A POSTROUTING -s "${VPN_SUBNET}/24" -j MASQUERADE

echo "=== Starting services ==="
exec supervisord -n -c /etc/supervisor/conf.d/supervisord.conf
