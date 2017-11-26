{ stdenv
, lib
, buildPythonPackage
, fetchPypi
, isPyPy
, pillow
, pdfrw
}:

buildPythonPackage rec {
  pname = "img2pdf";
  version = "0.2.4";
  name = "${pname}-${version}";

  src = fetchPypi {
    inherit pname version;
    sha256 = "1bn9zzsmg4k41wmx1ldmj8a4yfj807p8r0a757lm9yrv7bx702ql";
  };

  propagatedBuildInputs = [
    pillow
    pdfrw
  ];

  meta = with stdenv.lib; {
    homepage = https://gitlab.mister-muffin.de/josch/img2pdf;
    description = "Losslessly convert raster images to PDF. ";
    license = lib.licenses.lgpl3;
    maintainers = with lib.maintainers; [ hyper_ch ];
  };
}
