# An opinionated anycast unbound instance.
#
# Other notes:
#
# - `allowedAccess` from the Nixpkgs unbound module is broken up into
#   separate IPv4 and IPv6 lists so that the addresses can easily be
#   added to firewall rules.
#
# TODO:
#
# - Reload the block list when it is updated. Note -- this will
#   require unbound-control functionality, which is not currently
#   supported in Nixpkgs.

{ config, pkgs, lib, ... }:

with lib;

let

  cfg = config.services.unbound-anycast;
  enable = cfg.enable;


  stateDir = "/var/lib/unbound";
  blockListEnabled = cfg.blockList.enable;
  blockListDir = "${stateDir}/blocklists";
  blockListName = "blocklist-someonewhocares.conf";
  blockListFile = "${blockListDir}/${blockListName}";
  seedBlockList = ./blocklist-someonewhocares.conf;

  rootTrustAnchorFile = "${stateDir}/root.key";

  confFile =
  let
    isLocalAddress = x: substring 0 3 x == "::1" || substring 0 9 x == "127.0.0.1";
  in
  pkgs.writeText "unbound.conf" ''
    server:
      directory: "${stateDir}"
      username: unbound
      chroot: "${stateDir}"
      pidfile: ""
      ${concatMapStringsSep "\n  " (x: "interface: ${x.addrOpts.address}") cfg.anycastAddrs.v4}
      ${concatMapStringsSep "\n  " (x: "interface: ${x.addrOpts.address}") cfg.anycastAddrs.v6}
      ${concatMapStringsSep "\n  " (x: "access-control: ${x} allow") cfg.allowedAccessIpv4}
      ${concatMapStringsSep "\n  " (x: "access-control: ${x} allow") cfg.allowedAccessIpv6}
      ${optionalString cfg.enableRootTrustAnchor "auto-trust-anchor-file: ${rootTrustAnchorFile}"}

    unwanted-reply-threshold: 10000000

    verbosity: 3
    prefetch: yes
    prefetch-key: yes

    hide-version: yes
    hide-identity: yes

    private-address: 10.0.0.0/8
    private-address: 172.16.0.0/12
    private-address: 192.168.0.0/16
    private-address: 169.254.0.0/16
    private-address: fd00::/8
    private-address: fe80::/10

    ${optionalString blockListEnabled "include: ${blockListFile}"}
    ${cfg.extraConfig}
    ${optionalString (any isLocalAddress cfg.forwardAddresses) ''
        do-not-query-localhost: no
      '' +
      optionalString (cfg.forwardAddresses != []) ''
        forward-zone:
          name: .
      '' +
      concatMapStringsSep "\n" (x: "    forward-addr: ${x}") cfg.forwardAddresses}
  '';

