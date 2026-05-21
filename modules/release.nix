{
  lib,
  self,
  ...
}:
{
  perSystem =
    {
      pkgs,
      config,
      manifest,
      ...
    }:
    {
      files.files = [
        {
          path = "RELEASE";
          drv = pkgs.writeText "RELEASE" manifest.release.version;
        }
      ];
      # Create a shell script to cut a new release. The script runs at the end of the CI/CD workflow, and creates a new tagged
      # release if the first line of RELEASE contains a newer version than the last release. The release notes come from the
      # rest of RELEASE and the supportedVersions list above, and all Lix archives for all systems are included as assets.
      packages.release-script = pkgs.writeShellApplication {
        name = "release";

        runtimeInputs = [
          pkgs.coreutils
          pkgs.gitMinimal
          pkgs.github-cli
        ];

        text =
          let
            inherit (config.packages) markdown-manifest;
            # Produce a list of all Lix archives for all systems, to pass to the GitHub CLI when making a release.
            releaseAssets = lib.pipe self.legacyPackages [
              (lib.mapAttrsToList (_sys: ps: builtins.attrValues ps.lixArchives))
              lib.flatten
              (builtins.map (archive: "\"$lix_archives/${archive.fileName}\""))
              (lib.join " ")
            ];
          in
          # sh
          ''
            if [ "$GITHUB_ACTIONS" != "true" ]; then
              echo >&2 "not running in GitHub, exiting"
              exit 1
            fi

            lix_archives="$1"
            release_file="$2"
            release="$(head -n1 "$release_file")"
            prev_release="$(gh release list -L 1 | cut -f 3)"

            if [ "$release" = "$prev_release" ]; then
              echo >&2 "Release tag not updated ($release)"
              exit
            else
              release_notes="$(mktemp)"
              tail -n+2 "$release_file" > "$release_notes"

              echo "" | cat >>"$release_notes" - "${markdown-manifest}"

              echo >&2 "New release: $prev_release -> $release"

              gh release create "$release" ${releaseAssets} \
                  --title "$GITHUB_REPOSITORY@$release" \
                  --notes-file "$release_notes"
            fi
          '';
      };
    };
}
