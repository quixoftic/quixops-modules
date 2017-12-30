let

  lib = import ../lib.nix;
  quixopsModules = (import ../.).modules;

in

{ system ? builtins.currentSystem
, pkgs ? (import lib.fetchNixPkgs) { inherit system; }
, makeTest
, ... }:


let

  makeFfmpegSnapshotTest = name: machineAttrs:
    makeTest {
      name = "ffmpeg-snapshot-${name}";
      meta = with lib.quixopsMaintainers; {
        maintainers = [ dhess ];
      };
      machine = { config, pkgs, ... }: {
        imports = [
          ./common/users.nix
        ] ++ quixopsModules;
        quixops.defaults.overlays.enable = true;
      } // machineAttrs;
      testScript = { nodes, ... }:
      let
        pkgs = nodes.machine.pkgs;
      in
      ''
        $machine->waitForUnit("multi-user.target");

        subtest "ffmpeg-snapshot", sub {
          $machine->succeed("${pkgs.ffmpeg-snapshot}/bin/ffmpeg -version");
        };
      '';
    };

in
{

  defaultTest = makeFfmpegSnapshotTest "default" { };

}
