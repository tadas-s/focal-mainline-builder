#!/bin/bash
set -u

export LANG=C

update=yes
btype=binary
shell=no
custom=no
sign=no
flavour=none
exclude=none
rename=no
patch=no
series=focal
checkbugs=yes
buildmeta=no
debug=no
maintainer="Zaphod Beeblebrox <zaphod@betelgeuse-seven.western-spiral-arm.change.me.to.match.signing.key>"
buildargs="-aamd64 -d"

do_metapackage() {
  KVER=$1
  VERSION=$(echo ${KVER} | awk -F. '{printf "%d.%02d", $1,$2 }')
  FLAVOUR=$2
  SERIES=$3
  MAINT=$4
  ABINUM=$5
  BTYPE=$6
  BINS="${KVER}-${ABINUM}-${FLAVOUR}"
  DEPS="linux-headers-${BINS}, linux-image-unsigned-${BINS}, linux-modules-${BINS}"

  [ -d "../meta" ] || mkdir ../meta
  cd ../meta
  cat > metapackage.control <<-EOF
		Section: devel
		Priority: optional
		# Homepage: <enter URL here; no default>
		Standards-Version: 3.9.2

		Package: linux-${FLAVOUR}-${VERSION}
		Changelog: changelog
		Version: ${KVER}
		Maintainer: ${MAINT}
		Depends: ${DEPS}
		Architecture: amd64
		Description: Meta-package which will always depend on the latest packages in a mainline series.
		  This meta package will depend on the latest kernel in a series (eg 5.12.x) and install the
		  dependencies for that kernel.
		  .
		  Example: linux-generic-5.12 will depend on linux-image-unsigned-5.12.x-generic,
		  linux-modules-5.12.x-generic, linux-headers-5.12.x-generic and linux-headers-5.12.x
	EOF
	cat > changelog <<-EOF
		linux-${FLAVOUR}-${VERSION} (${KVER}) ${SERIES}; urgency=low

		  Metapackage for Linux ${VERSION}.x
		  Mainline build at commit: v${KVER}

		 -- ${MAINT}  $(date -R)
	EOF
  mkdir -p "source/usr/share/doc/linux-generic-${VERSION}"
  tar -C source -zcpf "linux-${FLAVOUR}-${VERSION}_${KVER}.orig.tar.gz" .
  equivs-build metapackage.control
  if [ "$BTYPE" == "source" ]
  then
    equivs-build --source metapackage.control
  fi
  mv linux-* ../
  cd -
}

__die() {
  local rc=$1; shift
  printf 1>&2 '%s\n' "ERROR: $*"; exit $rc
}

