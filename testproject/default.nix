{ pkgs ? import <nixpkgs> {} }:

let

  python = let
    packageOverrides = self: super: {
      typeddep = super.callPackage ./typeddep {};
    };
  in pkgs.python3.override {inherit packageOverrides; self = python;};

  pythonEnv = python.withPackages(ps: [
    ps.typeddep
    ps.mypy
  ]);

  pythonScript = pkgs.writeText "myscript.py" ''
    from typeddep import util
    s: str = util.echo("hello")
    print(s)
  '';

in pkgs.runCommandNoCC "site-prefix-mypy-test" {} ''
  ${pythonEnv}/bin/mypy ${pythonScript}
  touch $out
''
