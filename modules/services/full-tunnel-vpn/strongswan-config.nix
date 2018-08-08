{ cfg, lib, pkgs, keys, ... }:

with lib;

let

  inherit (builtins) toFile;
  ikev2Port = 500;
  ikev2NatTPort = 4500;

  deployedCertKeyFile = keys.strongswan-cert-key.path;

  keyFile = "/var/lib/strongswan/key";

  strongSwanDns = concatMapStringsSep "," (x: "${x}") cfg.dns;

  secretsFile = toFile "strongswan.secrets"
    ": RSA ${keyFile}";
    
in
mkIf cfg.enable {

  quixops.assertions.moduleHashes."services/networking/strongswan.nix" =
        "4dbdea221ac2f5ab469e9d8c7f7cf0c6ce5dcf837504c05e69de5e3b727fef6c";

  quixops.keychain.keys.strongswan-cert-key = {
    text = cfg.certKeyLiteral;
  };

  services.strongswan = {
    enable = true;
    secrets = [ secretsFile ];
    ca.strongswan = {
      auto = "add";
      cacert = "${cfg.caFile}";
      crlurl = "${cfg.crlFile}";
    };
    setup = { uniqueids = "never"; }; # Allow multiple connections by same cert.
    connections."%default" = {
      keyexchange = "ikev2";
      # Suite-B-GCM-256, Suite-B-GCM-128.
      ike = "aes256gcm16-prfsha384-ecp384,aes128gcm16-prfsha256-ecp256";
      esp = "aes256gcm16-prfsha384-ecp384,aes128gcm16-prfsha256-ecp256";
      fragmentation = "yes";
      dpdaction = "clear";
      dpddelay = "300s";
      rekey = "no";
      left = "%any";
      leftsubnet = "0.0.0.0/0,::/0";
      leftcert = "${cfg.certFile}";
      leftsendcert = "always";
      right = "%any";
      rightsourceip = "${cfg.ipv4ClientCidr}, ${cfg.ipv6ClientPrefix}";
      rightdns = "${strongSwanDns}";
      auto = "add";
    };
    connections."apple-roadwarrior" = {
      leftid = cfg.remoteId;
      auto = "add";
    };
  };
  
  networking.nat.internalIPs = [ cfg.ipv4ClientCidr ];

  systemd.services.strongswan-setup = {
    description = "strongswan setup script ";
    wantedBy = [ "multi-user.target" "strongswan.service" ];
    wants = [ "keys.target" ];
    after = [ "keys.target" ];
    before = [ "strongswan.service" ];
    script =
    ''
      install -m 0700 -o root -g root -d `dirname ${keyFile}` > /dev/null 2>&1 || true
      install -m 0400 -o root -g root ${deployedCertKeyFile} ${keyFile}
    '';
  };

}
