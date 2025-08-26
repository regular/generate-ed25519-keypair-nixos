
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
          self.packages.${pkgs.system}.genkeypair
          bash
        ])}";
        ExecStart = "bash -euo pipefail -c 'genkeypair | systemd-creds encrypt --name=session-ed25519 - /etc/encrypted/session-ed25519 '";
      };

    };
  };
}
