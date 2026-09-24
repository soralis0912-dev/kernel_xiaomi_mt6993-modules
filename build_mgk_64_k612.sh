#!/bin/bash
# Build the MT6993 kernel out of this MGKI workspace.
#
# Mirrors kernel_device_modules-6.12/build.sh, with the bits MTK's flow expects
# from the environment filled in, plus the workarounds that come from mixing
# Motorola's bazel_mgk_rules with Xiaomi's build/kernel (see below).
#
#   ./build_mgk_64_k612.sh                # kernel image + dtbs (default)
#   ./build_mgk_64_k612.sh <bazel target> # anything else
#   DEVICE=warhol ./build_mgk_64_k612.sh  # which kernel/configs/<device>.config
#   MODE=user ./build_mgk_64_k612.sh      # user instead of userdebug
#   NOBUILD=1 ./build_mgk_64_k612.sh      # analysis only, no compilation
#   JOBS=64 ./build_mgk_64_k612.sh        # cap the job count
#   SANDBOX=0 ./build_mgk_64_k612.sh      # --config=local, no sandbox
#
set -e
cd "$(dirname "$0")"

PROJECT=mgk_64_k612
MODE=${MODE:-userdebug}
OUT_DIR=${OUT_DIR:-$PWD/out}

# kernel/configs/<device>{,_stability}.config. mgk_64.bzl also keys the device
# module list off the name appearing here, so it is not optional.
DEVICE=${DEVICE:-warhol}
DEFCONFIG_OVERLAYS="${DEVICE}.config ${DEVICE}_stability.config"

TARGET=${1:-//kernel_device_modules-6.12:${PROJECT}_kernel_aarch64.${MODE}}

export BAZEL_DO_NOT_DETECT_CPP_TOOLCHAIN=1

# --experimental_sibling_repository_layout is not optional here.
#
# This workspace has a real top-level external/ directory (external/lz4,
# external/toybox, external/zlib, external/pigz, ... straight out of the AOSP
# kernel manifest), and the host tools kleaf builds from source live in
# external repos that Bazel reaches through execroot/_main/external. Those two
# collide: as soon as the build touches main-repo packages, Bazel plants the
# main repo's top-level entries into the execroot, skips the reserved name
# "external", and deletes any execroot/_main/external it finds -- so every
# sandbox symlink into @lz4 / @toybox / @zlib / @zopfli / @pigz dangles and
# clang reports "no such file or directory" on a source file. Which file it
# trips over depends on scheduling, so it looks like a flake but is not, and
# --config=local does not help (it makes it deterministic instead).
#
# The sibling layout puts external repos at output_base/execroot/<repo> instead,
# so nothing needs the execroot "external" name and the collision is gone.

# The env vars below reach the build through repository rules / module
# extensions, and this Bazel no longer leaks the client environment into
# those -- they have to be passed as --repo_env explicitly.
exec tools/bazel \
  --output_user_root="${OUT_DIR}" \
  --output_base="${OUT_DIR}/bazel/output_user_root/output_base" \
  build ${NOBUILD:+--nobuild} ${JOBS:+--jobs=${JOBS}} ${EXTRA} --verbose_failures \
  $([ "${SANDBOX:-1}" = 0 ] && echo --config=local --spawn_strategy=local) \
  --experimental_sibling_repository_layout \
  --experimental_writable_outputs \
  --allow_ddk_unsafe_headers=1 \
  --workaround_btrfs_b292212788 \
  --experimental_optimize_ddk_config_actions \
  --//build/bazel_mgk_rules:kernel_version=6.12 \
  --user_ddk_unsafe_headers=//kernel_device_modules-6.12:mtk_use_gki_unsafe_headers \
  --repo_env=KERNEL_VERSION=kernel-6.12 \
  --repo_env=KERNEL_BUILD_VARIANT="${MODE}" \
  --repo_env="DEFCONFIG_OVERLAYS=${DEFCONFIG_OVERLAYS}" \
  --repo_env=SUPPORT_PLATFORM= \
  "${TARGET}"
