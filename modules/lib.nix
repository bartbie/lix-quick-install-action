{ lib, actionLib, ... }:
let
  # "2.95" -> "2_95"
  normalizeVer = s: "${builtins.replaceStrings [ "." ] [ "_" ] s}";
in
{
  flake.actionLib = {
    # "2.95" -> "lix_2_95"; matches the attr naming in pkgs.lixPackageSets.
    seriesToAttr = s: "lix_${normalizeVer s}";

    # Makes a set of Lix packages, where the version is the key and the package is the value.
    #
    # Accepts:
    # - f: A function that accepts a system, and a Lix package, that produces the final value assigned to the version in
    #   the set.
    # - lixen: A function that accepts a system, and returns a list of Lix packages to include in the set.
    # - system: The system to produce a set for.
    mkLixSet =
      f: lixen: system:
      let
        mapLix = lix: lib.nameValuePair "v${normalizeVer lix.version}" (f system lix);
      in
      lib.listToAttrs (builtins.map mapLix (lixen system));

    # Release tags carry a `v`, manifest.json stores bare semver. Normalize at
    # every point that names a real tag rather than trusting either side.
    toTag = v: "v${lib.removePrefix "v" v}";

    # Runner label -> platform. Labels mark the arch exception and leave the
    # default implicit, in opposite directions: linux is x86_64 unless -arm,
    # macos is aarch64 unless -intel. The nix double and the suffix
    # upload-artifact names both follow from the label, so manifest.runners
    # stays the only list a platform is added to or dropped from.
    runnerPlatform =
      runner:
      let
        darwin = lib.hasPrefix "macos" runner;
        arm = if darwin then !lib.hasInfix "intel" runner else lib.hasInfix "arm" runner;
      in
      {
        system = "${if arm then "aarch64" else "x86_64"}-${if darwin then "darwin" else "linux"}";
        artifact = "${if darwin then "macOS" else "Linux"}-${if arm then "ARM64" else "X64"}";
      };

    sortVersions =
      vrs:
      lib.pipe vrs [
        lib.naturalSort
        lib.reverseList
      ];

    getVersions =
      archivesOrLixDrvs:
      lib.pipe archivesOrLixDrvs [
        builtins.attrValues
        (builtins.map (drv: drv.version))
        actionLib.sortVersions
      ];
  };
}
