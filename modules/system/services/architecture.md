# Architecture

Note: Architecture assuming wireguard is enabled

## DNS

### Server

On all servers where DNS is enabled, an unbound server is started with recursion enabled. Custom DNS entries are added that point to the wireguard IP address.

### Client

Using systemd-resolved for split dns. All traffic is sent the wireguard DNS servers unless overidden by another network interface that configured DNS for specific addresses.

## Mail Server

A public mail server is set up (through simple-nixos-mailserver). If a DNS server has been set up on the host, disable the mailserver DNS.

## Nginx

All web services are set up behind an nginx proxy.

Current web services:

* Miniflux

## Taskserver

Sets up a taskserver using the auto generated key options (TODO: make it manual). Secrets are distributed to clients by manually doing `nixos-taskserver export` and storing them in the secrets repository.

## Monitoring (TODO)

Using `promscale` and `timescaledb` for long term storage of metrics and traces. Logs are sent to `quickwit` for indexing (stored on FS, look into seaweedfs in the future).

Using `vector` to scrape logs and metrics. Forwards the logs to quickwit. Metrics are sent to `promscale` prometheus `remote_write` endpoint. When vector gains support for open telemetry line protocol (OTLP) forward traces to the `promscale` endpoint.

A grafana dashboard connects to timescaledb and quickwit.
