
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
      #ConditionPathExists=!/etc/credstore.encrypted/machine-master-ed25519.cred

      serviceConfig = {
        Type = "oneshot";
        After = ["local-fs.target"];
        UMask = "0077";
        ExecStart = ''
          PATH=${lib.makeBinPath (with pkgs; [
            coreutils-full
            self.packages.${pkgs.system}.genkeypair
            bash
          ])}
          cat <<<'EOF' | bash -euo pipefail
            genkeypair | systemd-creds encrypt \
              --name=session-ed25519 - \
              /etc/encrypted/session-ed25519
          EOF
        '';
      };

      wantedBy = [ "multi-user.target" ];
    };
  };
}
