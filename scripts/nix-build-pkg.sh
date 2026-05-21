#!/usr/bin/env bash

set -eu
set -o pipefail

pkg="${1:?usage: $(basename "$0") <package-name>}"

exec nix build -L --impure \
    --expr "(import ./.).packages.\${builtins.currentSystem}.\"$pkg\""
