{ stdenv, fetchurl, getopt, utillinux, gperf }:

stdenv.mkDerivation rec {
  pname = "libseccomp";
  version = "2.5.1";

  src = fetchurl {
    url = "https://github.com/seccomp/libseccomp/releases/download/v${version}/libseccomp-${version}.tar.gz";
    sha256 = "0m8dlg1v7kflcxvajs4p76p275qwsm2abbf5mfapkakp7hw7wc7f";
  };

  outputs = [ "out" "lib" "dev" "man" ];

  nativeBuildInputs = [ gperf ];
  buildInputs = [ getopt ];

  patchPhase = ''
    patchShebangs .
  '';

  checkInputs = [ utillinux ];
  doCheck = false; # dependency cycle

  # Hack to ensure that patchelf --shrink-rpath get rids of a $TMPDIR reference.
  preFixup = "rm -rfv src";

  meta = with stdenv.lib; {
    description = "High level library for the Linux Kernel seccomp filter";
    homepage = "https://github.com/seccomp/libseccomp";
    license = licenses.lgpl21;
    platforms = platforms.linux;
    badPlatforms = [
      "alpha-linux"
      "riscv32-linux"
      "sparc-linux"
      "sparc64-linux"
    ];
    maintainers = with maintainers; [ thoughtpolice ];
  };
}
