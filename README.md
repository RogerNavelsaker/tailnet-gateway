# Tailnet Gateway

A small Nix-built container that combines **Tailscale** and **Caddy** as a reusable network sidecar. Caddy includes the Cloudflare DNS module for ACME DNS challenges. The image is distroless apart from its runtime tools; no Docker/Podman socket or dynamic container discovery is used.

**Recommended image name:** `tailnet-gateway` (GHCR: `ghcr.io/rogernavelsaker/tailnet-gateway`). The previous `tailnet-gateway` name is published as a compatibility alias by the workflow.

## Configuration model

- **OCI labels** identify the built image (title, source, revision, description). They are metadata, not runtime service configuration.
- **Environment variables** configure Tailscale and provide secrets. Use Podman/Docker secrets and the `_FILE` variables when possible.
- **Mounted files** carry Caddy configuration. Cloudflare's plugin reads its token from the environment referenced in the Caddyfile.
- **No engine labels/socket discovery:** services are routed explicitly in the Caddyfile. This keeps the sidecar independent of the container engine and avoids granting it access to the engine socket.

| Variable | Default | Purpose |
| --- | --- | --- |
| `TS_AUTHKEY` | unset | Tailscale auth key; authenticates only when set. |
| `TS_AUTHKEY_FILE` | unset | Read the auth key from a mounted secret file; takes precedence over `TS_AUTHKEY`. |
| `TS_HOSTNAME` | `tailnet-gateway` | Tailscale node hostname used during `tailscale up`. |
| `TS_STATE_DIR` | `/var/lib/tailscale` | Persistent Tailscale state directory. Mount a persistent volume here. |
| `TS_SOCKET` | `/var/run/tailscale/tailscaled.sock` | Local `tailscaled` socket path. |
| `TS_DAEMON_ARGS` | empty | Additional whitespace-separated arguments for `tailscaled` (for example `--tun=userspace-networking`). |
| `TS_EXTRA_ARGS` | empty | Additional whitespace-separated arguments for `tailscale up` (for example `--accept-routes`). Arguments are not evaluated as shell code. |
| `CADDYFILE` | `/etc/caddy/Caddyfile` | Path to the mounted Caddyfile or other Caddy config. |
| `CADDY_ADAPTER` | `caddyfile` | Caddy config adapter. |
| `CLOUDFLARE_API_TOKEN` | unset | Cloudflare token used by Caddy's DNS module. |
| `CLOUDFLARE_API_TOKEN_FILE` | unset | Read the Cloudflare token from a mounted secret file; takes precedence over the direct variable. |

The Caddyfile controls host routing and TLS. For example:

```caddyfile
{
  acme_dns cloudflare {env.CLOUDFLARE_API_TOKEN}
}

app.example.net {
  reverse_proxy app:8080
}
```

Attach the gateway and backend to the same user-defined container network so the Caddyfile can resolve the backend service name. In TUN mode, the container needs `/dev/net/tun` and `NET_ADMIN`; `NET_RAW` is included for Tailscale networking. No host port publishing is required when clients connect over the gateway's tailnet IP.

## Run with Podman

Create Podman secrets from local files (keep these files out of version control):

```sh
podman secret create tailscale-authkey ./tailscale-authkey
podman secret create cloudflare-api-token ./cloudflare-api-token
```

Then start the sidecar on the same network as the service:

```sh
podman run -d \
  --name=tailnet-gateway \
  --network=app-network \
  --device=/dev/net/tun:/dev/net/tun \
  --cap-add=NET_ADMIN \
  --cap-add=NET_RAW \
  --secret=tailscale-authkey,type=mount,target=/run/secrets/ts-authkey \
  --secret=cloudflare-api-token,type=mount,target=/run/secrets/cloudflare-token \
  -e TS_AUTHKEY_FILE=/run/secrets/ts-authkey \
  -e TS_HOSTNAME=app-gateway \
  -e TS_EXTRA_ARGS="--advertise-tags=tag:gateway" \
  -e CLOUDFLARE_API_TOKEN_FILE=/run/secrets/cloudflare-token \
  -v tailscale-state:/var/lib/tailscale:rw \
  -v ./Caddyfile:/etc/caddy/Caddyfile:ro \
  -v caddy-data:/data:rw \
  -v caddy-config:/config:rw \
  ghcr.io/rogernavelsaker/tailnet-gateway:latest
```

The Tailscale auth key should be reusable only as needed for the deployment; the persisted state volume keeps the node identity across restarts. Configure advertised tags in the tailnet ACL policy.

## Build locally

```sh
nix build .#image
podman load < result
```

## GitHub Actions publishing

`.github/workflows/publish.yml` builds and checks the Nix image on pull requests. Pushes to the default branch publish `latest`, branch, and commit-SHA tags; `v*` tags also publish version tags. The workflow publishes the canonical `tailnet-gateway` image and the legacy `tailnet-gateway` alias to GHCR using the repository's `GITHUB_TOKEN`.

Publishing requires a GitHub repository with Actions enabled and the workflow's `packages: write` permission. The checkout currently has no Git remote configured, so the workflow has not been run against GitHub from this workspace.
