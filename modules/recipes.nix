{ lib, actionLib, ... }:
{

  perSystem =
    { pkgs, config, ... }:
    {
      files.writer.exeFilename = "write-action";
      packages = {
        write-action = config.files.writer.drv;

        write-ci = pkgs.callPackage (
          { git }:
          pkgs.writers.writeBashBin "write-ci" { }
            # sh
            ''
              set -o errexit
              set -o nounset
              set -o pipefail

              root="$(${lib.getExe git} rev-parse --show-toplevel)"
              cd "$root"
              workflow_dir="$root/.github/workflows"
              mkdir -p "$workflow_dir"
              cp -rf ${config.githubActions.workflowsDir}/* "$workflow_dir/"
              chmod -R u+w "$workflow_dir"
            ''
        ) { };

        write-repo =
          pkgs.writers.writeBashBin "write-repo" { }
            # sh
            ''
              ${config.packages.write-ci}/bin/write-ci
              ${config.packages.write-action}/bin/write-action
            '';

        sync-release = pkgs.callPackage (
          { git, jq }:
          pkgs.writers.writeBashBin "sync-release" { }
            # sh
            ''
              set -o errexit
              set -o nounset
              set -o pipefail

              root="$(${lib.getExe git} rev-parse --show-toplevel)"
              cd "$root"
              manifest="$root/manifest.json"
              release="$root/RELEASE"
              ${lib.getExe jq} -r '.release.version' "$manifest" > "$release"
            ''
        ) { };

        bump-release-minor = pkgs.callPackage (
          {
            git,
            jq,
            sync-release,
          }:
          pkgs.writers.writeBashBin "bump-release-minor" { }
            # sh
            ''
              set -o errexit
              set -o nounset
              set -o pipefail

              root="$(${lib.getExe git} rev-parse --show-toplevel)"
              cd "$root"
              manifest="$root/manifest.json"
              tmp="$(mktemp)"
              # The version being retired becomes release.previous, which is what
              # a null manifest.bootstrap follows. lixVersion is baked in at build
              # time, so run this before re-entering the shell on a new nixpkgs -
              # `update` already orders it that way.
              ${lib.getExe jq} --arg lix "${config.packages.lix.version}" '
                .release.previous = { version: .release.version, lixVersion: $lix }
                | .release.version |= (split(".") | .[1] = (.[1]|tonumber+1|tostring) | .[2] = "0" | join("."))
              ' "$manifest" > "$tmp"
              mv "$tmp" "$manifest"
              ${sync-release}/bin/sync-release
            ''
        ) { inherit (config.packages) sync-release; };

        add-new-lix = pkgs.callPackage (
          { git, jq }:
          pkgs.writers.writeBashBin "add-new-lix" { }
            # sh
            ''
              set -o errexit
              set -o nounset
              set -o pipefail

              if [ $# -ne 1 ]; then
                echo >&2 "usage: add-new-lix <version-set>"
                exit 1
              fi
              version="$1"

              root="$(${lib.getExe git} rev-parse --show-toplevel)"
              cd "$root"
              manifest="$root/manifest.json"
              tmp="$(mktemp)"
              ${lib.getExe jq} --arg v "$version" '.lixSeries | contains([ $v ])' "$manifest" > /dev/null 2>&1 && {
                  echo "$version is already in $manifest"
                  exit 1
              }
              ${lib.getExe jq} --arg v "$version" '.lixSeries |= [ $v ] + .' "$manifest" > "$tmp"
              mv "$tmp" "$manifest"
            ''
        ) { };

        update =
          pkgs.callPackage
            (
              {
                npins,
                add-new-lix,
                bump-release-minor,
                write-repo,
                sync-release,
                bump-pins,
              }:
              pkgs.writers.writeBashBin "update" { }
                # sh
                ''
                  set -o errexit
                  set -o nounset
                  set -o pipefail

                  ${lib.getExe npins} update nixpkgs

                  if [ $# -ge 1 ]; then
                      ${add-new-lix}/bin/add-new-lix "$1"
                  fi

                  ${bump-pins}/bin/bump-pins && \
                  ${bump-release-minor}/bin/bump-release-minor && \
                  ${write-repo}/bin/write-repo && \
                  ${sync-release}/bin/sync-release
                ''
            )
            {
              inherit (config.packages)
                add-new-lix
                bump-release-minor
                write-repo
                sync-release
                bump-pins
                ;
            };

        bump-pins = pkgs.callPackage (
          {
            jq,
            git,
            gh,
          }:
          pkgs.writers.writeBashBin "bump-pins" { }
            # sh
            ''
              export PATH="${
                lib.makeBinPath [
                  jq
                  gh
                  git
                ]
              }:$PATH"
              ${builtins.readFile (actionLib.scriptsPath + /bump-pins.sh)}
            ''
        ) { };
      };
    };
}
