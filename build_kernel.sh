CWD="$(dirname -- "$0" 2> /dev/null)"
if [ $? -ne 0 -o -z "$CWD" ]; then
	echo "unable to retrieve cwd" >&2
	return 1 2> /dev/null || exit 1
fi

BUILD_TARGET="dm3q_kor_singlex"
export MODEL="$(echo ${BUILD_TARGET} | cut -d'_' -f1)"
export PROJECT_NAME=${MODEL}
export REGION="$(echo ${BUILD_TARGET} | cut -d'_' -f2)"
export CARRIER="$(echo ${BUILD_TARGET} | cut -d'_' -f3)"
export TARGET_BUILD_VARIANT="user"

CHIPSET_NAME="kalama"
export ANDROID_BUILD_TOP="$CWD"
export TARGET_PRODUCT="gki"
export TARGET_BOARD_PLATFORM="gki"

export ANDROID_PRODUCT_OUT="${ANDROID_BUILD_TOP}/out/target/product/${MODEL}"
export OUT_DIR="${ANDROID_BUILD_TOP}/out/msm-${CHIPSET_NAME}-${CHIPSET_NAME}-${TARGET_PRODUCT}"
export BUILD_CONFIG="build.config.gki.aarch64"

BUILD_SCRIPT="$CWD/build/build.sh"
if [ ! -x "$BUILD_SCRIPT" ]; then
  echo "build script not found or not executable at $BUILD_SCRIPT" >&2
  exit 1
fi

exec "$BUILD_SCRIPT" "$@"