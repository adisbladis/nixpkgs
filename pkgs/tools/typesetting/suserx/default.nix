{ lib
, fetchFromGitHub
, stdenv
, ruby
, bundlerEnv
# , libxml2
}:

let
  env = bundlerEnv {
    name = "docbookrx-env";
    gemdir = ./.;

    inherit ruby;

    # buildInputs = [
    #   libxml2
    # ];

    gemfile = ./Gemfile;
    lockfile = ./Gemfile.lock;
    gemset = ./gemset.nix;
  };

in stdenv.mkDerivation {

  pname = "suserx";
  version = "unstable-2019-03-01";

  buildInputs = [ env.wrappedRuby ];

  src = fetchFromGitHub {
    owner = "openSUSE";
    repo = "docbookrx";
    rev = "b994cb88c655e6b832be0598fcc3663307c99c7a";
    sha256 = "1y8sqq6ywix6p3bixp7nfiq20dq2fys9az8pd2mj846q5ps2032f";
  };

  # TODO: I don't know ruby packaging but this does the trick for now
  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    # Dont collide with docbookrx, we use it as a fallback
    cp -a bin/docbookrx $out/bin/suserx
    cp -a lib $out

    runHook postInstall
  '';

  meta = with lib; {
    description = "(An early version of) a DocBook to AsciiDoc converter written in Ruby.";
    homepage = https://asciidoctor.org/;
    license = licenses.mit;
    maintainers = with maintainers; [ ];
    platforms = platforms.unix;
  };

}
