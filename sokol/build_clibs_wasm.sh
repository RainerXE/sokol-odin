#!/bin/bash
# Build the sokol C libraries for Odin's own WASM target (js_wasm32) -- NO Emscripten.
#
# Replaces the upstream emcc/emar script. Uses clang + `vendor:libc-shim` (Odin's small
# libc over Odin libraries), exactly like vendor:box2d / vendor:stb do:
#
#   clang -c --target=wasm32 --sysroot=$(odin root)vendor/libc-shim ...
#
# Output: one relocatable .o per lib, next to its binding (gfx/sokol_gfx_wasm_gl_release.o);
# the binding does `foreign import ... "sokol_gfx_wasm_gl_release.o"`. The .o files are build
# products (git-ignored), not committed.
#
# Currently built: gfx only.
#   - sokol_app is not built for the web: RuiShin has its own web platform layer on
#     core:sys/wasm/js (plan 261006-pure-wasm-web.md, step 3).
#   - sokol_log: the C version needs <emscripten/emscripten.h> (EM_JS). On wasm the Odin
#     binding provides `slog.func` itself (sokol/log/log_wasm.odin), nothing to build.
#   - sokol_time: also needs emscripten.h; RuiShin does not use it, so no wasm replacement
#     exists yet (Odin's core:time covers it if ever needed).
#   - glue/gl/shape/debugtext compile, but nothing needs them on the web yet.
#
# The GL calls sokol_gfx makes (glBindBuffer, ...) are left UNDEFINED in the .o: the Odin
# side defines them (RuiShin: src/web/glshim, GL C ABI -> vendor:wasm/WebGL -> WebGL2).
#
# Requirements: clang with the wasm32 backend (Homebrew `llvm`, NOT Apple's /usr/bin/clang),
# `odin` on PATH (for `odin root`), and the Khronos GLES3 headers (GLES3/gl3.h,
# KHR/khrplatform.h) -- compile-time only; RuiShin bundles pinned copies in
# vendor-local/khronos-headers, which are used by default.
#
#   CLANG=/path/to/clang         override the compiler
#   GLES3_INCLUDE=/path/include  dir that contains GLES3/gl3.h
#
# Why -D__EMSCRIPTEN__: sokol_gfx.h gates its WebGL behaviour on it -- GLES3/gl3.h include,
# no glGetError() calls, separate buffer types (WebGL2 forbids one buffer on several
# targets), no ETC2. Those are WebGL facts, not Emscripten facts; it is the same flag the
# old emcc libs were built with. Sokol's other __EMSCRIPTEN__ uses are in WGPU/app code,
# which this build does not touch.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
# RuiShin layout: shared toolchain discovery lives next to the submodule (vendor-local/wasm-support).
source "$PWD/../../wasm-support/toolchain.sh"

declare -a libs=("gfx")


find_gles3_include() {
    if [ -n "${GLES3_INCLUDE:-}" ]; then echo "$GLES3_INCLUDE"; return; fi
    # RuiShin ships pinned copies next to this submodule (vendor-local/khronos-headers).
    local bundled="$PWD/../../khronos-headers"
    if [ -f "$bundled/GLES3/gl3.h" ] && [ -f "$bundled/KHR/khrplatform.h" ]; then
        (cd "$bundled" && pwd); return
    fi
    for d in /opt/homebrew/include /usr/local/include /usr/include \
             /opt/homebrew/opt/mesa/include; do
        if [ -f "$d/GLES3/gl3.h" ] && [ -f "$d/KHR/khrplatform.h" ]; then echo "$d"; return; fi
    done
    echo "ERROR: GLES3/gl3.h not found; install the Khronos headers (mesa / libgles-dev) or set GLES3_INCLUDE" >&2
    exit 1
}

CLANG="$(find_clang)"
GLES3_INC="$(find_gles3_include)"
SYSROOT="$(libc_shim)"

COMMON=(-c --target=wasm32 --sysroot="$SYSROOT" -DIMPL -DSOKOL_GLES3 -D__EMSCRIPTEN__
        -I"$GLES3_INC" -Wno-unused-function)

echo "clang:   $CLANG"
echo "sysroot: $SYSROOT"
echo "gles3:   $GLES3_INC"

for l in "${libs[@]}"
do
    out="$l/sokol_${l}_wasm_gl_debug.o"
    echo "$out"
    "$CLANG" "${COMMON[@]}" -g c/sokol_$l.c -o "$out"
    out="$l/sokol_${l}_wasm_gl_release.o"
    echo "$out"
    "$CLANG" "${COMMON[@]}" -O2 -DNDEBUG c/sokol_$l.c -o "$out"
done
