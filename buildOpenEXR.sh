#!/bin/sh

#Options:
# CLEAN_REPO=1 (optional): If the repo has modifications compared to the original branch, stash them before building
# THREAD_MODEL=(win32,pthread): pick pthread or win32 threads for MingW
# NO_CLEAN_BUILD=1 (optional): If the build directory is present, do not clean it. It will be cleaned if CLEAN_REPO is set
# USE_XCODE=1 (optional): (OSX Only) Builds using xcodebuild. The binaries will be symlinked to the Xcode build directory
# and the actual headers will not be installed
# MKJOBS (optional): Number of threads for make
# GIT_BRANCH (optional): select git branch or tag
# CONFIG=(debug,release) (required)
# DST_DIR=... (required): Where to deploy the library
#
#
#Usage: MKJOBS=8 GIT_BRANCH=tags/v2.2.0 CONFIG=debug DST_DIR=. ./buildOpenEXR
#With Xcode: NO_CLEAN=1 USE_XCODE=1 GIT_BRANCH=master CONFIG=debug DST_DIR=. sh buildOpenEXR.sh

set -x 
CWD=$(pwd)

DEFAULT_GIT_BRANCH=tags/v2.2.0

if [ -z "$DST_DIR" ]; then
    ###### To be customized
    DST_DIR=/Users/alexandre/development/CustomBuilds
    ######
fi

if [ ! -d "$DST_DIR" ]; then
    echo "$DST_DIR: Specified DST_DIR does not exist."
    exit 1
fi

PATCH_DIR=$CWD/patches

OPENEXR_GIT=https://github.com/MrKepzie/openexr


if [ "$CONFIG" = "debug" ]; then
    BUILDTYPE=Debug
	CMAKE_CONFIG="-DCMAKE_BUILD_TYPE=Debug -DCMAKE_INSTALL_CONFIG_NAME=Debug"
	echo "Debug build"
elif [ "$CONFIG" = "release" ]; then
    BUILDTYPE=Release
    CMAKE_CONFIG="-DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_CONFIG_NAME=Release"
else
    echo "You must specify build type (debug or release)"
    exit 1
fi

if [ -z "$GIT_BRANCH" ]; then
    GIT_BRANCH=$DEFAULT_GIT_BRANCH
fi

OS=$(uname -s)

if [ "$OS" == "MINGW64_NT-6.1" ]; then
	IS_MINGW=1
	if [ "$THREAD_MODEL" != "win32" ] && [ "$THREAD_MODEL" != "pthread" ]; then
		echo "THREAD_MODEL must be set to either win32 or pthread."
		exit 1
	fi
else
	THREAD_MODEL=""
fi


if [ "$USE_XCODE" = "1" ]; then
    GENERATOR_TYPE="-G Xcode"
fi

if [ ! -d "openexr-git" ]; then
	MUST_PATCH=1
    echo "Using git repository $OPENEXR_GIT"
    git clone $OPENEXR_GIT openexr-git
	cd openexr-git || exit 1
	git checkout $GIT_BRANCH
	cd ..
fi

cd openexr-git || exit 1

if [ "$CLEAN_REPO" = "1" ] || [ "$MUST_PATCH" = "1" ]; then
	MUST_PATCH=1
	git stash
	NO_CLEAN_BUILD=0
fi

if [ "$NO_CLEAN_BUILD" != "1" ]; then
	rm -rf $DST_DIR/include/OpenEXR
	rm $DST_DIR/bin/libIex*.dll $DST_DIR/bin/libHalf-2*.dll $DST_DIR/bin/libIlm*.dll $DST_DIR/lib/pkgconfig/OpenEXR.pc
	
	rm -rf build_ilmbase
	rm -rf build_openexr
fi
	if [ "$MUST_PATCH" = "1" ]; then 
		ILM_BASE_PATCHES=$(find $PATCH_DIR/ilmbase -type f)
		OPENEXR_BASE_PATCHES=$(find $PATCH_DIR/openexr -type f)
		for p in $ILM_BASE_PATCHES; do
			if [[ "$p" = *-mingw-* ]] && [ "$IS_MINGW" != "1" ]; then
				continue
			fi
			if [[ "$p" = *-mingw-use_pthreads* ]] && [ "$THREAD_MODEL" != "pthread" ]; then
				continue
			fi
			if [[ "$p" = *-mingw-use_windows_threads* ]] && [ "$THREAD_MODEL" != "win32" ]; then
				continue
			fi
			echo "Patch: $p"
			patch -p1 -i $p || exit 1
		done
		for p in $OPENEXR_BASE_PATCHES; do
			if [[ "$p" = *-mingw-* ]] && [ "$IS_MINGW" != "1" ]; then
				continue
			fi
			if [[ "$p" = *-mingw-use_pthreads* ]] && [ "$THREAD_MODEL" != "pthread" ]; then
				continue
			fi
			echo "Patch: $p"
			patch -p1 -i $p || exit 1
		done
	fi 
	
    mkdir build_ilmbase
	cd build_ilmbase
	cmake -G"MSYS Makefiles" -DCMAKE_INSTALL_PREFIX=$DST_DIR -DBUILD_SHARED_LIBS=ON -DNAMESPACE_VERSIONING=ON ${CMAKE_CONFIG} ../IlmBase || exit 1
	make -j${MKJOBS} || exit 1
    make install || exit 1
	cd ..
	mkdir build_openexr
	cd build_openexr
	
	cmake -DCMAKE_CXX_FLAGS="-I${DST_DIR}/include/OpenEXR" -DCMAKE_EXE_LINKER_FLAGS="-L${DST_DIR}/bin" -G"MSYS Makefiles" -DCMAKE_INSTALL_PREFIX=$DST_DIR -DBUILD_SHARED_LIBS=ON -DNAMESPACE_VERSIONING=ON -DUSE_ZLIB_WINAPI=OFF ${CMAKE_CONFIG} ../OpenEXR || exit 1

    make -j${MKJOBS} || exit 1
    make install || exit 1
	
#if [ "$USE_XCODE" = "1" ]; then
#    if [ ! -d "OpenEXR.xcodeproj" ]; then
#        cd ..
#        rm -rf build
#        exit 1
#    fi
#    INSTALL_DIR=$DST_DIR xcodebuild -project OpenEXR.xcodeproj -configuration=$BUILDTYPE || exit 1
#(cd $DST_DIR/lib;rm libOpenImageIO*; ln -s $CWD/oiio-src/build/src/libOpenImageIO/Debug/libOpenImageIO* .;rm -rf $DST_DIR/include/OpenImageIO;cp -r $CWD/oiio-src/src/include/OpenImageIO $DST_DIR/include; cp $CWD/oiio-src/build/include/OpenImageIO/* $DST_DIR/include/OpenImageIO/;)
#else
#   make -j${MKJOBS} || exit 1
#    make DESTDIR=$DST_DIR BUILD_TYPE=$BUILDTYPE install || exit 1
#fi

cd $CWD
