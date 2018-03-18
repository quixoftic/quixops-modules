# Configuration common to Jetson TK1 hosts.

{ config, lib, pkgs, ... }:

with lib;

let

  cfg = config.quixops.hardware.jetson-tk1;
  enabled = cfg.enable;

in
{
  options.quixops.hardware.jetson-tk1 = {
    enable = mkEnableOption "Enable NVIDIA Jetson TK1-specific hardware configuration.";
  };

  config = mkIf enabled {
    nixpkgs.system = "armv7l-linux";

    hardware.enableAllFirmware = true;

    boot.loader.grub.enable = false;
    boot.loader.generic-extlinux-compatible.enable = true;

    boot.kernelPackages = pkgs.linuxPackages_4_14;

    boot.initrd.availableKernelModules = [ "ahci_tegra" "nvme" ];

    # Manual doesn't currently evaluate on ARM
    services.nixosManual.enable = false;
  };
}
