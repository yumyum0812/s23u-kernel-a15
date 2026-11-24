CWD="$(dirname -- "$0" 2> /dev/null)"
if [ $? -ne 0 -o -z "$CWD" ]; then
	echo "unable to retrieve cwd" >&2
	return 1 2> /dev/null || exit 1
fi

export ANDROID_BUILD_TOP="$CWD"
export TARGET_BUILD_VARIANT="user"
export TARGET_PRODUCT="gki"
export TARGET_BOARD_PLATFORM="gki"
export OUT_DIR="${ANDROID_BUILD_TOP}/out/gki-aarch64"
export BUILD_CONFIG="build.config.gki.aarch64"

BUILD_SCRIPT="$CWD/build/build.sh"
if [ ! -x "$BUILD_SCRIPT" ]; then
  echo "build script not found or not executable at $BUILD_SCRIPT" >&2
  exit 1
fi

exec "$BUILD_SCRIPT" "$@"