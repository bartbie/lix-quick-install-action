{
  lib,
  inputs,
  config,
  ...
}:
let
  manifest = builtins.fromJSON (builtins.readFile ../manifest.json);
  action-lock = builtins.fromJSON (builtins.readFile ../action-lock.json);
  commonArgs = {
    inherit manifest action-lock;
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
