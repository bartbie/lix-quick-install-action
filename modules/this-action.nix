{ lib, inputs, ... }:
{
  imports = [
    (inputs.files + "/flake-module.nix")
  ];

  perSystem =
    {
      pkgs,
      config,
      manifest,
      ...
    }:
    let
      yaml = {
        name = "Quick Install Lix";
        description = "Quickly installs Lix in unprivileged single-user mode";
        author = manifest.owner;

        inputs = {
          lix_version = {
            required = true;
            default = config.packages.lix.version;
            description = ''
              The version of Lix that should be installed.

              If not specified, the latest stable Lix release is used. Note that each
              release of lix-quick-install-action has a specific set of supported
              Lix versions, which do not change. You can check what Lix versions are
              supported by the version of lix-quick-install-action you're using by
              going to https://github.com/canidae-solutions/lix-quick-install-action/releases.
            '';
          };

          lix_conf = {
            required = false;
            description = ''
              If set, this configuration is written to XDG_CONFIG_HOME/nix/nix.conf,
              which is read by Lix.
              See https://docs.lix.systems/manual/lix/stable/command-ref/conf-file.html for
              information on what settings that are available. Make sure the settings
              you define are supported by the Lix version you're using.
            '';
          };

          github_access_token = {
            default = "\${{ github.token }}";
            description = ''
              Configure Lix to use the specified token when fetching from GitHub.
            '';
          };

          lix_on_tmpfs = {
            required = true;
            default = false;
            description = ''
              Installs /nix on a tmpfs mount. This can make Lix operations faster, but
              you risk running out of memory if your Nix store grows too big. Only
              enable this if you're absolutely sure the size of your Nix store (and
              database, logs etc) will be considerably less than the available memory.
              This option does nothing on macOS runners.
            '';
          };

          lix_archives_url = {
            required = false;
            description = ''
              Don't use. For bootstrapping purposes only.
            '';
          };

          enable_kvm = {
            description = ''
              Enable KVM for hardware-accelerated virtualization on Linux, if available.
            '';
            required = false;
            default = true;
          };
        };

        runs = {
          using = "composite";
          steps = [
            {
              name = "Install Lix in single-user mode";
              run = "\${{ github.action_path }}/scripts/nix-quick-install.sh";
              shell = "bash";
              env = {
                RELEASE_FILE = "\${{ github.action_path }}/RELEASE";
                # Fallback for when GITHUB_ACTION_REPOSITORY is unset, i.e. the
                # action is used locally as `uses: ./`.
                ACTION_REPOSITORY = "${manifest.owner}/${manifest.repo}";
                LIX_VERSION = "\${{ inputs.lix_version }}";
                LIX_CONF = "\${{ inputs.lix_conf }}";
                LIX_ARCHIVES_URL = "\${{ inputs.lix_archives_url }}";
                LIX_ON_TMPFS = "\${{ inputs.lix_on_tmpfs }}";
                GITHUB_ACCESS_TOKEN = "\${{ inputs.github_access_token }}";
                ENABLE_KVM = "\${{ inputs.enable_kvm }}";
              };
            }
          ];
        };

        branding = {
          icon = "zap";
          color = "purple";
        };
      };
    in
    {
      files.files = [
        {
          path = "action.yml";
          drv =
            let
              emit =
                pkgs.writers.writePython3 "emit-yaml"
                  {
                    libraries = [ pkgs.python3Packages.ruamel-yaml ];
                    # who cares its formatted better than 90% of python out there
                    flakeIgnore = [
                      "E501" # line too long
                      "E302" # expected 2 blank lines
                      "E305" # blank lines after function
                      "W292" # no newline at end of file
                    ];
                  }
                  # py
                  ''
                    import sys
                    import json
                    from ruamel.yaml import YAML
                    from ruamel.yaml.scalarstring import LiteralScalarString
                    from ruamel.yaml.comments import CommentedMap, CommentedSeq


                    def style(obj):
                        match obj:
                            case dict():
                                return CommentedMap((k, style(v)) for k, v in obj.items())
                            case list():
                                return CommentedSeq(style(v) for v in obj)
                            case str() if "\n" in obj:
                                return LiteralScalarString(obj)
                            case _:
                                return obj


                    def space_between(m):
                        for k in list(m.keys())[1:]:
                            m.yaml_set_comment_before_after_key(k, before="\n")


                    data = style(json.load(sys.stdin))

                    if isinstance(data, CommentedMap):
                        space_between(data)                                # between top-level sections
                        for section in ("inputs", "outputs"):              # between entries in each
                            if isinstance(data.get(section), CommentedMap):
                                space_between(data[section])

                    y = YAML()
                    y.default_flow_style = False
                    y.width = 4096  # don't auto-fold long lines
                    y.indent(mapping=2, sequence=4, offset=2)

                    print("# This file is automatically generated from Nix configuration. Do not edit directly.\n")
                    y.dump(data, sys.stdout)
                  '';
            in
            pkgs.runCommand "action.yml"
              {
                json = builtins.toJSON yaml;
                passAsFile = [ "json" ];
              }
              ''
                ${emit} < $jsonPath > $out
              '';
        }
      ];
    };
}
