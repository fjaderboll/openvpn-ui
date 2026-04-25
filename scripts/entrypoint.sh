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
if [ ! -f "$CONFIG_DIR/client.conf.template" ]; then
    echo ">>> Copying default client.conf.template..."
    cp /app/config/client.conf.template "$CONFIG_DIR/client.conf.template"
    echo ">>> client.conf.template copied. Edit $CONFIG_DIR/client.conf.template to customize."
fi

# Setup networking rules
bash /app/scripts/setup-networking.sh "$VPN_SUBNET" "$TUN_DEV"

echo "=== Starting services ==="
exec supervisord -n -c /etc/supervisor/conf.d/supervisord.conf
