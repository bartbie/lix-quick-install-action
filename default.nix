let
  sources = import ./npins;
  with-inputs = import sources.with-inputs sources {
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
