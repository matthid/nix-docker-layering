{
    pkgs ? import <nixpkgs> {},
    storeDir ? builtins.storeDir
}:
let
  lib = pkgs.lib;
  defaultArchitecture = pkgs.go.GOARCH;
  writePython3 = pkgs.writers.writePython3;
  writeText = pkgs.writers.writeText;
  symlinkJoin = pkgs.symlinkJoin;
  fakeroot = pkgs.fakeroot;
  proot = pkgs.proot;
  runCommand = pkgs.runCommand;
  coreutils = pkgs.coreutils;
  buildPackages = pkgs.buildPackages;
  jq = pkgs.jq;
  btar = pkgs.btar;
  python3 = pkgs.python3;
  makeWrapper = pkgs.makeWrapper;

  inherit (lib)
    optionals
    optionalString
    ;

  call_slurpfile_generator = (
    # Write the references of `path' to a file, in order of how "popular" each
    # reference is. Nix 2 only.
    { path
    , exclude_paths, slurpfile_generator, gen_args
    , fromImage, maxLayers, availableLayersFile }:
        let
            argsFile =
                runCommand "closure-paths"
                {
                  exportReferencesGraph.graph = path;
                  __structuredAttrs = true;
                  preferLocalBuild = true;
                  generatorArguments = gen_args;
                  inherit maxLayers fromImage;
                  nativeBuildInputs = [ coreutils python3 availableLayersFile exclude_paths ];
                }
                ''
                  echo >&2 "starting call_slurpfile_generator"
                  availableLayers=$(cat ${availableLayersFile})
                  EXCLUDE_PATHS=( ${builtins.concatStringsSep " " (map (x: ''"${x}"'') exclude_paths)} )
                  ${python3}/bin/python3 ${./cleanup_dependencies.py} "$NIX_ATTRS_JSON_FILE" "$availableLayers" "''${EXCLUDE_PATHS[@]}" > $out

                  echo >&2 "call_slurpfile_generator OK"
                '';
        in
            slurpfile_generator { inherit argsFile; }
  );

  # The default implementation https://github.com/NixOS/nixpkgs/blob/69ac79b3ffd2d8c2e8ab053ab11a8311649f35e8/pkgs/build-support/docker/default.nix#L520
  default_generator = { argsFile }: runCommand "default_generator.json" {
     nativeBuildInputs = [ jq ];
     preferLocalBuild = true;
     inherit argsFile;
  } ''
    echo >&2 "Creating docker with default layers..."

    availableLayers=$(jq -r .availableLayers ${argsFile})
    maxLayers=$(jq -r .maxLayers ${argsFile})
    dependencies_file=${argsFile}
    ${python3}/bin/python3 ${./closure_graph.py} "$dependencies_file" "graph" > paths.txt

    # Create $maxLayers worth of Docker Layers, one layer per store path
    # unless there are more paths than $maxLayers. In that case, create
    # $maxLayers-1 for the most popular layers, and smush the remainaing
    # store paths in to one final layer.
    #
    # The following code is fiddly w.r.t. ensuring every layer is
    # created, and that no paths are missed. If you change the
    # following lines, double-check that your code behaves properly
    # when the number of layers equals:
    #      maxLayers-1, maxLayers, and maxLayers+1, 0
    cat paths.txt |
      ${jq}/bin/jq -sR --argjson maxLayers "$availableLayers" '
        rtrimstr("\n") | split("\n")
          | (.[:$maxLayers-1] | map([.])) + [ .[$maxLayers-1:] ]
          | map(select(length > 0))
        ' > $out
  '';


  # The default implementation https://github.com/NixOS/nixpkgs/blob/69ac79b3ffd2d8c2e8ab053ab11a8311649f35e8/pkgs/build-support/docker/default.nix#L520
  equal_generator = { argsFile }: runCommand "equal_generator.json" {
     nativeBuildInputs = [ jq ];
     preferLocalBuild = true;
     inherit argsFile;
  } ''
    echo >&2 "Creating docker with equal layers..."

    availableLayers=$(jq -r .availableLayers ${argsFile})
    maxLayers=$(jq -r .maxLayers ${argsFile})
    dependencies_file=${argsFile}
    ${python3}/bin/python3 ${./closure_graph.py} "$dependencies_file" "graph" > paths.txt
    ${python3}/bin/python3 ${./create_slurpfile.py} paths.txt "$availableLayers" > $out
  '';
