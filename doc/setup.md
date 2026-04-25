# Setup

## Home Network
For routing purposes inside your local network, it might be easier to run with `--net=host`.

```shell
docker run -d \
  --name openvpn-ui \
  --cap-add=NET_ADMIN \
  --device /dev/net/tun \
  --net=host \
  -e UI_PORT=1180 \
  -v openvpn-ui-data:/data \
  -e ADMIN_USERNAME=john \
  -e ADMIN_PASSWORD=verysecret \
  -e VPN_PORT=1194 \
  -e VPN_SUBNET=10.8.0.0 \
  -e VPN_SUBNET_MASK=255.255.255.0 \
  -e VPN_HOST=vpn.mydomain.com \
  ghcr.io/fjaderboll/openvpn-ui:latest
```

### Routing
For a local fix on your computer, run this:
```shell
sudo ip route add 10.8.0.0/24 via ip.of.server.running.the.container
```

A better solution is to add a static route in your router:
* Destination: `10.8.0.0/24`
* Gateway: `ip.of.server.running.the.container`

If you intend to use this externally, your router also needs a port
forwarding of port `1194/udp` to your server.

Then try this from your computer: `ping 10.8.0.1` for the VPN-server and `ping 10.8.0.2` for a connected client.
