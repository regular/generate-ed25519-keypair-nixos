
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
        ExecStart = "${self.packages.${pkgs.system}.default}/bin/generate-keypairs";
      };

    };
  };
}
