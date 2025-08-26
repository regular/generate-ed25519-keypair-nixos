
self: { config, lib, pkgs, ... }:
let
  cfg = config.services.generate-ED25519;
in {
  options.services.generate-ED25519 = with lib; {
    enable = mkEnableOption "keypair generator service";
  };

  config = lib.mkIf cfg.enable {
    systemd = {
      services.generate-ED25519 = {
        description = "Generate ED25519 keypairs service";
        after = ["local-fs.target"];
        wantedBy = [ "multi-user.target" ];

        serviceConfig = {
          Type = "oneshot";
          UMask = "0077";
          ExecStart = "${self.packages.${pkgs.system}.default}/bin/generate-keypairs";
        };

      };
      sockets.keypairs-provider = {
        wantedBy = [ "sockets.target" ];
        description = "socket for keypair provider";
        socketConfig = {
          ListenStream = "/run/keys.sock";
          SocketMode = "0600";
          Service = "keypairs-provider.service";
        };
      };
      services.keypairs-provider = {
        description = "ed25519 keypairs provider";

        serviceConfig = {
          Type = "simple";
          DynamicUser = "yes";
          NoNewPrivileges = "yes";
          ProtectSystem = "strict";
          ProtectHome = "yes";
          PrivateTmp = "yes";
          LoadCredentialEncrypted = [
            "machine-key:/etc/encrypted/machine-key"
            "session-key:/etc/encrypted/session-key"
          ];
          ExecStart = "${self.packages.${pkgs.system}.provider}/bin/provider --machine-key %d/machine-key --session-key %d/session-key";
        };
      };
    };
  };
}
