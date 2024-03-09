{ pkgs ? import <nixpkgs> {} }:
let
  # Example: Importing directly from a GitHub repository
  docker_layering = import ./../default.nix { inherit pkgs; };
in
docker_layering.streamLayeredImage {
  # Select your strategy or implement your own!
  slurpfileGenerator = docker_layering.generators.equal;
  maxLayers = 20;
  name = "docker_layering_test";
  tag = "latest";

  contents = [
    pkgs.coreutils
    pkgs.findutils
    pkgs.gnugrep
    pkgs.gnused
    pkgs.gawk
    pkgs.bashInteractive
    pkgs.which
    pkgs.file
    pkgs.binutils
    pkgs.diffutils
    pkgs.less
    pkgs.gzip
    pkgs.btar
    pkgs.nano
  ];
  config = {
    Entrypoint = ["${pkgs.bashInteractive}/bin/bash"];
  };
}