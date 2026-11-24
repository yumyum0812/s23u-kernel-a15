#!/bin/bash

# Author: yumyum0812
# Some code from AOSP

if [ "$BASH_SOURCE" != "$0" ]; then
    echo "source not supported" >&2
	return 1 2> /dev/null || exit 1
fi

if ! { CWD="$(dirname -- "$0" 2> /dev/null)" && \
     CWD="$(dirname -- "$CWD" 2> /dev/null)" && \
     CWD="$(realpath -- "$CWD")" && \
     [ -n "$CWD" ]; }; then
	echo "unable to retrieve cwd" >&2
	exit 1
fi

echo "CWD: $CWD"


LLVM_DIR="$(realpath -- "${LLVM_DIR:-/usr/lib/llvm-14}")"
if [ ! -d $LLVM_DIR ]; then
  echo "LLVM directory LLVM_DIR not found at $LLVM_DIR" >&2
  exit 1
fi

LLVM_BIN="$LLVM_DIR/bin"
if [ ! -d $LLVM_BIN ]; then
  echo "LLVM bin directory not found at $LLVM_DIR" >&2
  exit 1
fi

LLVM_TOOLS=(
  "clang"
  "ld.lld"
  "llvm-ar"
  "llvm-nm"
  "llvm-objcopy"
  "llvm-objdump"
  "llvm-readelf"
  "llvm-strip"
)

echo "LLVM_DIR: $LLVM_DIR"

for tool in "${LLVM_TOOLS[@]}"; do
  IS_MISSING=""
  if [ ! -x "$LLVM_BIN/$tool" ]; then
    echo "missing: $tool"
    IS_MISSING="1"
  fi
  if [ -n "$IS_MISSING" ]; then
    echo "some tools missing at: $LLVM_BIN"
    exit 1
  fi
done


export PATH="$LLVM_BIN:$PATH"
echo "PATH: $PATH"

export LTO="${LTO:-none}"
# export TRIM_NONLISTED_KMI=$([ -z "$TRIM_NONLISTED_KMI" ] && [ "$LTO" = "none" ] && echo 0)
# export KMI_SYMBOL_LIST_STRICT_MODE=$([ -z "$KMI_SYMBOL_LIST_STRICT_MODE" ] && [ "$LTO" = "none" ] && echo 0)

RECOMPILE_KERNEL=${RECOMPILE_KERNEL:-1}
if [ "$RECOMPILE_KERNEL" = "1" ]; then
  SKIP_MRPROPER=1
fi

export LLVM=1
export LLVM_IAS=1
TOOL_ARGS="LLVM=1 LLVM_IAS=1"
MAKE_ARGS="-j$(grep -c "^processor" /proc/cpuinfo) ${MAKE_ARGS:-}"
echo "MAKE_ARGS: $MAKE_ARGS"

OUT_DIR="${OUT_DIR:-$CWD/out}"
mkdir -p "$OUT_DIR"
OUT_DIR="$(realpath -- "$OUT_DIR")"

echo "OUT_DIR: $OUT_DIR"

KERNEL_DIR="."
ROOT_DIR="$CWD"

echo "running config..."
cd "$CWD" || exit 1
pushd "$CWD" || exit 1
set -a
source "$CWD/$BUILD_CONFIG" || exit 1
set +a
popd > "/dev/null" || exit 1

echo "making mrproper..."
if [ "$SKIP_MRPROPER" = "1" ]; then
  echo "skipped"
else
  (
    cd "${CWD}" || exit 1
    make O="${OUT_DIR}" $TOOL_ARGS $MAKE_ARGS mrproper
  ) || exit 1
fi

echo "making defconfig..."
(
  if [ -z "$DEFCONFIG" ]; then
    echo "defconfig empty" >&2
    exit 1
  fi
  cd "${CWD}" || exit 1
  make O="${OUT_DIR}" $TOOL_ARGS $MAKE_ARGS "$DEFCONFIG" $ADDITIONAL_CONFIGS
) || exit 1

check_defconfig() {
  echo "checking defconfig..."
  make O="${OUT_DIR}" $TOOL_ARGS savedefconfig
}

if [ -n "${POST_DEFCONFIG_CMDS}" ]; then
  echo "running post defconfig cmds..."
  eval ${POST_DEFCONFIG_CMDS} || exit 1
fi

