{ config, pkgs, lib, ... }:

with lib;

let

  cfg = config.quixops.defaults;
  enabled = cfg.enable;

in
{

  options.quixops.defaults = {

    enable = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Enable all of the Quixops configuration defaults.

        These defaults will configure a NixOS server according to the
        Quixoftic, LLC security requirements. Note that some of the
        defaults may not be appropriate for an interactive desktop
        system.
      '';
    };

  };

  config = mkIf enabled {

    quixops.defaults = {

      environment.enable = true;
      networking.enable = true;
      nix.enable = true;
      security.enable = true;
      ssh.enable = true;
      sudo.enable = true;
      system.enable = true;
      users.enable = true;

    };

  };

}