args=( "$@" );
for (( i=0; $i < $# ; i++ ))
do
  arg=${args[$i]}
  if [[ $arg = --*=* ]]
  then
    key=${arg#--}
    val=${key#*=}; key=${key%%=*}
    case "$key" in
      update|btype|shell|custom|sign|flavour|exclude|rename|patch|series|checkbugs|buildmeta|maintainer|debug)
        printf -v "$key" '%s' "$val" ;;
      *) __die 1 "Unknown flag $arg"
    esac
  else __die 1 "Bad arg $arg"
  fi
done

if [ "$sign" == "no" ]
then
  buildargs="$buildargs -uc -ui -us"
else
  buildargs="$buildargs -sa --sign-key=${sign}"
  cp -rp /root/keys /root/.gnupg
  chown -R root:root /root/.gnupg
  chmod 700 /root/.gnupg
fi

if [ ! -d /home/source/.git ]; then
  echo -e "********\n\nGetting source\n\n********"

  git clone \
    git://git.launchpad.net/~ubuntu-kernel-test/ubuntu/+source/linux/+git/mainline-crack \
    /home/source
else
  echo -e "********\n\nGot kernel sources already\n\n********"
fi

cd "$ksrc" || __die 1 "\$ksrc ${ksrc@Q} not found"

# tell git to trust /home/source
git config --global --add safe.directory /home/source

echo -e "********\n\nCleaning git source tree\n\n********"
git clean -fdx || __die 1 'git failed'
git reset --hard HEAD

if [ "$update" == "yes" ]
then
  echo -e "********\n\nUpdating git source tree\n\n********"
  git fetch --tags origin
fi

# checkout the kver
echo -e "********\n\nSwitching to cod/mainline/${kver} branch\n\n********"
git checkout "cod/mainline/${kver}" || __die 1 "Tag for 'cod/mainline/${kver} not found"

# Apply patch if requested
if [ "$patch" != "no" ]
then
  echo -e "********\n\nDownloading and patching cod/mainline/${kver} to $patch\n\n********"
  if [[ "$patch" =~ v[0-9]+\.[0-9]+\.[0-9]* ]]
  then
    # apply patch
    curl -s https://cdn.kernel.org/pub/linux/kernel/${patch/.*/}.x/patch-${patch:1}.xz > /home/patch.xz
    ret=$?
    [ $ret -ne 0 ] && __die $ret "Failed to download patch. Code: $ret"
    xzcat /home/patch.xz |  patch -p1 --forward -r -
    ret=$?
    [ $ret -gt 1 ] && __die $ret "Patching failed. Code $ret"
    kver="$patch"
  else
    __die 1 "Patch version should be a kernel version, Eg v5.11.19"
  fi
fi

# prep
echo -e "********\n\nRenaming source package and updating control files\n\n********"
debversion=$(date +%Y%m%d%H%M)
abinum=$(echo ${kver:1} | awk -F. '{printf "%02d%02d%02d", $1,$2,$3 }')
if [ "$rename" == "yes" ]
then
  sed -i -re "s/(^linux) \(([0-9]+\.[0-9]+\.[0-9]+)-([0-9]+)\.[0-9]+\) ([^;]*)(.*)/linux-${kver:1} (${kver:1}-${abinum}.${debversion}) ${series}\5/" debian.master/changelog
  sed -i -re 's/SRCPKGNAME/linux/g' debian.master/control.stub.in
  sed -i -re 's/SRCPKGNAME/linux/g' debian.master/control.d/flavour-control.stub
  sed -i -re "s/Source: linux/Source: linux-${kver:1}/" debian.master/control.stub.in
  sed -i -re "s/^(Package:\s+)(linux(-cloud[-tools]*|-tools)(-common|-host))$/\1\2-PKGVER/" debian.master/control.stub.in
  sed -i -re "s/^(Depends:\s+.*, )(linux(-cloud[-tools]*|-tools)(-common|-host))$/\1\2-PKGVER/" debian.master/control.stub.in
  sed -i -re "s/indep_hdrs_pkg_name=[^-]*/indep_hdrs_pkg_name=linux/" debian/rules.d/0-common-vars.mk
else
  sed -i -re "s/(^linux) \(([0-9]+\.[0-9]+\.[0-9]+)-([0-9]+)\.[0-9]+\) ([^;]*)(.*)/linux (${kver:1}-${abinum}.${debversion}) ${series}\5/" debian.master/changelog
fi
sed -i -re 's/dwarves \[/dwarves (>=1.21) \[/g' debian.master/control.stub.in

# undo GCC-11 update
sed -i -re 's/export gcc\?=.*/export gcc?=gcc-9/' debian/rules.d/0-common-vars.mk
#sed -i -re 's/CONFIG_CC_VERSION_TEXT=.*/CONFIG_CC_VERSION_TEXT="gcc (Ubuntu 9.4.0-1ubuntu1~20.04.1) 9.4.0"/' debian.master/config/amd64/config.common.amd64
#sed -i -re 's/CONFIG_GCC_VERSION=.*/CONFIG_GCC_VERSION=90400/' debian.master/config/config.common.ubuntu


if [ "$flavour" != "none" ]
then
  sed -i -re "s/(flavours\s+=).*/\1 $flavour/" debian.master/rules.d/amd64.mk
fi

if [ "$exclude" != "none" ]
then
  IFS=',' read -ra pkgs <<< "$exclude"
  for pkg in "${pkgs[@]}"
  do
    if [ "$pkg" == "cloud-tools" ]
    then
      sed -i -re "s/(do_tools_hyperv\s+=).*/\1 false/" debian.master/rules.d/amd64.mk
    elif [ "$pkg" == "tools" ]
    then
      # This doesn't work. We'll rename tools packages instead
      sed -i -re "s/^(do_tools_)((common|host)\s+=).*/\1\2 false/" debian.master/rules.d/amd64.mk
      echo "do_linux_tools  = false" >> debian.master/rules.d/amd64.mk
    elif [ "$pkg" == "udebs" ]
    then
      echo "disable_d_i     = true" >> debian.master/rules.d/amd64.mk
    fi
  done
fi

if [ "$debug" == yes ]
then
  echo -e "********\n\nEnabling Debug packages\n\n********\n"
  sed -i -re "s/skipdbg\s*=\s*true/skipdbg = false/g" debian/rules.d/0-common-vars.mk
fi

if [ "$checkbugs" == "yes" ]
then
  echo -e "********\n\nChecking for potential bugs\n\n********\n"
  if [ "$(cat debian/debian.env)" == "DEBIAN=debian.master" ]
  then
    echo " ---> debian.env bug == no"
  else
    echo " ---> debian.env bug == yes"
    echo "DEBIAN=debian.master" > debian/debian.env
  fi
  grep "CONFIG_KERNEL_LZ4=y" debian.master/config/amd64/config.common.amd64 > /dev/null
  if [ $? == 0 ]
  then
    # LZ4 Compression enabled. Check it's listed as a dependency
    if [ ! "$( egrep -i "lz4.*amd" debian.master/control.stub.in )" ]
    then
      echo " ---> LZ4 dependency bug == yes"
      sed -i -re "s/(^\s+lz4 )([^<]*)(.*)/\1[amd64 s390x] \3/" debian.master/control.stub.in
    else
      echo " ---> LZ4 dependency bug == no"
    fi
  else
    echo " ---> LZ4 dependency bug == not used"
  fi
fi

# Make lowlatency changes manually, the flavour was removed in 5.16.12 and newer
if [ "$flavour" = "lowlatency" -a ! -f debian.master/control.d/vars.lowlatency ]
then
  cat debian.master/control.d/vars.generic | sed -e 's/Generic/Lowlatency/g' > debian.master/control.d/vars.lowlatency
  touch debian.master/config/amd64/config.flavour.lowlatency
  ./scripts/config --file debian.master/config/amd64/config.common.amd64 --disable COMEDI_TESTS_EXAMPLE
  ./scripts/config --file debian.master/config/amd64/config.common.amd64 --disable COMEDI_TESTS_NI_ROUTES
  ./scripts/config --file debian.master/config/amd64/config.common.amd64 --set-val CONFIG_HZ 1000
  ./scripts/config --file debian.master/config/amd64/config.common.amd64 --enable HZ_1000
  ./scripts/config --file debian.master/config/amd64/config.common.amd64 --disable HZ_250
  ./scripts/config --file debian.master/config/amd64/config.common.amd64 --enable LATENCYTOP
  ./scripts/config --file debian.master/config/amd64/config.common.amd64 --enable PREEMPT
  ./scripts/config --file debian.master/config/amd64/config.common.amd64 --disable PREEMPT_VOLUNTARY
  ./scripts/config --file debian.master/config/amd64/config.common.amd64 --set-val TEST_DIV64 m
fi

echo -e "********\n\nApplying default configs\n\n********"
fakeroot debian/rules clean defaultconfigs
fakeroot debian/rules clean

if [ "$shell" == "yes" ]
then
  echo -e "********\n\nPre-build shell, exit or ctrl-d to continue build\n\n********"
  bash
fi

if [ "$custom" == "yes" ]
then
  echo -e "********\n\nYou have asked for a custom build.\nYou will be given the chance to makemenuconfig next.\n\n********"
  read -p 'Press return to continue...' foo
  fakeroot debian/rules editconfigs
fi

# Build
echo -e "********\n\nBuilding packages\nCommand: dpkg-buildpackage --build=$btype $buildargs\n\n********"
dpkg-buildpackage --build=$btype $buildargs

echo -e "********\n\nBuilding meta package\n\n********"
if [ "$buildmeta" == "yes" ]
then
  if [ "$flavour" == "none" ]
  then
    do_metapackage "${kver:1}" "generic" "$series" "$maintainer" "$abinum" "$btype"
    if [ -f debian.master/control.d/vars.lowlatency ]
    then
      do_metapackage "${kver:1}" "lowlatency" "$series" "$maintainer" "$abinum" "$btype"
    fi
  else
    do_metapackage "${kver:1}" "$flavour" "$series" "$maintainer" "$abinum" "$btype"
  fi
fi

echo -e "********\n\nMoving packages to debs folder\n\n********"
[ -d "$kdeb/$kver" ] || mkdir "$kdeb/$kver"
mv "$ksrc"/../*.* "$kdeb/$kver"

if [ "$shell" == "yes" ]
then
  echo -e "********\n\nPost-build shell, exit or ctrl-d to finish\n\n********"
  bash
fi

echo -e "********\n\nCleaning git source tree\n\n********"
git clean -fdx
git reset --hard HEAD

