{ system ? "x86_64-linux"
, pkgs
, makeTest
, ...
}:


let

  makeZncTest = name: machineAttrs:
    makeTest {
      name = "znc-${name}";
      meta = with pkgs.lib.maintainers; {
        maintainers = [ dhess-pers ];
      };

      nodes = {

        localhostServer = { config, ... }:
        {
          nixpkgs.localSystem.system = system;
          imports =
            pkgs.lib.quixops-modules.modules ++
            pkgs.lib.quixops-modules.testing.testModules;

          # Use the test key deployment system.
          deployment.reallyReallyEnable = true;

          services.qx-znc = {
            enable = true;
            mutable = false;
            openFirewall = true;
            configLiteral = pkgs.lib.quixops-modules.mkZncConfig {
              inherit pkgs;
              zncServiceConfig = config.services.qx-znc;
            };
            confOptions = {
              host = "localhost";
              userName = "bob-znc";
              nick = "bob";
              passBlock = "
                <Pass password>
                  Method = sha256
                  Hash = e2ce303c7ea75c571d80d8540a8699b46535be6a085be3414947d638e48d9e93
                  Salt = l5Xryew4g*!oa(ECfX2o
                </Pass>
              ";
            };
          };
        };

        server = { config, ... }:
        {
          nixpkgs.localSystem.system = system;
          imports =
            pkgs.lib.quixops-modules.modules ++
            pkgs.lib.quixops-modules.testing.testModules;

          # Use the test key deployment system.
          deployment.reallyReallyEnable = true;

          services.qx-znc = {
            enable = true;
            mutable = false;
            openFirewall = true;
            configLiteral = pkgs.lib.quixops-modules.mkZncConfig {
              inherit pkgs;
              zncServiceConfig = config.services.qx-znc;
            };
            confOptions = {
              userName = "bob-znc";
              nick = "bob";
              passBlock = "
                <Pass password>
                  Method = sha256
                  Hash = e2ce303c7ea75c571d80d8540a8699b46535be6a085be3414947d638e48d9e93
                  Salt = l5Xryew4g*!oa(ECfX2o
                </Pass>
              ";
            };
          };
        };

        client = { config, ... }:
        {
          nixpkgs.localSystem.system = system;
        };

      } // machineAttrs;

      testScript = { nodes, ... }:
      ''
        startAll;

        $server->waitForUnit("znc.service");
        $localhostServer->waitForUnit("znc.service");

        subtest "no-remote-connections", sub {
          $client->fail("${pkgs.netcat}/bin/nc -w 5 localhostServer ${builtins.toString nodes.localhostServer.config.services.qx-znc.confOptions.port}");
        };

        subtest "localhost-connections", sub {
          $localhostServer->succeed("${pkgs.netcat}/bin/nc -w 5 localhost ${builtins.toString nodes.localhostServer.config.services.qx-znc.confOptions.port}");
        };

        subtest "allow-remote-connections", sub {
          $client->succeed("${pkgs.netcat}/bin/nc -w 5 server ${builtins.toString nodes.server.config.services.qx-znc.confOptions.port}");
        };
      '';

    };

in
{

  defaultTest = makeZncTest "default" { };

}
