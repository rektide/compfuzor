export DPKG_DEB_COMPRESSOR_TYPE=xz
export DPKG_DEB_COMPRESSOR_LEVEL=9
export DPKG_DEB_THREADS_MAX=12

export SOURCE_DATE_EPOCH="$(git -C /usr/local/src/linux show -s --format=%ct HEAD)"
export KBUILD_BUILD_TIMESTAMP="$(git -C /usr/local/src/linux show -s --format=%cI HEAD)"
export KBUILD_BUILD_USER=rektide
export KBUILD_BUILD_HOST=workhorse
export KDEB_CHANGELOG_DIST=unstable

make \
  -j12 \
  LLVM=1 \
  LOCALVERSION=-debplus.1 \
  KDEB_SOURCENAME=linux-debplus \
  KDEB_PKGVERSION=7.1.0-1 \
  KDEB_CHANGELOG_DIST=unstable \
  bindeb-pkg