if [ "$LTO" = "none" -o "$LTO" = "thin" -o "$LTO" = "full" ]; then
  echo "modifying LTO mode to '$LTO'"

  if [ "$LTO" = "none" ]; then
     "$CWD/scripts/config" --file "$OUT_DIR/.config" \
      -d LTO_CLANG \
      -e LTO_NONE \
      -d LTO_CLANG_THIN \
      -d LTO_CLANG_FULL \
      -d THINLTO \
      --set-val FRAME_WARN 0 || exit 1
  elif [ "$LTO" = "thin" ]; then
    "$CWD/scripts/config" --file "$OUT_DIR/.config" \
      -e LTO_CLANG \
      -d LTO_NONE \
      -e LTO_CLANG_THIN \
      -d LTO_CLANG_FULL \
      -e THINLTO || exit 1
  elif [ "$LTO" = "full" ]; then
    "$CWD/scripts/config" --file "$OUT_DIR/.config" \
      -e LTO_CLANG \
      -d LTO_NONE \
      -d LTO_CLANG_THIN \
      -e LTO_CLANG_FULL \
      -d THINLTO || exit 1
  fi
  (
    echo "olddefconfig..."
    cd "$OUT_DIR" &&
    make O="${OUT_DIR}" $TOOL_ARGS $MAKE_ARGS olddefconfig
  ) || exit 1
elif [ -n "$LTO" ]; then
  echo "LTO must be one of 'none', 'thin' or 'full'." >&2
  exit 1
fi

if [ -n "${KMI_SYMBOL_LIST}" ]; then
  "$CWD/build/process_symbols" --out-dir="$OUT_DIR" --out-file=abi_symbollist \
    --report-file=abi_symbollist.report --in-dir="$CWD" \
    "${KMI_SYMBOL_LIST}" ${ADDITIONAL_KMI_SYMBOL_LISTS} || exit 1
  pushd "$ROOT_DIR/$KERNEL_DIR" || exit 1

  if [ "${TRIM_NONLISTED_KMI}" = "1" ]; then
    cat "${OUT_DIR}/abi_symbollist" | \
      "$CWD/build/flatten_symbol_list" > \
      "${OUT_DIR}/abi_symbollist.raw"

    "$CWD/scripts/config" --file ${OUT_DIR}/.config \
      -d UNUSED_SYMBOLS -e TRIM_UNUSED_KSYMS \
      --set-str UNUSED_KSYMS_WHITELIST "${OUT_DIR}/abi_symbollist.raw"
    (
      cd ${OUT_DIR} &&
      make O="${OUT_DIR}" $TOOL_ARGS $MAKE_ARGS olddefconfig
    ) || exit 1
    
    grep CONFIG_UNUSED_KSYMS_WHITELIST "${OUT_DIR}/.config" > /dev/null || {
      echo "ERROR: Failed to apply TRIM_NONLISTED_KMI kernel configuration" >&2
      echo "Does your kernel support CONFIG_UNUSED_KSYMS_WHITELIST?" >&2
      exit 1
    }
  elif [ "${KMI_SYMBOL_LIST_STRICT_MODE}" = "1" ]; then
    echo "ERROR: KMI_SYMBOL_LIST_STRICT_MODE requires TRIM_NONLISTED_KMI=1" >&2
    exit 1
  fi

  popd # $ROOT_DIR/$KERNEL_DIR
elif [ "${TRIM_NONLISTED_KMI}" = "1" ]; then
  echo "ERROR: TRIM_NONLISTED_KMI requires a KMI_SYMBOL_LIST" >&2
  exit 1
elif [ "${KMI_SYMBOL_LIST_STRICT_MODE}" = "1" ]; then
  echo "ERROR: KMI_SYMBOL_LIST_STRICT_MODE requires a KMI_SYMBOL_LIST" >&2
  exit 1
fi

echo "building kernel..."
(
  cd "$OUT_DIR" &&
  make O="${OUT_DIR}" $TOOL_ARGS $MAKE_ARGS $MAKE_GOALS
) || exit 1

if [ "${KMI_SYMBOL_LIST_STRICT_MODE}" = "1" ]; then
  echo "comparing the KMI and the symbol lists:"

  gki_modules_list="$CWD/android/gki_system_dlkm_modules"
  if ! (
    export KMI_STRICT_MODE_OBJECTS="vmlinux $(sed 's/\.ko$//' ${gki_modules_list} | tr '\n' ' ')"
    echo "KMI_STRICT_MODE_OBJECTS: $KMI_STRICT_MODE_OBJECTS"
    "$CWD/build/compare_to_symbol_list" "${OUT_DIR}/Module.symvers" "${OUT_DIR}/abi_symbollist.raw" &&
    echo "compare symbol list ok"
  ); then
    if [ "$LTO" -ne "none" ]; then
      echo "symbol list not match, aborting"
      exit 1
    else
      echo "warn: symbol list not match, continuing because LTO=none"
    fi
  fi
fi
