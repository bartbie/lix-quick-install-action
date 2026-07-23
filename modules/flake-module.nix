{
  lib,
  inputs,
  config,
  ...
}:
let
  manifest = builtins.fromJSON (builtins.readFile ../manifest.json);
  # Only the action-* pins; the rest are already in `inputs`.
  sources = import ../npins;
  commonArgs = {
    inherit manifest sources;
    inherit (config.flake) actionLib;
  };
in
{
  # Building for a system no runner covers is how x86_64-darwin outlived the
  # runner that produced it, failing the release long after the build matrix
  # had forgotten it.
  systems = map (r: (config.flake.actionLib.runnerPlatform r).system) manifest.runners;

  _module.args = commonArgs;
  perSystem =
    { system, ... }:
    {
      _module.args = commonArgs // {
        pkgs = import inputs.nixpkgs { inherit system; };
      };
    };
}
