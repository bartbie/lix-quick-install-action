{ lib, actionLib, ... }:
let
  # "2.95" -> "2_95"
  normalizeVer = s: "${builtins.replaceStrings [ "." ] [ "_" ] s}";
in
{
  flake.actionLib = {
    scriptsPath = ../scripts;
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
