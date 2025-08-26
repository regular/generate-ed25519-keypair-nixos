{
  description = "Generate persistent and non-persistent ED25519 keypairs";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = inputs@{ self, nixpkgs, ...}: let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
  in {
    nixosConfigurations.demo = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        self.nixosModules.default
        {
            services.generate-ED25519.enable = true;
        }
      ];
    };
    nixosModules.default = (import ./service.nix) self;
    packages.${system} = {
      genkeypair = pkgs.writeShellScriptBin "genkeypair" ''
        export PATH=${pkgs.lib.makeBinPath (with pkgs; [
          openssl
          gawk
        ])}
        pem="$(openssl genpkey -algorithm ED25519 -out - 2>/dev/null)"
        dump="$(printf "%s" "$pem" | openssl pkey -text -noout)"

        privhex=$(
          printf "%s\n" "$dump" |
          awk '/^priv:/{m=1;next} /^pub:/{m=0} m{gsub(/[^0-9a-f]/,""); printf "%s",$0}'
        )

        pubhex=$(
          printf "%s\n" "$dump" |
          awk '/^pub:/{m=1;next} m{gsub(/[^0-9a-f]/,""); printf "%s",$0}'
        )

        # sanity: 32 bytes each (64 hex chars)
        [ ''${#privhex} -eq 64 ] && [ ''${#pubhex} -eq 64 ] || { echo "bad key lengths" >&2; exit 1; }

        printf "%s\n%s\n" "$privhex" "$pubhex"
      '';
      default = pkgs.writeShellScriptBin "generate-keypairs" ''
        export PATH=${pkgs.lib.makeBinPath (with pkgs; [
          coreutils-full
          systemd
          self.packages.${pkgs.system}.genkeypair
        ])}
        set -euo pipefail
        mkdir -p /etc/encrypted
        [ ! -e /etc/encrypted/machine-key-ed25519 ] && genkeypair | \
          systemd-creds encrypt --name=machine-key-ed25519 - \
            /etc/encrypted/machine-key-ed25519
        genkeypair | \
          systemd-creds encrypt --name=session-key-ed25519 - \
            /etc/encrypted/session-key-ed25519
      '';
    };
  };
}
