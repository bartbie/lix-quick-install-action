default:
    @just --list

bump-nixpkgs:
    npins update nixpkgs

_run cmd *args:
    nix-shell ./shell.nix --run "{{ cmd }} {{ args }}"

fmt:
    @just _run treefmt

write-repo:
    @just _run write-repo

bump-release-minor:
    @just _run bump-release-minor

bump-pins:
    @just _run bump-pins

add-new-lix version-set:
    @just _run add-new-lix {{ version-set }}

update version-set='':
    @just _run update {{ version-set }}
