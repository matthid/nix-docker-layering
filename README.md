# Nix docker layering

Allows to customize the layering logic as you need it. Especially useful for large containers.

## Other projects

- Official Docs: https://nix.dev/tutorials/nixos/building-and-running-docker-images.html
- Default Way: https://grahamc.com/blog/nix-and-layered-docker-images/
- Faster Way: https://blog.eigenvalue.net/2023-nix2container-everything-once/

But what if you want to implement/experiment with custom strategies? This project might help!

## Example usage

```usage.nix
{ pkgs ? import <nixpkgs> {} }:
let
  # Example: Importing directly from a GitHub repository
  docker_layering = import (pkgs.fetchTarball {
    # URL of the tarball archive of the specific commit, branch, or tag
    url = "https://github.com/matthid/nix-docker-layering/archive/1.0.0.tar.gz";
    #sha256 = "<hash>";
  }) { inherit pkgs; };
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
```

## Existing stratgies

- `generators.default` -> Similar to the "Default Way" as explained in the blogpost above.
- `generators.equal` -> Instead of single package layers, group them by equal size.


## Create your own strategy

Look at the existing generators, define your own accordingly.
They don't need to be written in python basically a generator is a derivation which has a json input file  as parameter (all the context you will need) and should write a json output file (a docker slurpfile for the layers)


## Contributing

Change and run `$(nix-build test/usage.nix) | docker load` to test.