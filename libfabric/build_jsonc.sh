#!/bin/bash
# json-c headers for libfabric >= 2.x, whose CXI provider will not configure
# without them. The library itself is dlopened at run time
# (--enable-cxi-json-dlopen), so only the headers matter; LUMI ships
# libjson-c.so.5 but no headers.
#   build_jsonc.sh <prefix>
set -euo pipefail
P=${1:?prefix}
S=$P.src
TAG=json-c-0.17-20230812
rm -rf "$S" "$P"
git clone -q --depth 1 -b "$TAG" https://github.com/json-c/json-c.git "$S"
cmake -S "$S" -B "$S/build" -DCMAKE_INSTALL_PREFIX="$P" -DBUILD_STATIC_LIBS=OFF \
  -DCMAKE_BUILD_TYPE=Release > "$S/cmake.log"
cmake --build "$S/build" -j 16 > "$S/build.log"
cmake --install "$S/build" > "$S/install.log"
echo "json-c $TAG $(git -C "$S" rev-parse HEAD) -> $P"
