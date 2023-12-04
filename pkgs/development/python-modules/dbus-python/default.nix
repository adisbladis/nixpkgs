{ lib
, fetchPypi
, buildPythonPackage
, isPyPy

# build-system
, meson
, meson-python
, ninja
, patchelf
, pkg-config
, setuptools

# native dependencies
, dbus
, dbus-glib

# tests
, pygobject3
}:

buildPythonPackage rec {
  pname = "dbus-python";
  version = "1.3.2";
  pyproject = true;

  disabled = isPyPy;

  outputs = [
    "out"
    "dev"
  ];

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-rWeBkwhhi1BpU3viN/jmjKHH/Mle5KEh/mhFsUGCSPg=";
  };

  postPatch = ''
    sed -i '/patchelf/d' pyproject.toml
    rm configure.ac configure
  '';

  nativeBuildInputs = [
    meson
    meson-python
    ninja
    patchelf
    pkg-config
    setuptools
  ];

  buildInputs = [
    dbus
    dbus-glib
  ];

  nativeCheckInputs = [
    dbus.out
    pygobject3
  ];

  pypaBuildFlags = [
    # Don't discard meson build directory.
    "-Cbuild-dir=_meson-build"
  ];

  doCheck = true; # ERROR: No such build data file as '/build/dbus-python-1.3.2/meson-private/build.dat'.

  checkPhase = ''
    runHook preCheck
    dbus-run-session \
      --config-file=${dbus}/share/dbus-1/session.conf \
        meson test --no-rebuild -C _meson-build \
          --print-errorlogs
    runHook postCheck
  '';

  meta = with lib; {
    description = "Python DBus bindings";
    homepage = "https://gitlab.freedesktop.org/dbus/dbus-python";
    license = licenses.mit;
    platforms = dbus.meta.platforms;
    maintainers = with maintainers; [ ];
  };
}
