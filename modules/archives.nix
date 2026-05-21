{
  lib,
  actionLib,
  manifest,
  self,
  ...
}:
{
  perSystem =
    {
      pkgs,
      system,
      config,
      ...
    }:
    let
      inherit (config.legacyPackages)
        lixArchives
        lixVersions
        ;

      latest = actionLib.seriesToAttr (builtins.head (actionLib.sortVersions manifest.lixSeries));
      archiveFor = lix: config.packages.store-archive.override { inherit lix; };
    in
    {
      # sets of drvs, .packages.* would type-check fail
      legacyPackages = {
        lixVersions = lib.genAttrs (map actionLib.seriesToAttr manifest.lixSeries) (
          attr: pkgs.lixPackageSets.${attr}.lix
        );

        lixArchives = builtins.mapAttrs (_: archiveFor) lixVersions;
      };
      packages = {
        # latest version always available
        lix = lixVersions.${latest};

        combined-archives = pkgs.symlinkJoin {
          name = "lix-archives";
          paths = builtins.attrValues lixArchives;
        };

        markdown-manifest =
          # Generate a markdown file containing a list of Lix versions that the action supports.
          # This gets included into the release's description.
          lib.pipe self.legacyPackages [
            (lib.mapAttrsToList (
              sys: sysPkgs:
              let
                mdList = lib.pipe sysPkgs.lixArchives [
                  actionLib.getVersions
                  (builtins.map (s: "- ${s}"))
                  (lib.join "\n")
                ];
              in
              ''
                ## supported lix versions on ${sys}:
                ${mdList}
              ''
            ))
            (lib.join "\n")
            (pkgs.writeText "supportedVersions")
          ];

        store-archive =
          pkgs.callPackage
            (
              {
                runCommand,
                closureInfo,

                gnutar,
                zstd,

                lix,
              }:

              # Produces an archive for a Lix version that gets installed on runners with the action. The archive contains a minimal
              # Nix store containing just the closure over the Lix derivation and some supporting files to setup the Nix store
              # database, and get Lix installed in the global profile.
              runCommand "lix-${lix.version}-archive"
                {
                  buildInputs = [
                    lix
                    gnutar
                    zstd
                  ];

                  closureInfo = closureInfo { rootPaths = [ lix ]; };
                  fileName = "lix-${lix.version}-${system}.tar.zstd";
                  inherit (lix) version;
                }
                ''
                  mkdir -p $out root/nix/var/{nix,lix-quick-install-action}
                  ln -s ${lix} root/nix/var/lix-quick-install-action/lix
                  cp $closureInfo/registration root/nix/var/lix-quick-install-action
                  tar -cvT $closureInfo/store-paths -C root nix | zstd -o "$out/$fileName"
                ''
            )
            {
              lix = lixVersions.${latest};
            };
      };
    };
}
