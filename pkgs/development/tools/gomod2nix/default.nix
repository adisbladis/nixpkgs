{ lib, fetchFromGitHub }:
let
  srcMeta = lib.importJSON ./src.json;
in
(import ./generic.nix {
  version = lib.removePrefix "v" srcMeta.rev;
  src = fetchFromGitHub srcMeta;
  modules = ./gomod2nix.toml;
})
