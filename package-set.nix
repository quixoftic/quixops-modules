let
  nixpkgs = (import ./lib.nix).nixpkgs;

in

{ pkgs ? nixpkgs {} }:

with pkgs.lib;
let
  self = foldl'
    (prev: overlay: prev // (overlay (pkgs // self) (pkgs // prev)))
    {} (map import (import ./overlays.nix));
in
self //
{
  overlays.lib = import ./overlays/lib.nix;
}
