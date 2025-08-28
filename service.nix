
self: { config, lib, pkgs, ... }:
let
  cfg = config.services.tre-generate-keypairs;
in {
  options.services.tre-generate-keypairs = with lib; {
    enable = mkEnableOption "keypair generator service";
  };

  config = lib.mkIf cfg.enable {
    systemd = {
      services.tre-generate-keypairs = {
        description = "Generate ED25519 keypairs service";
        after = ["local-fs.target"];
        wantedBy = [ "multi-user.target" ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = "yes";
          UMask = "0077";
          ExecStart = "${self.packages.${pkgs.system}.default}/bin/generate-keypairs";
        };

      };
      sockets.tre-keypairs-provider = {
        wantedBy = [ "sockets.target" ];
        description = "socket for keypair provider";
        socketConfig = {
          ListenStream = "/run/tre-keypairs-provider.sock";
          SocketMode = "0600";
          Service = "tre-keypairs-provider.service";
        };
      };
      services.tre-keypairs-provider = {
        description = "ed25519 keypairs provider";
        after = ["tre-generate-keypairs.service"];
        requires = ["tre-generate-keypairs.service"];

        serviceConfig = {
          Type = "simple";
          DynamicUser = "yes";
          NoNewPrivileges = "yes";
          ProtectSystem = "strict";
          ProtectHome = "yes";
          PrivateTmp = "yes";
          LoadCredentialEncrypted = [
            "tre-machine-key:/etc/encrypted/tre-machine-key"
            "tre-session-key:/etc/encrypted/tre-session-key"
          ];
          ExecStart = "${self.packages.${pkgs.system}.provider}/bin/provider --machine-key %d/tre-machine-key --session-key %d/tre-session-key";
        };
      };
    };
  };
}
