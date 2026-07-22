let
  sources = import ./npins;

  # action-* pins are GitHub Action revisions read straight out of sources.json;
  # they are not flake inputs. with-inputs probes every input for a flake.nix
  # with pathExists, which forces outPath and so fetches the tarball - keep them
  # out rather than tagging each one `flake = false`.
  isAction = n: builtins.substring 0 7 n == "action-";
  nixSources = builtins.removeAttrs sources (builtins.filter isAction (builtins.attrNames sources));

  with-inputs = import sources.with-inputs nixSources {
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";
    files = sources.files // {
      flake = false;
    };
    # uncomment on CI for local checkout
    # flake-file = import ./../../modules;
  };

  outputs =
    inputs@{ flake-parts, import-tree, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } (import-tree ./modules);
in
with-inputs outputs
