#!/bin/bash
# Unsigned arm64 IPA, same shape as the other apps in this repo:
# clang + iphoneos SDK, ad-hoc codesign, zip Payload/*.app.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
CC="$(xcrun --sdk iphoneos -f clang)"
CXX="$(xcrun --sdk iphoneos -f clang++)"
LLAMA_TAG="v0.8.0"
LLAMA_SRC="${RUNNER_TEMP:-/tmp}/llama.cpp-${LLAMA_TAG}"

if [[ ! -f "$LLAMA_SRC/include/llama.h" ]]; then
  rm -rf "$LLAMA_SRC"
  git clone --depth 1 --branch "$LLAMA_TAG" https://github.com/ggml-org/llama.cpp.git "$LLAMA_SRC"
fi

BUILD="$LLAMA_SRC/build-ios"
cmake -S "$LLAMA_SRC" -B "$BUILD" \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_SYSROOT="$SDK" \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
  -DGGML_METAL=OFF \
  -DGGML_NATIVE=OFF \
  -DGGML_BLAS=OFF \
  -DGGML_ACCELERATE=ON \
  -DGGML_OPENMP=OFF \
  -DGGML_CPU_ALL_VARIANTS=OFF \
  -DGGML_BACKEND_DL=OFF \
  -DLLAMA_BUILD_EXAMPLES=OFF \
  -DLLAMA_BUILD_TESTS=OFF \
  -DLLAMA_BUILD_SERVER=OFF \
  -DLLAMA_BUILD_TOOLS=OFF \
  -DLLAMA_BUILD_APP=OFF \
  -DLLAMA_BUILD_COMMON=OFF \
  -DGGML_CCACHE=OFF \
  -DLLAMA_CURL=OFF \
  -DBUILD_SHARED_LIBS=OFF
cmake --build "$BUILD" --config Release --parallel 3

WORK="$ROOT/build/biblia-reels"
rm -rf "$WORK"
mkdir -p "$WORK/obj" "$WORK/Payload/BibliaReels.app"
FLAGS=(-target arm64-apple-ios15.0 -isysroot "$SDK" -miphoneos-version-min=15.0 -O2)

for src in "$ROOT"/biblia-reels/src/*.m; do
  "$CC" "${FLAGS[@]}" -fobjc-arc -c "$src" -o "$WORK/obj/$(basename "${src%.m}").o"
done
"$CXX" "${FLAGS[@]}" -std=c++17 \
  -I"$LLAMA_SRC/include" -I"$LLAMA_SRC/ggml/include" \
  -c "$ROOT/biblia-reels/src/llama_bridge.cpp" -o "$WORK/obj/llama_bridge.o"

LIBS=()
while IFS= read -r lib; do
  LIBS+=("$lib")
done < <(find "$BUILD" -name '*.a' -not -path '*/CMakeFiles/*' | sort)
echo "Static libraries:"
printf '  %s\n' "${LIBS[@]}"
if [[ "${#LIBS[@]}" -eq 0 ]]; then
  echo "llama.cpp did not produce static libraries"
  exit 1
fi

APP="$WORK/Payload/BibliaReels.app"
"$CXX" "${FLAGS[@]}" -fobjc-arc \
  "$WORK"/obj/*.o \
  -Wl,-all_load "${LIBS[@]}" -Wl,-noall_load \
  -framework UIKit -framework Foundation -framework AVFoundation \
  -framework AudioToolbox -framework CoreGraphics -framework QuartzCore \
  -framework Accelerate -framework CoreFoundation \
  -o "$APP/BibliaReels"

cp "$ROOT/biblia-reels/Info.plist" "$APP/Info.plist"
cp "$ROOT/biblia-reels/config.json" "$APP/config.json"
cp "$ROOT"/biblia-reels/data/*.json "$APP/"
cp "$ROOT"/biblia-reels/assets/* "$APP/"
printf 'APPL????' > "$APP/PkgInfo"
plutil -lint "$APP/Info.plist"
strip -x "$APP/BibliaReels" || true
codesign -s - --force "$APP"
rm -f "$ROOT/BibliaReels.ipa"
(cd "$WORK" && zip -qry "$ROOT/BibliaReels.ipa" Payload)

BYTES="$(stat -f%z "$ROOT/BibliaReels.ipa")"
echo "IPA size: $BYTES bytes"
if [[ "$BYTES" -gt 80000000 ]]; then
  echo "IPA is over 80 MB. Media or the GGUF must not be inside the app."
  exit 1
fi
file "$APP/BibliaReels"
unzip -l "$ROOT/BibliaReels.ipa"
