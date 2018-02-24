{ stdenv
, fetchFromGitHub
, cmake
, pkgconfig
, gtk3
, granite
, libgee
, libxml2
, gtksourceview
, libgda
, vala
}:

let
  sqlGda = libgda.override {
    mysqlSupport = true;
    postgresSupport = true;
  };

in stdenv.mkDerivation rec {
  name = "sequeler-${version}";
  version = "0.5.3";

  src = fetchFromGitHub {
    owner = "Alecaddd";
    repo = "sequeler";
    rev = "v${version}";
    sha256 = "0m5zwl9jfdl1dzd1ymlwx7rx5cr9fdx06sbnidaajh33z02zaph0";
  };

  nativeBuildInputs = [ cmake pkgconfig vala ];

  buildInputs = [ gtk3 granite libgee libxml2 sqlGda gtksourceview ];

  meta = with stdenv.lib; {
    description = "Friendly SQL Client";
    longDescription = ''
      Sequeler is a native Linux SQL client built in Vala and Gtk. It allows you
      to connect to your local and remote databases, write SQL in a handy text
      editor with language recognition, and visualize SELECT results in a
      Gtk.Grid Widget.
    '';
    homepage = https://github.com/Alecaddd/sequeler;
    license = licenses.gpl3;
    maintainers = [ maintainers.etu ];
  };
}
