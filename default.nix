{ pkgs ? import <nixpkgs> {} }:

let
  dockerTools = import ./docker-tools { inherit pkgs; };
in {
  inherit dockerTools;
  streamLayeredImage = dockerTools.streamLayeredImage;
  generators = dockerTools.generators;
}