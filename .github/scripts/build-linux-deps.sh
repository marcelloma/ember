#!/usr/bin/env bash
set -euo pipefail

prefix="${RUNNER_TEMP:?}/ember-sdl"
work="${RUNNER_TEMP}/ember-sdl-sources"
mkdir -p "$prefix" "$work"
build_sdl() {
    local project="$1" version="$2" checksum="$3"
    shift 3
    local archive="$work/$project.tar.gz" source="$work/$project-$version"
    curl --fail --location --retry 3 "https://codeload.github.com/libsdl-org/$project/tar.gz/refs/tags/release-$version" -o "$archive"
    echo "$checksum  $archive" | sha256sum --check
    mkdir -p "$source"
    tar -xzf "$archive" --strip-components=1 -C "$source"
    cmake -S "$source" -B "$source/build" -G Ninja \
        -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$prefix" \
        -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_PREFIX_PATH="$prefix" \
        -DBUILD_SHARED_LIBS=ON "$@"
    cmake --build "$source/build" --parallel 2
    cmake --install "$source/build"
    mkdir -p "$prefix/licenses/$project"
    cp "$source/LICENSE.txt" "$prefix/licenses/$project/"
}

build_sdl SDL 3.4.18 c4b08b950bd29d83caae0ab8d884298d27046a9d30700fb42841c50992665c90 \
    -DSDL_TESTS=OFF -DSDL_STATIC=OFF
build_sdl SDL_ttf 3.2.2 ff6b81d3dc39d843cc3ead6dedd68043a79513d266792ea89445547ef4e9b073 \
    -DSDLTTF_SAMPLES=OFF -DSDLTTF_VENDORED=OFF -DSDLTTF_PLUTOSVG=OFF
build_sdl SDL_image 3.4.8 a3cdbe4bee5dc6251bea15c379bde2bc87bc1eb78a6d68784852f51732d41c24 \
    -DSDLIMAGE_SAMPLES=OFF -DSDLIMAGE_TESTS=OFF -DSDLIMAGE_VENDORED=OFF \
    -DSDLIMAGE_AVIF=OFF -DSDLIMAGE_TIF=OFF -DSDLIMAGE_WEBP=OFF

echo "PKG_CONFIG_PATH=$prefix/lib/pkgconfig" >> "$GITHUB_ENV"
echo "LD_LIBRARY_PATH=$prefix/lib" >> "$GITHUB_ENV"
