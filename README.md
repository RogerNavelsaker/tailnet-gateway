# ts-caddy-gateway

Minimal distroless/layered container image packaging **Tailscale** and **Caddy** (compiled with the official Cloudflare DNS module `github.com/caddy-dns/cloudflare`) built with Nix Flakes and `pkgs.dockerTools`.

## Purpose

Replaces two separate sidecar containers (`tailscale` + `caddy`) per service/pod with a single lightweight container, dramatically reducing memory overhead, process duplication, and Tailnet node sprawl.

## Architecture

- **Tailscaled**: Background userspace or tun daemon.
- **Caddy**: High-performance HTTP/2 & HTTP/3 reverse proxy with automated ACME TLS via Cloudflare DNS challenge.
- **Nix Layered Image**: Distroless, deterministic root filesystem containing only runtime dependencies (no Debian/Ubuntu/Alpine bloat).

## Building

```bash
# Build the container image tarball
nix build .#image

# Load into Podman
podman load < result

# Or build and load in one command:
nix build .#image && podman load < result
```

## Running with Podman

```bash
podman run -d \
  --name=ts-caddy-gateway \
  --device=/dev/net/tun:/dev/net/tun \
  --cap-add=NET_ADMIN \
  --cap-add=NET_RAW \
  -e TS_AUTHKEY="tskey-auth-..." \
  -e TS_HOSTNAME="gateway-host" \
  -e CLOUDFLARE_API_TOKEN="cf-token-..." \
  -v ./tailscale:/var/lib/tailscale:rw \
  -v ./Caddyfile:/etc/caddy/Caddyfile:ro \
  -v ./caddy-data:/data:rw \
  -v ./caddy-config:/config:rw \
  ghcr.io/rogernavelsaker/ts-caddy-gateway:latest
```
