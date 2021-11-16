#!/bin/bash

BASE_DIRECTORY=$PWD
BUILD_DIRECTORY=$BASE_DIRECTORY/qt5build
IMX8MM_ADDRESS=10.42.0.100

#if [ ! -d "$BASE_DIRECTORY/tools" ]; then
#    git clone https://github.com/raspberrypi/tools
#fi

#if [[ :$PATH: == *:"$BASE_DIRECTORY/tools/arm-bcm2708/gcc-linaro-arm-linux-gnueabihf-raspbian-x64/bin":* ]] ; then
#    echo "Found toolchain in PATH. "
#else
#	echo "Toolchain not found. Export toolchain"
#    export PATH=$PATH:$BASE_DIRECTORY/tools/arm-bcm2708/gcc-linaro-arm-linux-gnueabihf-raspbian-x64/bin
#fi

if [ ! -f "$BASE_DIRECTORY/qt-everywhere-src-5.15.2.tar.xz" ]; then
	echo "Download qt sources"
    wget https://download.qt.io/official_releases/qt/5.15/5.15.2/single/qt-everywhere-src-5.15.2.tar.xz
fi

if [ ! -d "$BASE_DIRECTORY/qt-everywhere-src-5.15.2" ]; then
	echo "Extract qt sources"
    tar -xf qt-everywhere-src-5.15.2.tar.xz
fi

if [ ! -d "$BASE_DIRECTORY/qt-everywhere-src-5.15.2/qtbase/mkspecs/devices/linux-imx8-g++/qmake.conf" ]; then
	echo "Generate qmake for imx8 mini"
	mv $BASE_DIRECTORY/qt-everywhere-src-5.15.2/qtbase/mkspecs/devices/linux-imx8-g++/qmake.conf $BASE_DIRECTORY/qt-everywhere-src-5.15.2/qtbase/mkspecs/devices/linux-imx8-g++/qmake.conf.bak

cat > "$BASE_DIRECTORY/qt-everywhere-src-5.15.2/qtbase/mkspecs/devices/linux-imx8-g++/qmake.conf" << EOF

include(../common/linux_device_pre.conf)

QMAKE_INCDIR_POST += \\
    \$\$[QT_SYSROOT]/usr/include \\
    \$\$[QT_SYSROOT]/usr/include/aarch64-linux-gnu

QMAKE_LIBDIR_POST += \\
    \$\$[QT_SYSROOT]/usr/lib \\
    \$\$[QT_SYSROOT]/lib/aarch64-linux-gnu \\
    \$\$[QT_SYSROOT]/usr/lib/aarch64-linux-gnu

QMAKE_RPATHLINKDIR_POST += \\
    \$\$[QT_SYSROOT]/usr/lib \\
    \$\$[QT_SYSROOT]/usr/lib/aarch64-linux-gnu \\
    \$\$[QT_SYSROOT]/usr/lib/aarch64-linux-gnu/vivante \\
    \$\$[QT_SYSROOT]/lib/aarch64-linux-gnu

QMAKE_LIBS_EGL         += -lEGL
QMAKE_LIBS_OPENGL_ES2  += -lGLESv2 -lEGL -lGAL
QMAKE_LIBS_OPENVG      += -lOpenVG -lEGL -lGAL

IMX8_CFLAGS             = -march=armv8-a -mtune=cortex-a72.cortex-a53 -DLINUX=1 -DEGL_API_FB=1
QMAKE_CFLAGS           += \$\$IMX8_CFLAGS
QMAKE_CXXFLAGS         += \$\$IMX8_CFLAGS

DISTRO_OPTS += aarch64

# Preferred eglfs backend
EGLFS_DEVICE_INTEGRATION = eglfs_viv

include(../common/linux_arm_device_post.conf)

load(qt_config)
EOF
fi

if [ ! -f "$BASE_DIRECTORY/.sysroot" ]; then
	echo "Download sysroot"
	if [ -d "$BASE_DIRECTORY/sysroot" ]; then
		rm -Rf $BASE_DIRECTORY/sysroot
	fi

    mkdir $BASE_DIRECTORY/sysroot $BASE_DIRECTORY/sysroot/usr $BASE_DIRECTORY/sysroot/opt $BASE_DIRECTORY/sysroot/usr/local
    rsync -avz root@$IMX8MM_ADDRESS:/lib $BASE_DIRECTORY/sysroot
    rsync -avz root@$IMX8MM_ADDRESS:/usr/include $BASE_DIRECTORY/sysroot/usr
    rsync -avz root@$IMX8MM_ADDRESS:/usr/lib $BASE_DIRECTORY/sysroot/usr
    rsync -avz root@$IMX8MM_ADDRESS:/usr/local/lib $BASE_DIRECTORY/sysroot/usr/local
    rsync -avz root@$IMX8MM_ADDRESS:/usr/local/include $BASE_DIRECTORY/sysroot/usr/local

    if [ ! -f "$BASE_DIRECTORY/sysroot-relativelinks.py" ]; then
        wget https://raw.githubusercontent.com/riscv/riscv-poky/master/scripts/sysroot-relativelinks.py
        chmod +x $BASE_DIRECTORY/sysroot-relativelinks.py
    fi

    $BASE_DIRECTORY/sysroot-relativelinks.py $BASE_DIRECTORY/sysroot 2>&1 | tee $BASE_DIRECTORY/sysroot-relativelinks.log
    touch $BASE_DIRECTORY/.sysroot
fi

set -o pipefail
set -o errtrace
function error() {
    JOB="$0"
    LASTLINE="$1"
    LASTERR="$2"
    echo "ERROR in ${JOB} : line ${LASTLINE} with exit code ${LASTERR}"
    exit 1
}
trap 'error ${LINENO} ${?}' ERR

if [ ! -d "$BUILD_DIRECTORY" ]; then
    mkdir $BUILD_DIRECTORY
fi

cd $BUILD_DIRECTORY

if [ ! -f "$BASE_DIRECTORY/.configure" ]; then
    $BASE_DIRECTORY/qt-everywhere-src-5.15.2/configure -opengl es2 -device linux-imx8-g++ -device-option CROSS_COMPILE=aarch64-linux-gnu- -sysroot $BASE_DIRECTORY/sysroot -prefix /usr/local/qt5 -opensource -confirm-license -skip qtscript -nomake tests -nomake examples -make libs -no-gbm -pkg-config -no-use-gold-linker -v 2>&1 | tee $BASE_DIRECTORY/configure.log
    touch $BASE_DIRECTORY/.configure
fi

if [ ! -f "$BASE_DIRECTORY/.make" ]; then
    make 2>&1 | tee $BASE_DIRECTORY/make.log
    touch $BASE_DIRECTORY/.make
fi

if [ ! -f "$BASE_DIRECTORY/.make_install" ]; then
    make install 2>&1 | tee $BASE_DIRECTORY/make_install.log
    touch $BASE_DIRECTORY/.make_install
fi

cd $BASE_DIRECTORY

if [ ! -f "$BASE_DIRECTORY/.upload" ]; then
    rsync -avz $BASE_DIRECTORY/sysroot/usr/local/qt5 root@$IMX8MM_ADDRESS:/usr/local
    touch $BASE_DIRECTORY/.upload
fi

exit 0