in
{
  generators = {
        default = default_generator;
        equal = equal_generator;
  };

  # Arguments are documented in ../../../doc/build-helpers/images/dockertools.section.md
  streamLayeredImage = lib.makeOverridable (
    {
      name
    , tag ? null
    , fromImage ? null
    , contents ? [ ]
    , config ? { }
    , architecture ? defaultArchitecture
    , created ? "1970-01-01T00:00:01Z"
    , uid ? 0
    , gid ? 0
    , uname ? "root"
    , gname ? "root"
    , maxLayers ? 100
    , extraCommands ? ""
    , fakeRootCommands ? ""
    , enableFakechroot ? false
    , includeStorePaths ? true
    , passthru ? {}
    , slurpfileGenerator ? default_generator
    , genArgs ? {}
    }:
      assert
      (lib.assertMsg (maxLayers > 1)
        "the maxLayers argument of dockerTools.buildLayeredImage function must be greather than 1 (current value: ${toString maxLayers})");
      let
        baseName = baseNameOf name;

        streamScript = writePython3 "stream" { } ./stream_layered_image.py;
        baseJson = writeText "${baseName}-base.json" (builtins.toJSON {
          inherit config architecture;
          os = "linux";
        });

        contentsList = if builtins.isList contents then contents else [ contents ];
        bind-paths = builtins.toString (builtins.map (path: "--bind=${path}:${path}!") [
          "/dev/"
          "/proc/"
          "/sys/"
          "${builtins.storeDir}/"
          "$out/layer.tar"
        ]);

        # We store the customisation layer as a tarball, to make sure that
        # things like permissions set on 'extraCommands' are not overridden
        # by Nix. Then we precompute the sha256 for performance.
        customisationLayer = symlinkJoin {
          name = "${baseName}-customisation-layer";
          paths = contentsList;
          inherit extraCommands fakeRootCommands;
          nativeBuildInputs = [
            fakeroot
          ] ++ optionals enableFakechroot [
            proot
          ];
          postBuild = ''
            mv $out old_out
            (cd old_out; eval "$extraCommands" )

            mkdir $out
            ${if enableFakechroot then ''
              proot -r $PWD/old_out ${bind-paths} --pwd=/ fakeroot bash -c '
                source $stdenv/setup
                eval "$fakeRootCommands"
                tar \
                  --sort name \
                  --exclude=./proc \
                  --exclude=./sys \
                  --exclude=.${builtins.storeDir} \
                  --numeric-owner --mtime "@$SOURCE_DATE_EPOCH" \
                  --hard-dereference \
                  -cf $out/layer.tar .
              '
            '' else ''
              fakeroot bash -c '
                source $stdenv/setup
                cd old_out
                eval "$fakeRootCommands"
                tar \
                  --sort name \
                  --numeric-owner --mtime "@$SOURCE_DATE_EPOCH" \
                  --hard-dereference \
                  -cf $out/layer.tar .
              '
            ''}
            sha256sum $out/layer.tar \
              | cut -f 1 -d ' ' \
              > $out/checksum
          '';
        };

        closureRoots = lib.optionals includeStorePaths /* normally true */ (
          [ baseJson customisationLayer ]
        );
        overallClosure = writeText "closure" (lib.concatStringsSep " " closureRoots);

        # These derivations are only created as implementation details of docker-tools,
        # so they'll be excluded from the created images.
        unnecessaryDrvs = [ baseJson overallClosure customisationLayer ];
        availableLayersFile = runCommand "availableLayers"
          {
            inherit fromImage maxLayers;
            nativeBuildInputs = [ jq python3 btar ];
          }
          ''
          # Compute the number of layers that are already used by a potential
          # 'fromImage' as well as the customization layer. Ensure that there is
          # still at least one layer available to store the image contents.
          usedLayers=0

          # subtract number of base image layers
          if [[ -n "$fromImage" ]]; then
            (( usedLayers += $(tar -xOf "$fromImage" manifest.json | jq '.[0].Layers | length') ))
          fi

          # one layer will be taken up by the customisation layer
          (( usedLayers += 1 ))

          if ! (( $usedLayers < $maxLayers )); then
            echo >&2 "Error: usedLayers $usedLayers layers to store 'fromImage' and" \
                      "'extraCommands', but only maxLayers=$maxLayers were" \
                      "allowed. At least 1 layer is required to store contents."
            exit 1
          fi
          availableLayers=$(( maxLayers - usedLayers ))
          echo "$availableLayers" > $out
        '';

        slurpFile = call_slurpfile_generator {
          inherit fromImage maxLayers availableLayersFile;
          path = overallClosure; exclude_paths=unnecessaryDrvs;
          slurpfile_generator = slurpfileGenerator;
          gen_args = genArgs;
        };

        conf = runCommand "${baseName}-conf.json"
          {
            inherit fromImage maxLayers created uid gid uname gname slurpFile;
            imageName = lib.toLower name;
            preferLocalBuild = true;
            passthru.imageTag =
              if tag != null
              then tag
              else
                lib.head (lib.strings.splitString "-" (baseNameOf conf.outPath));
            nativeBuildInputs = [ jq python3 ];
          } ''

          ${if (tag == null) then ''
            outName="$(basename "$out")"
            outHash=$(echo "$outName" | cut -d - -f 1)

            imageTag=$outHash
          '' else ''
            imageTag="${tag}"
          ''}

          # convert "created" to iso format
          if [[ "$created" != "now" ]]; then
              created="$(date -Iseconds -d "$created")"
          fi

          # The index on $store_layers is necessary because the --slurpfile
          # automatically reads the file as an array.
          cat ${baseJson} | jq '
            . + {
              "store_dir": $store_dir,
              "from_image": $from_image,
              "store_layers": $store_layers[0],
              "customisation_layer": $customisation_layer,
              "repo_tag": $repo_tag,
              "created": $created,
              "uid": $uid,
              "gid": $gid,
              "uname": $uname,
              "gname": $gname
            }
            ' --arg store_dir "${storeDir}" \
              --argjson from_image ${if fromImage == null then "null" else "'\"${fromImage}\"'"} \
              --slurpfile store_layers ${slurpFile} \
              --arg customisation_layer ${customisationLayer} \
              --arg repo_tag "$imageName:$imageTag" \
              --arg created "$created" \
              --arg uid "$uid" \
              --arg gid "$gid" \
              --arg uname "$uname" \
              --arg gname "$gname" |
            tee $out
        '';

        result = runCommand "stream-${baseName}"
          {
            inherit (conf) imageName;
            preferLocalBuild = true;
            passthru = passthru // {
              inherit (conf) imageTag;

              # Distinguish tarballs and exes at the Nix level so functions that
              # take images can know in advance how the image is supposed to be used.
              isExe = true;
            };
            nativeBuildInputs = [ makeWrapper ];
          } ''
          makeWrapper ${streamScript} $out --add-flags ${conf}
        '';
      in
      result
  );
}
