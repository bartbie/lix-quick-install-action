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
  systems = [
    "x86_64-linux"
    "aarch64-linux"
    "aarch64-darwin"
    "x86_64-darwin"
  ];

  _module.args = commonArgs;
  perSystem =
    { system, ... }:
    {
      _module.args = commonArgs // {
        pkgs = import inputs.nixpkgs { inherit system; };
      };
    };
}