in {

  options.services.unbound-anycast = {

    enable = mkEnableOption "An opinionated Unbound service";

    blockList = {

      enable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          If true, the Unbound instance will use a blocklist to block
          unwanted domains; these domains will return an address of
          <literal>127.0.0.1</literal> or <literal>::1</literal>.
        '';
      };

      updateFrequency = mkOption {
        default = "daily";
        example = "hourly";
        type = pkgs.lib.types.nonEmptyStr;
        description = ''
          How often to update the block list. This value should be
          specified as a valid <literal>systemd.timers</literal>
          <literal>OnCalendar</literal> value.
        '';
      };

    };

    allowedAccessIpv4 = mkOption {
      default = [ "127.0.0.0/8" ];
      example = [ "192.168.1.0/24" ];
      type = types.listOf pkgs.lib.types.ipv4CIDR;
      description = ''
        A list of IPv4 networks that can use the server as a resolver,
        in CIDR notation.

        Note that, in addition to specifying them in the Unbound
        service configuration, these addresses will also be added to
        the <literal>nixos-fw-accept</literal> firewall whitelist for
        port 53 (UDP and TCP).
      '';
    };

    allowedAccessIpv6 = mkOption {
      default = [ "::1/128" ];
      example = [ "2001:db8::/32" ];
      type = types.listOf pkgs.lib.types.ipv6CIDR;
      description = ''
        A list of IPv6 networks that can use the server as a resolver,
        in CIDR notation.

        Note that, in addition to specifying them in the Unbound
        service configuration, these addresses will also be added to
        the <literal>nixos-fw-accept</literal> firewall whitelist for
        port 53 (UDP and TCP).
      '';
    };

    anycastAddrs = mkOption {
      type = pkgs.lib.types.anycastAddrs;
      default = { v4 = []; v6 = []; };
      example = {
        v4 = [ { ifnum = 0; addrOpts = { address = "10.8.8.8"; prefixLength = 32; }; } ];
        v6 = [ { ifnum = 0; addrOpts = { address = "2001:db8::1"; prefixLength = 128; }; } ];
      };
      description = ''
        A set of IPv4 and IPv6 anycast addresses on which the Unbound
        service will listen.
      '';
    };

    forwardAddresses = mkOption {
      default = pkgs.lib.dns.googleDNS;
      example = [ "8.8.8.8" "2001:4860:4860::8888" ];
      type = types.nonEmptyListOf (types.either pkgs.lib.types.ipv4NoCIDR pkgs.lib.types.ipv6NoCIDR);
      description = ''
        The address(es) of forwarding servers for this Unbound
        service. Both IPv4 and IPv6 addresses are supported.
      '';
    };

    enableRootTrustAnchor = mkOption {
      default = true;
      type = types.bool;
      description = "Use and update root trust anchor for DNSSEC validation.";
    };

    extraConfig = mkOption {
      default = "";
      type = types.lines;
      description = "Extra unbound config.";
    };

  };

  config = mkIf cfg.enable {

    assertions = [

      { assertion = pkgs.lib.exclusiveOr cfg.enable config.services.unbound.enable;
        message = "Only one of `services.unbound` and `services.unbound-anycast` can be enabled";
      }

      { assertion = (cfg.anycastAddrs.v4 == [] -> cfg.anycastAddrs.v6 != []) &&
                    (cfg.anycastAddrs.v6 == [] -> cfg.anycastAddrs.v4 != []);
        message = "At least one anycast address must be set in `services.unbound-anycast`";
      }
    ];

    # Track changes in upstream service, in case we need to reproduce
    # them here.

    quixops.assertions.moduleHashes."services/networking/unbound.nix" =
      "28324ab792c2eea96bce39599b49c3de29f678029342dc57ffcac186eee22f7b";

    networking.anycastAddrs = cfg.anycastAddrs;

    environment.systemPackages = [ pkgs.unbound ];

    users.users.unbound = {
      description = "unbound daemon user";
      isSystemUser = true;
    };

    systemd.services.unbound-anycast = {
      description = "Unbound recursive name server (anycast)";
      after = [ "network.target" ];
      before = [ "nss-lookup.target" ];
      wants = [ "nss-lookup.target" ];
      wantedBy = [ "multi-user.target" ];

      preStart = ''
        mkdir -m 0755 -p ${stateDir}/dev/
        cp ${confFile} ${stateDir}/unbound.conf
        ${optionalString cfg.enableRootTrustAnchor ''
          ${pkgs.unbound}/bin/unbound-anchor -a ${rootTrustAnchorFile} || echo "Root anchor updated!"
          chown unbound ${stateDir} ${rootTrustAnchorFile}
        ''}
        touch ${stateDir}/dev/random
        ${pkgs.utillinux}/bin/mount --bind -n /dev/urandom ${stateDir}/dev/random
      '';

      serviceConfig = {
        ExecStart = "${pkgs.unbound}/bin/unbound -d -c ${stateDir}/unbound.conf";
        ExecStopPost="${pkgs.utillinux}/bin/umount ${stateDir}/dev/random";

        ProtectSystem = true;
        ProtectHome = true;
        PrivateDevices = true;
        Restart = "always";
        RestartSec = "5s";
      };
    };

    systemd.services.pre-seed-unbound-blocklist = {
      description = "Pre-seed Unbound's block list";
      before = [ "unbound-anycast.service" ];
      requiredBy = if blockListEnabled then [ "unbound-anycast.service" ] else [];
      script = ''
        mkdir -p -m 0755 ${blockListDir} > /dev/null 2>&1 || true
        if ! [ -e ${blockListFile} ] ; then
          echo "Pre-seeding unbound-anycast block list"
          cp ${seedBlockList} ${blockListFile}
        else
          echo "A unbound-anycast block list already exists; skipping"
        fi
        chown -R unbound:nogroup ${blockListDir}
        find ${blockListDir} -type f -exec chmod 0644 {} \;
      '';
      restartIfChanged = true;

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
    };

    systemd.services.update-unbound-block-hosts = {
      description = "Update Unbound's block list";
      after = [ "unbound-anycast.service" ];
      wantedBy = if blockListEnabled then [ "unbound-anycast.service" ] else [];
      script = ''
        until ${pkgs.unbound-block-hosts}/bin/unbound-block-hosts \
          --file ${blockListFile}.latest
        do
          sleep 10
        done

        [ -e ${blockListFile} ] && \
          cp ${blockListFile} ${blockListFile}.last

        cp ${blockListFile}.latest ${blockListFile}

        # Not yet working, need to run unbound-control-setup.
        # ${pkgs.unbound}/bin/unbound-control -c ${stateDir}/unbound.conf reload
      '';
      restartIfChanged = true;

      serviceConfig = {
        PermissionsStartOnly = true;
        User = "unbound";
        Type = "oneshot";
        RemainAfterExit = true;
      };
    };

    systemd.timers.update-unbound-block-hosts = {
      wantedBy = if blockListEnabled then [ "timers.target" ] else [];
      timerConfig = {
        OnCalendar = cfg.blockList.updateFrequency;
        Persistent = "yes";
      };
    };

    networking.firewall.allowedIPs = [
      { protocol = "tcp"; port = 53; v4 = cfg.allowedAccessIpv4; v6 = cfg.allowedAccessIpv6; }
      { protocol = "udp"; port = 53; v4 = cfg.allowedAccessIpv4; v6 = cfg.allowedAccessIpv6; }
    ];

  };

  meta.maintainers = lib.maintainers.dhess-qx;

}
