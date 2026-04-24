# Setup

## Home Network
For routing purposes inside your local network, it might be easier to run with `--net=host`.
And without the port specification you need to specify variable `UI_PORT` (if you don't want to run on port 80). OpenVPN still runs at port `1194` (as specified in `server.conf`).

```bash
docker run -d \
  --name openvpn-ui \
  --cap-add=NET_ADMIN \
  --device /dev/net/tun \
  --net=host \
  -e UI_PORT=1180 \
  -v openvpn-ui-data:/data \
  -e ADMIN_USERNAME=john \
  -e ADMIN_PASSWORD=verysecret \
  -e VPN_HOST=your.public.ip.or.hostname \
  ghcr.io/fjaderboll/openvpn-ui:latest
```

### Routing
On your local computer run this:
```shell
sudo ip route add 10.8.0.0/24 via ip.of.server.running.the.container
```

But a better solution is to add a static route in your router:
* Destination: `10.8.0.0/24`
* Gateway: `ip.of.server.running.the.container`

If you intend to use this externally, your router also needs a port
forwarding of port `1194/udp` to your server.
