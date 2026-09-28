{
  description = "Minimal rootless/distroless Tailscale + Caddy Cloudflare unified gateway";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };

        caddyWithCloudflare = pkgs.caddy.withPlugins {
          plugins = [ "github.com/caddy-dns/cloudflare@v0.2.4" ];
          hash = "sha256-dQvk6ezY6TQ1J7PjhCXnThF/SqVgPwBO8/RXzHCY+js=";
        };

        entrypoint = pkgs.writeShellScriptBin "entrypoint.sh" ''
          set -euo pipefail

          TS_STATE_DIR="''${TS_STATE_DIR:-/var/lib/tailscale}"
          TS_SOCKET="''${TS_SOCKET:-/var/run/tailscale/tailscaled.sock}"
          CADDYFILE="''${CADDYFILE:-/etc/caddy/Caddyfile}"

          mkdir -p "$TS_STATE_DIR" "$(dirname "$TS_SOCKET")" /var/log /data /config

          echo "[ts-caddy-gateway] Starting tailscaled..."
          ${pkgs.tailscale}/bin/tailscaled \
            --state="$TS_STATE_DIR/tailscaled.state" \
            --socket="$TS_SOCKET" &
          TAILSCALED_PID=$!

          # Wait for tailscaled socket
          until ${pkgs.tailscale}/bin/tailscale --socket="$TS_SOCKET" status >/dev/null 2>&1; do
            sleep 0.5
          done

          # Bring up tailscale if authkey provided
          if [ -n "''${TS_AUTHKEY:-}" ]; then
            echo "[ts-caddy-gateway] Authenticating Tailscale node..."
            ${pkgs.tailscale}/bin/tailscale --socket="$TS_SOCKET" up \
              --auth-key="$TS_AUTHKEY" \
              --hostname="''${TS_HOSTNAME:-ts-caddy-gateway}" \
              ''${TS_EXTRA_ARGS:-}
          fi

          echo "[ts-caddy-gateway] Starting Caddy..."
          ${caddyWithCloudflare}/bin/caddy run --config "$CADDYFILE" --adapter caddyfile &
          CADDY_PID=$!

          trap 'kill -TERM $CADDY_PID $TAILSCALED_PID 2>/dev/null; wait' SIGTERM SIGINT

          wait -n $CADDY_PID $TAILSCALED_PID
        '';

        baseImage = pkgs.dockerTools.buildLayeredImage {
          name = "ghcr.io/rogernavelsaker/ts-caddy-gateway";
          tag = "latest";
          maxLayers = 16;

          contents = [
            pkgs.cacert
            pkgs.coreutils
            pkgs.bash
            pkgs.iptables
            pkgs.iproute2
            pkgs.tailscale
            caddyWithCloudflare
            entrypoint
          ];

          config = {
            Entrypoint = [ "${entrypoint}/bin/entrypoint.sh" ];
            Env = [
              "PATH=${pkgs.lib.makeBinPath [ pkgs.coreutils pkgs.bash pkgs.iptables pkgs.iproute2 pkgs.tailscale caddyWithCloudflare ]}"
              "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
              "XDG_DATA_HOME=/data"
              "XDG_CONFIG_HOME=/config"
            ];
            WorkingDir = "/data";
            Volumes = {
              "/data" = {};
              "/config" = {};
              "/var/lib/tailscale" = {};
              "/var/run/tailscale" = {};
            };
            ExposedPorts = {
              "80/tcp" = {};
              "443/tcp" = {};
              "443/udp" = {};
            };
          };

          extraCommands = ''
            mkdir -p data config etc/caddy var/lib/tailscale var/run/tailscale tmp
            chmod 1777 tmp
          '';
        };

      in {
        packages = {
          default = baseImage;
          caddy = caddyWithCloudflare;
          tailscale = pkgs.tailscale;
          image = baseImage;
        };

        apps = {
          default = {
            type = "app";
            program = "${entrypoint}/bin/entrypoint.sh";
          };
        };
      }
    );
}
