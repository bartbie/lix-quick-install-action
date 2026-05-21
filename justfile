fmt:
    nix shell -f ./shell.nix -c treefmt

bump-nixpkgs:
    npins update nixpkgs
