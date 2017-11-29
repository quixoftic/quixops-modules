let

  lib = import ../lib.nix;

in

{ system ? builtins.currentSystem
, pkgs ? (import lib.fetchNixPkgs) { inherit system; }
, ... }:


let

  testing = import <nixpkgs/nixos/lib/testing.nix> { inherit system; };
  inherit (testing) makeTest;

  makeUsersTest = name: machineAttrs:
    makeTest {

      name = "users-${name}";

      meta = with lib.quixopsMaintainers; {
        maintainers = [ dhess ];
      };

      machine = { config, pkgs, ... }: {

        imports = [
          ./common/users.nix
        ] ++ lib.quixopsModules;
        nixpkgs.overlays = lib.quixopsOverlays;

      } // machineAttrs;

      testScript = { nodes, ... }:
      let
        alicePassword = nodes.machine.config.users.users.alice.password;
      in
      ''
        $machine->waitForUnit("multi-user.target");

        subtest "immutable-users", sub {
          $machine->succeed("(echo notalicespassword; echo notalicespassword) | passwd alice");
          $machine->waitUntilTTYMatches(1, "login: ");
          $machine->sendChars("alice\n");
          $machine->waitUntilTTYMatches(1, "Password: ");
          $machine->sendChars("notalicespassword\n");
          $machine->waitUntilTTYMatches(1, "alice\@machine");

          $machine->shutdown();
          $machine->waitForUnit("multi-user.target");
          $machine->waitUntilTTYMatches(1, "login: ");
          $machine->sendChars("alice\n");
          $machine->waitUntilTTYMatches(1, "Password: ");
          $machine->sendChars("${alicePassword}\n");
          $machine->waitUntilTTYMatches(1, "alice\@machine");
        };
      '';
    };

in
{

  globalEnableTest = makeUsersTest "global-enable" { quixops.defaults.enable = true; };
  usersEnableTest = makeUsersTest "users-enable" { quixops.defaults.users.enable = true; };

}