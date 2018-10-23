{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.dovecot2;
  dovecotPkg = pkgs.dovecot;

  # Not yet upstream.
  dovenull2gid = 47;

  baseDir = "/run/dovecot2";
  stateDir = "/var/lib/dovecot";

  dovecotConf = concatStrings [
    ''
      base_dir = ${baseDir}
      protocols = ${concatStringsSep " " cfg.protocols}
      sendmail_path = /run/wrappers/bin/sendmail

      ssl_cert = <${cfg.sslServerCert}
      ssl_key = <${cfg.sslServerKey}
      ssl_ca = <${cfg.sslCACert}
      ssl_dh = <${cfg.dhParamsFile}
      ssl_prefer_server_ciphers = yes
      ssl_min_protocol = TLSv2
      ssl_cipher_list = ${cfg.sslCiphers}

      disable_plaintext_auth = yes

      default_internal_user = ${cfg.user}
      default_internal_group = ${cfg.group}
      ${optionalString (cfg.mailUser != null) "mail_uid = ${cfg.mailUser}"}
      ${optionalString (cfg.mailGroup != null) "mail_gid = ${cfg.mailGroup}"}

      mail_location = ${cfg.mailLocation}

      maildir_copy_with_hardlinks = yes
      pop3_uidl_format = %08Xv%08Xu

      auth_mechanisms = plain

      protocol imap {
        mail_plugins = $mail_plugins imap_zlib
      }
    ''

    (if cfg.enablePAM then ''
      userdb {
        driver = passwd
      }

      passdb {
        driver = pam
        args = ${optionalString cfg.showPAMFailure "failure_show_msg=yes"} dovecot2
      }
    '' else ''
      service auth-worker {
        user = $default_internal_user
      }
    '')

    (optionalString (cfg.sieveScripts != {}) ''
      plugin {
        ${concatStringsSep "\n" (mapAttrsToList (to: from: "sieve_${to} = ${stateDir}/sieve/${to}") cfg.sieveScripts)}
      }
    '')

    (optionalString (cfg.mailboxes != []) ''
      protocol imap {
        namespace inbox {
          inbox=yes
          ${concatStringsSep "\n" (map mailboxConfig cfg.mailboxes)}
        }
      }
    '')

    (optionalString cfg.enableQuota ''
      mail_plugins = $mail_plugins quota
      service quota-status {
        executable = ${dovecotPkg}/libexec/dovecot/quota-status -p postfix
        inet_listener {
          port = ${cfg.quotaPort}
        }
        client_limit = 1
      }

      protocol imap {
        mail_plugins = $mail_plugins imap_quota
      }

      plugin {
        quota_rule = *:storage=${cfg.quotaGlobalPerUser} 
        quota = maildir:User quota # per virtual mail user quota # BUG/FIXME broken, we couldn't get this working
        quota_status_success = DUNNO
        quota_status_nouser = DUNNO
        quota_status_overquota = "552 5.2.2 Mailbox is full"
        quota_grace = 10%%
      }
    '')

    cfg.extraConfig
  ];

  modulesDir = pkgs.symlinkJoin {
    name = "dovecot-modules";
    paths = map (pkg: "${pkg}/lib/dovecot") ([ dovecotPkg ] ++ map (module: module.override { dovecot = dovecotPkg; }) cfg.modules);
  };

  mailboxConfig = mailbox: ''
    mailbox "${mailbox.name}" {
      auto = ${toString mailbox.auto}
  '' + optionalString (mailbox.specialUse != null) ''
      special_use = \${toString mailbox.specialUse}
  '' + "}";

  mailboxes = { ... }: {
    options = {
      name = mkOption {
        type = types.strMatching ''[^"]+'';
        example = "Spam";
        description = "The name of the mailbox.";
      };
      auto = mkOption {
        type = types.enum [ "no" "create" "subscribe" ];
        default = "no";
        example = "subscribe";
        description = "Whether to automatically create or create and subscribe to the mailbox or not.";
      };
      specialUse = mkOption {
        type = types.nullOr (types.enum [ "All" "Archive" "Drafts" "Flagged" "Junk" "Sent" "Trash" ]);
        default = null;
        example = "Junk";
        description = "Null if no special use flag is set. Other than that every use flag mentioned in the RFC is valid.";
      };
    };
  };
in
{

  disabledModules = [ "services/mail/dovecot.nix" ];

  options.services.dovecot2 = {
    enable = mkEnableOption "Dovecot 2.x POP3/IMAP server";

    enablePop3 = mkOption {
      type = types.bool;
      default = false;
      description = "Start the POP3 listener (when Dovecot is enabled).";
    };

    enableImap = mkOption {
      type = types.bool;
      default = true;
      description = "Start the IMAP listener (when Dovecot is enabled).";
    };

    enableLmtp = mkOption {
      type = types.bool;
      default = false;
      description = "Start the LMTP listener (when Dovecot is enabled).";
    };

    protocols = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Additional listeners to start when Dovecot is enabled.";
    };

    user = mkOption {
      type = types.str;
      default = "dovecot2";
      description = "Dovecot user name.";
    };

    group = mkOption {
      type = types.str;
      default = "dovecot2";
      description = "Dovecot group name.";
    };

    extraConfig = mkOption {
      type = types.lines;
      default = "";
      example = "mail_debug = yes";
      description = "Additional entries to put verbatim into Dovecot's config file.";
    };

    configFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Config file used for the whole dovecot configuration.";
      apply = v: if v != null then v else pkgs.writeText "dovecot.conf" dovecotConf;
    };

    mailLocation = mkOption {
      type = types.str;
      default = "maildir:/var/spool/mail/%u"; /* Same as inbox, as postfix */
      example = "maildir:~/mail:INBOX=/var/spool/mail/%u";
      description = ''
        Location that dovecot will use for mail folders. Dovecot mail_location option.
      '';
    };

    mailUser = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Default user to store mail for virtual users.";
    };

    mailGroup = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Default group to store mail for virtual users.";
    };

    createMailUser = mkOption {
      type = types.bool;
      default = true;
      description = ''Whether to automatically create the user
        given in <option>services.dovecot.user</option> and the group
        given in <option>services.dovecot.group</option>.'';
    };

    modules = mkOption {
      type = types.listOf types.package;
      default = [];
      example = literalExample "[ pkgs.dovecot_pigeonhole ]";
      description = ''
        Symlinks the contents of lib/dovecot of every given package into
        /etc/dovecot/modules. This will make the given modules available
        if a dovecot package with the module_dir patch applied is being used.
      '';
    };

    sslCACert = mkOption {
      type = types.path;
      description = "Path to the server's CA certificate key.";
    };

    sslServerCert = mkOption {
      type = types.path;
      description = "Path to the server's public key.";
    };

    sslServerKey = mkOption {
      type = types.path;
      description = "Path to the server's private key.";
    };

    dhParamsFile = mkOption {
      type = types.path;
      description = "Path to the server's DH params file.";
    };

    sslCiphers = mkOption {
      type = pkgs.lib.types.nonEmptyStr;
      default = pkgs.lib.security.sslModernCiphers;
      example = "ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-SHA384:ECDHE-RSA-AES256-SHA384:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA256";
      description = ''
        Specify the list of SSL ciphers that the server will accept.
      '';
    };

    enablePAM = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to create a own Dovecot PAM service and configure PAM user logins.";
    };

    sieveScripts = mkOption {
      type = types.attrsOf types.path;
      default = {};
      description = "Sieve scripts to be executed. Key is a sequence, e.g. 'before2', 'after' etc.";
    };

    showPAMFailure = mkOption {
      type = types.bool;
      default = false;
      description = "Show the PAM failure message on authentication error (useful for OTPW).";
    };

    mailboxes = mkOption {
      type = types.listOf (types.submodule mailboxes);
      default = [];
      example = [ { name = "Spam"; specialUse = "Junk"; auto = "create"; } ];
      description = "Configure mailboxes and auto create or subscribe them.";
    };

    enableQuota = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = "Whether to enable the dovecot quota service.";
    };

    quotaPort = mkOption {
      type = types.str;
      default = "12340";
      description = ''
        The Port the dovecot quota service binds to.
        If using postfix, add check_policy_service inet:localhost:12340 to your smtpd_recipient_restrictions in your postfix config.
      '';
    };
    quotaGlobalPerUser = mkOption {
      type = types.str;
      default = "100G";
      example = "10G";
      description = "Quota limit for the user in bytes. Supports suffixes b, k, M, G, T and %.";
    };

  };


  config = mkIf cfg.enable {

    quixops.assertions.moduleHashes."services/mail/dovecot.nix" =
      "9c868ffb18fd19dd4284dc20a2e6661f9d6212f8154c8b7f3a222b6c8fd9f688";

    security.pam.services.dovecot2 = mkIf cfg.enablePAM {};

    services.dovecot2.protocols =
      optional cfg.enableImap "imap"
      ++ optional cfg.enablePop3 "pop3"
      ++ optional cfg.enableLmtp "lmtp";

    users.users = [
      { name = "dovenull";
        uid = config.ids.uids.dovenull2;
        description = "Dovecot user for untrusted logins";
        group = "dovenull";
      }
    ] ++ optional (cfg.user == "dovecot2")
         { name = "dovecot2";
           uid = config.ids.uids.dovecot2;
           description = "Dovecot user";
           group = cfg.group;
         }
      ++ optional (cfg.createMailUser && cfg.mailUser != null)
         ({ name = cfg.mailUser;
            description = "Virtual Mail User";
         } // optionalAttrs (cfg.mailGroup != null) {
           group = cfg.mailGroup;
         });

    users.groups = optional (cfg.group == "dovecot2")
      { name = "dovecot2";
        gid = config.ids.gids.dovecot2;
      }
    ++ optional (cfg.createMailUser && cfg.mailGroup != null)
      { name = cfg.mailGroup;
      }
    ++ singleton
      { name = "dovenull";
        # Not yet upstream.
        #gid = config.ids.gids.dovenull2;
        gid = dovenull2gid;
      };

    environment.etc."dovecot/modules".source = modulesDir;
    environment.etc."dovecot/dovecot.conf".source = cfg.configFile;

    systemd.services.dovecot2 = {
      description = "Dovecot IMAP/POP3 server";

      after = [ "keys.target" "network.target" ];
      wants = [ "keys.target" ];
      wantedBy = [ "multi-user.target" ];
      restartTriggers = [ cfg.configFile ];

      serviceConfig = {
        ExecStart = "${dovecotPkg}/sbin/dovecot -F";
        ExecReload = "${dovecotPkg}/sbin/doveadm reload";
        Restart = "on-failure";
        RestartSec = "1s";
        StartLimitInterval = "1min";
        RuntimeDirectory = [ "dovecot2" ];
      };

      # When copying sieve scripts preserve the original time stamp
      # (should be 0) so that the compiled sieve script is newer than
      # the source file and Dovecot won't try to compile it.
      preStart = ''
        rm -rf ${stateDir}/sieve
      '' + optionalString (cfg.sieveScripts != {}) ''
        mkdir -p ${stateDir}/sieve
        ${concatStringsSep "\n" (mapAttrsToList (to: from: ''
          if [ -d '${from}' ]; then
            mkdir '${stateDir}/sieve/${to}'
            cp -p "${from}/"*.sieve '${stateDir}/sieve/${to}'
          else
            cp -p '${from}' '${stateDir}/sieve/${to}'
          fi
          ${pkgs.dovecot_pigeonhole}/bin/sievec '${stateDir}/sieve/${to}'
        '') cfg.sieveScripts)}
        chown -R '${cfg.mailUser}:${cfg.mailGroup}' '${stateDir}/sieve'
      '';
    };

    environment.systemPackages = [ dovecotPkg ];

    assertions = [
      { assertion = intersectLists cfg.protocols [ "pop3" "imap" ] != [];
        message = "dovecot needs at least one of the IMAP or POP3 listeners enabled";
      }
      { assertion = isNull cfg.sslServerCert == isNull cfg.sslServerKey
          && (!(isNull cfg.sslCACert) -> !(isNull cfg.sslServerCert || isNull cfg.sslServerKey));
        message = "dovecot needs both sslServerCert and sslServerKey defined for working crypto";
      }
      { assertion = cfg.showPAMFailure -> cfg.enablePAM;
        message = "dovecot is configured with showPAMFailure while enablePAM is disabled";
      }
      { assertion = (cfg.sieveScripts != {}) -> ((cfg.mailUser != null) && (cfg.mailGroup != null));
        message = "dovecot requires mailUser and mailGroup to be set when sieveScripts is set";
      }
    ];

  };

}
