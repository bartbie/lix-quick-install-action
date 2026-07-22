{
  lib,
  inputs,
  actionLib,
  ...
}:
{
  imports = [
    inputs.github-actions-nix.flakeModules.default
  ];

  perSystem =
    {
      config,
      manifest,
      action-lock,
      ...
    }:
    let
      inherit (manifest) runners owner;

      mkAction =
        name:
        let
          inherit (action-lock.actions.${name}) repo sha;
        in
        "${repo}@${sha}";

      overrideWith = attr: new: (attr // { with_ = (attr.with_ or { }) // new; });

      onSuccess = what: attr: { if_ = "${what}.outputs.changed == 'true'"; } // attr;

      # 2-arg form: `run name script`. 3-arg form: `run name { id=...; } script`
      # for steps that need extra fields (if_, id, env, ...).
      run =
        name: argsOrScript:
        if builtins.isString argsOrScript then
          {
            inherit name;
            run = argsOrScript;
          }
        else
          script:
          argsOrScript
          // {
            inherit name;
            run = script;
          };

      uses = uses: with_: {
        inherit uses with_;
      };

      downloadFor =
        arch:
        uses (mkAction "download-artifact") {
          name = "lix-archives-${arch}";
          path = "/tmp/archives";
        };

      mkExampleJob =
        path:
        lib.mkMerge [
          singleRunner
          {
            steps = [
              action-harden
              action-checkout
              (uses action-bootstrap { })
              (run "nix run" /* sh */ "nix run ${path}")
            ];
          }
        ];

      lix_version = config.packages.lix.version;

      action-bootstrap = mkAction "lix-quick-install"; # v4

      # Where the archives the CI bootstraps from come from. Setting
      # `manifest.bootstrap` points at somebody else's release, which is what a
      # fresh fork needs - it has published nothing to bootstrap off yet. Null
      # means "the previous release of this repo", recorded in
      # `manifest.release.previous` by bump-release-minor.
      #
      # Either way this trails `manifest.release.version` and
      # `packages.lix.version`, which name the release being built right now.
      # That one has no assets until CI publishes it.
      bootstrap =
        let
          prev = manifest.release.previous or null;
        in
        if manifest.bootstrap != null then
          manifest.bootstrap
        else
          assert lib.assertMsg (prev != null) ''
            manifest.bootstrap is null but manifest.release.previous is unset, so
            there is no earlier release of ${owner}/${manifest.repo} to bootstrap
            from. Point manifest.bootstrap at an upstream release until this fork
            has published one of its own.
          '';
          {
            repo = "${owner}/${manifest.repo}";
            tag = prev.version;
            inherit (prev) lixVersion;
          };

      bootstrap_lix_version = bootstrap.lixVersion;
      bootstrap-url = "https://github.com/${bootstrap.repo}/releases/download/${bootstrap.tag}";

      # StepSecurity harden-runner: must be the FIRST step in every job so it
      # can hook the runner before any other code executes. `audit` mode logs
      # egress without blocking - flip to `block` + `allowed-endpoints` once
      # the audit reports show a stable set of destinations.
      action-harden = uses (mkAction "harden-runner") {
        "egress-policy" = "audit";
      };

      action-cachix = uses (mkAction "cachix") {
        name = owner;
        authToken = "\${{ secrets.CACHIX_AUTH_TOKEN }}";
      };

      # Read-only cachix setup: configures substituters without exposing the
      # auth token. Use on workflows that build PR code so a malicious PR
      # cannot exfiltrate the token from the runner env.
      action-cachix-readonly = uses (mkAction "cachix") {
        name = owner;
      };

      action-checkout = uses (mkAction "checkout") { "persist-credentials" = false; };

      # Writable checkout for jobs that push via git (update-nixpkgs).
      # Leaves GITHUB_TOKEN in .git/config so `git push` works.
      action-checkout-writable = uses (mkAction "checkout") { };

      # Checkout variant that respects the workflow_call `ref` input so cicd can
      # be gated against an arbitrary branch (e.g. auto/update-nixpkgs). For
      # pull_request/push triggers `inputs.ref` is empty and checkout falls back
      # to the event's ref/sha.
      action-cicd-checkout = uses (mkAction "checkout") {
        "persist-credentials" = false;
        ref = "\${{ inputs.ref }}";
      };

      action-download-lix-archives = {
        id = "lix-archives";
      }
      // (uses (mkAction "download-artifact") {
        name = "lix-archives-\${{ runner.os }}-\${{ runner.arch }}";
      });

      action-local-use-archives = uses "./" {
        lix_archives_url = "file://\${{ steps.lix-archives.outputs.download-path }}";
        lix_version = "\${{ matrix.version }}";
      };

      # Job shape templates - orthogonal concerns, compose via lib.mkMerge.
      matrixOnRunners = {
        runsOn = "\${{ matrix.os }}";
        timeoutMinutes = 60;
        strategy = {
          failFast = true;
          matrix.os = runners;
        };
      };

      lixVersionsMatrix = {
        strategy.matrix.version = actionLib.getVersions config.legacyPackages.lixVersions;
      };

      singleRunner = {
        runsOn = manifest.singleRunner;
        timeoutMinutes = 60;
      };

      writePerms = {
        permissions.contents = "write";
      };

      linux-arm-runners = builtins.filter (lib.hasInfix "arm") runners;
    in
    {
      githubActions = {
        enable = true;

        workflows = {
          cicd = {
            name = "CI/CD";
            permissions.contents = "read";
            on = {
              pullRequest = { };
              push.branches = [ "main" ];
              workflowCall.inputs.ref = {
                type = "string";
                required = false;
                default = "";
              };
            };
            concurrency = {
              group = "\${{ github.workflow }}-\${{ github.ref }}";
              cancelInProgress = true;
            };
            jobs = {
              build = lib.mkMerge [
                matrixOnRunners
                {
                  steps = lib.flatten [
                    action-harden
                    action-cicd-checkout
                    (uses action-bootstrap {
                      lix_archives_url = bootstrap-url;
                      lix_version = bootstrap_lix_version;
                    })
                    action-cachix
                    (lib.forEach linux-arm-runners (
                      os:
                      (run "Fix Lix tests (${os})" { if_ = "matrix.os == '${os}'"; } /* sh */ ''
                        sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0
                        sudo sysctl -w kernel.apparmor_restrict_unprivileged_unconfined=0
                      '')
                    ))
                    (run "Build Lix archives" { id = "build-lix-archives"; } /* sh */ ''
                      ./scripts/nix-build-pkg.sh combined-archives
                      echo "result=$(readlink result)" >> "$GITHUB_OUTPUT"
                    '')
                    (uses (mkAction "upload-artifact") {
                      name = "lix-archives-\${{ runner.os }}-\${{ runner.arch }}";
                      path = "\${{ steps.build-lix-archives.outputs.result }}/";
                    })
                  ];
                }
              ];
              test = lib.mkMerge [
                matrixOnRunners
                lixVersionsMatrix
                {
                  needs = "build";
                  steps = [
                    action-harden
                    action-cicd-checkout
                    action-download-lix-archives
                    (overrideWith action-local-use-archives { lix_on_tmpfs = true; })
                    (run "Test nix" /* sh */ "nix-build -v --version")
                    (run "Add to store" /* sh */ ''
                      file="$RANDOM"
                      echo "$RANDOM" > "$file"
                      path="$(nix-store --add "./$file")"
                    '')
                  ];
                }
              ];
              test-cachix = lib.mkMerge [
                matrixOnRunners
                lixVersionsMatrix
                {
                  needs = "build";
                  steps = [
                    action-harden
                    action-cicd-checkout
                    action-download-lix-archives
                    action-local-use-archives
                    (overrideWith action-cachix-readonly { skipPush = true; })
                    (run "Verify nix config" /* sh */ ''
                      if ! egrep -q "^substituters = https://cache.nixos.org https://${owner}.cachix.org$" "$HOME/.config/nix/nix.conf"; then
                        echo "Invalid substituters config"
                        exit 1
                      fi
                    '')
                    (run "Push to Cachix"
                      {
                        if_ = "github.event_name == 'push' && github.repository_owner == '${owner}'";
                        env.CACHIX_AUTH_TOKEN = "\${{ secrets.CACHIX_AUTH_TOKEN }}";
                      }
                      /* sh */ ''
                        dd if=/dev/urandom of=random count=1
                        cachix push ${owner} "$(nix add-to-store random)"
                      ''
                    )
                  ];
                }
              ];
              release = lib.mkMerge [
                singleRunner
                writePerms
                {
                  needs = [
                    "build"
                    "test"
                    "test-cachix"
                  ];
                  if_ = "github.event_name == 'push' && github.ref == 'refs/heads/main'";
                  steps = [
                    action-harden
                    action-cicd-checkout
                  ]
                  ++ builtins.map downloadFor [
                    "Linux-X64"
                    "Linux-ARM64"
                    "macOS-X64"
                    "macOS-ARM64"
                  ]
                  ++ [
                    (uses "./" {
                      lix_archives_url = "file:///tmp/archives";
                      inherit lix_version;
                    })
                    action-cachix
                    (run "Build release script" /* sh */ "./scripts/nix-build-pkg.sh release-script")
                    (run "Release if needed" { env.GITHUB_TOKEN = "\${{ secrets.GITHUB_TOKEN }}"; } /* sh */ ''
                      ./result/bin/release /tmp/archives ./RELEASE
                    '')
                  ];
                }
              ];
            };
          };

          examples = {
            name = "Examples";
            permissions.contents = "read";
            on.push.branches = [ "main" ];
            concurrency = {
              group = "\${{ github.workflow }}-\${{ github.ref }}";
              cancelInProgress = true;
            };
            jobs = {
              version-check = lib.mkMerge [
                singleRunner
                {
                  steps = [
                    action-harden
                    (uses action-bootstrap { })
                    (run "nix version" /* sh */ "nix --version")
                  ];
                }
              ];
              flakes = mkExampleJob "./examples/flakes";
              npins = mkExampleJob "-f examples/npins";
              niv = mkExampleJob "-f examples/niv";
              pinned-fetchurl = mkExampleJob "-f examples/pinned-fetchurl";
            };
          };

          # Weekly nixpkgs bump
          # - pushes the update to auto/update-nixpkgs
          # - runs the cicd workflow
          # - fast-forwards main on success
          # WARN: ff to main will retrigger cicd workflow (with the release job)
          update-nixpkgs = {
            name = "Update nixpkgs";
            permissions.contents = "read";
            on = {
              schedule = [ { cron = "0 6 * * 1"; } ];
              workflowDispatch = { };
            };
            # Serialize update-nixpkgs runs across the whole repo. Don't cancel
            # mid-flight: aborting between the prepare/gate/merge stages could
            # leave auto/update-nixpkgs in an inconsistent state.
            concurrency = {
              group = "update-nixpkgs";
              cancelInProgress = false;
            };
            jobs = {
              prepare = lib.mkMerge [
                singleRunner
                writePerms
                {
                  outputs.changed = "\${{ steps.diff.outputs.changed }}";
                  steps = [
                    action-harden
                    action-checkout-writable
                    (uses action-bootstrap {
                      lix_archives_url = bootstrap-url;
                      lix_version = bootstrap_lix_version;
                    })
                    (run "Update nixpkgs" /* sh */ "nix-shell ./shell.nix --run 'npins update nixpkgs'")
                    (run "Check for changes" { id = "diff"; } /* sh */ ''
                      if git diff --quiet npins/sources.json; then
                        echo "changed=false" >> "$GITHUB_OUTPUT"
                      else
                        echo "changed=true" >> "$GITHUB_OUTPUT"
                      fi
                    '')
                  ]
                  ++ builtins.map (onSuccess "steps.diff") [
                    (run "Regenerate repo files" /* sh */ "nix-shell ./shell.nix --run write-repo")
                    (run "Bump release version" /* sh */ "nix-shell ./shell.nix --run bump-release-minor")
                    (run "Push to auto/update-nixpkgs" /* sh */ ''
                      git config user.name 'github-actions[bot]'
                      git config user.email '41898282+github-actions[bot]@users.noreply.github.com'
                      git checkout -B auto/update-nixpkgs
                      git add -A
                      git commit -m 'chore: bump nixpkgs'
                      git push --force origin auto/update-nixpkgs
                    '')
                  ];
                }
              ];
              gate = onSuccess "needs.prepare" ({
                needs = "prepare";
                uses = "./.github/workflows/cicd.yml";
                with_.ref = "auto/update-nixpkgs";
                secrets = "inherit";
              });
              merge = lib.mkMerge [
                singleRunner
                writePerms
                (onSuccess "needs.prepare" ({
                  needs = [
                    "prepare"
                    "gate"
                  ];
                  steps = [
                    action-harden
                    (overrideWith action-checkout-writable {
                      ref = "main";
                      "fetch-depth" = 0;
                    })
                    (run "Fast-forward main to auto/update-nixpkgs" /* sh */ ''
                      git config user.name 'github-actions[bot]'
                      git config user.email '41898282+github-actions[bot]@users.noreply.github.com'
                      git fetch origin auto/update-nixpkgs:auto/update-nixpkgs
                      git merge --ff-only auto/update-nixpkgs
                      git push origin main
                      git push origin --delete auto/update-nixpkgs
                    '')
                  ];
                }))
              ];
            };
          };

        };
      };
    };
}
