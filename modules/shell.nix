{
  perSystem =
    { pkgs, config, ... }:
    {
      devShells.default = pkgs.mkShell {
        name = "lix-quick-install-action-devshell";
        packages = [
          pkgs.nixfmt
          pkgs.nil
          pkgs.npins
          pkgs.just
          pkgs.treefmt
          pkgs.jq
        ]
        ++ (builtins.attrValues {
          inherit (config.packages)
            write-action
            write-ci
            write-repo
            bump-release-minor
            add-new-lix
            update
            sync-release
            bump-pins
            ;
        });
      };
    };
}
