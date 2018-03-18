# Configuration common to Jetson TX1 hosts.

{ config, lib, pkgs, ... }:

with lib;

let

  cfg = config.quixops.hardware.jetson-tx1;
  enabled = cfg.enable;

in
{
  options.quixops.hardware.jetson-tx1 = {
    enable = mkEnableOption "Enable NVIDIA Jetson TX1-specific hardware configuration.";
  };

  config = mkIf enabled {
    nixpkgs.system = "aarch64-linux";

    hardware.enableAllFirmware = true;

    boot.loader.grub.enable = false;
    boot.loader.generic-extlinux-compatible.enable = true;

    boot.kernelPackages = pkgs.linuxPackages_4_14;

    boot.initrd.availableKernelModules = [ "ahci_tegra" "nvme" ];

    # Manual doesn't currently evaluate on ARM
    services.nixosManual.enable = false;
  };
}