
self: { config, lib, pkgs, ... }:
let
  cfg = config.services.generate-ED25519;
in {
  options.services.generate-ED25519 = with lib; {
    enable = mkEnableOption "keypair generator service";
  };

  config = lib.mkIf cfg.enable {
    systemd.services.generate-ED25519 = {
      description = "Generate ED25519 keypairs service";
      after = ["local-fs.target"];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        UMask = "0077";
        Environment="PATH=${lib.makeBinPath (with pkgs; [
          coreutils-full
          systemd
          self.packages.${pkgs.system}.genkeypair
        ])}";
        ExecStart = "${pkgs.bash}/bin/bash -euo pipefail -c 'mkdir -p /etc/encrypted && genkeypair | systemd-creds encrypt --name=session-ed25519 - /etc/encrypted/session-ed25519 '";
      };

    };
  };
}
