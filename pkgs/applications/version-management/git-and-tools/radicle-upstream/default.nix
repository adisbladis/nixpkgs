{ stdenv, lib, fetchurl, mkYarnPackage, callPackage }:

let
  srcmeta = lib.importJSON ./src.json;
  packageJSON = lib.importJSON ./radicle-upstream-package.json;
  inherit (packageJSON) version;

  src = stdenv.mkDerivation {
    name = "radicle-sources-${packageJSON.version}";
    src = fetchurl { inherit (srcmeta) url sha256; };
    dontConfigure = true;
    dontBuild = true;
    installPhase = "mkdir $out && cp -a * $out";
  };

  ui = mkYarnPackage {
    inherit src;
    packageJSON = ./radicle-upstream-package.json;
    yarnLock = "${src}/yarn.lock";
    yarnNix = ./radicle-upstream-yarndeps.nix;
    distPhase = ''
      cd $out/libexec/radicle-upstream/deps/radicle-upstream
      yarn --offline run rollup:build
    '';
  };

  proxy = (callPackage ./Cargo.nix { }).workspaceMembers.api;

in proxy
