#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
revision=bcdfed48262acb6e18a65d479c5ea8817012c961
upstream=https://github.com/nebius/nebius-physical-ai.git
source_dir=${NPA_SOURCE_DIR:-"$root/.npa-upstream"}
venv=${NPA_VENV_DIR:-"$root/.venv"}
native_dir=${NPA_NATIVE_DIR:-"$root/.npa-native"}

if [ "$(uname -s)" != Darwin ] || [ "$(uname -m)" != x86_64 ]; then
    printf '%s\n' 'This installer targets Intel macOS.' >&2
    exit 1
fi

if [ -x /Library/Developer/CommandLineTools/usr/bin/clang ]; then
    export DEVELOPER_DIR=/Library/Developer/CommandLineTools
fi
if ! xcrun --find clang >/dev/null 2>&1; then
    printf '%s\n' 'Install the macOS Command Line Tools with xcode-select --install, then retry.' >&2
    exit 1
fi

uv=$(command -v uv || true)
if [ -z "$uv" ] && [ -x "$HOME/.local/bin/uv" ]; then
    uv="$HOME/.local/bin/uv"
fi
if [ -z "$uv" ] || ! "$uv" pip install --help | grep -q -- '--excludes'; then
    printf '%s\n' 'Install or update uv to a version that supports uv pip install --excludes.' >&2
    exit 1
fi

if [ ! -d "$source_dir" ]; then
    git init -q "$source_dir"
fi
if [ ! -d "$source_dir/.git" ] && [ ! -f "$source_dir/.git" ]; then
    printf 'Expected a Git checkout at %s\n' "$source_dir" >&2
    exit 1
fi
if ! git -C "$source_dir" rev-parse --verify HEAD >/dev/null 2>&1; then
    git -C "$source_dir" fetch --depth=1 "$upstream" "$revision"
    git -C "$source_dir" checkout --detach --quiet FETCH_HEAD
fi
if [ "$(git -C "$source_dir" rev-parse HEAD)" != "$revision" ]; then
    printf 'Use the pinned upstream revision %s in a separate checkout.\n' "$revision" >&2
    exit 1
fi

mkdir -p "$native_dir"
native_dir=$(CDPATH= cd -- "$native_dir" && pwd)
rust_dir="$native_dir/rust"
openssl_dir="$native_dir/openssl"
work=$(mktemp -d "${TMPDIR:-/tmp}/npa-native.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
trap 'exit 1' HUP INT TERM

download() {
    url=$1
    digest=$2
    archive="$work/${url##*/}"
    curl --fail --silent --show-error --location --proto '=https' --retry 2 --output "$archive" "$url"
    printf '%s  %s\n' "$digest" "$archive" | shasum -a 256 -c - >&2
    tar -xf "$archive" -C "$work"
}

install_rust_component() {
    name="$1-1.99.0-x86_64-apple-darwin"
    download "https://static.rust-lang.org/dist/2026-10-01/$name.tar.xz" "$2"
    "$work/$name/install.sh" --prefix="$rust_dir" --disable-ldconfig
}

if [ ! -x "$rust_dir/bin/rustc" ] || [ ! -x "$rust_dir/bin/cargo" ] ||
   [ ! -d "$rust_dir/lib/rustlib/x86_64-apple-darwin/lib" ]; then
    install_rust_component rustc 7460910254f059b49b99ee3ddbcf7197d16b9505b59c166e14a1465ee323a81d
    install_rust_component cargo 939b71952afd63ae73bc00f3517c19f0dd7ac54884b5fac16a813ee50985d14d
    install_rust_component rust-std 18ee81961a73c3ae966ecb1e8f6096438c90aeefece8856201a6ecc17f5bc850
fi

if [ ! -x "$openssl_dir/bin/openssl" ] || [ ! -f "$openssl_dir/lib/libcrypto.a" ] ||
   [ ! -f "$openssl_dir/lib/libssl.a" ] || [ ! -f "$openssl_dir/include/openssl/ssl.h" ]; then
    download https://github.com/openssl/openssl/releases/download/openssl-3.5.9/openssl-3.5.9.tar.gz \
        603f5602e2eef00d77fbd429d34dcd5822bb301757a1bc9cdb24c670f1eb859a
    (
        cd "$work/openssl-3.5.9"
        export MACOSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET:-14.0}
        ./Configure darwin64-x86_64-cc no-shared no-tests --prefix="$openssl_dir" --libdir=lib
        make -j"${NPA_BUILD_JOBS:-6}" build_sw
        make install_sw
    )
fi

if [ ! -x "$venv/bin/python" ]; then
    "$uv" venv --python 3.12 "$venv"
fi
PATH="$rust_dir/bin:$PATH" OPENSSL_DIR="$openssl_dir" OPENSSL_STATIC=1 \
    "$uv" pip install --python "$venv/bin/python" --no-binary cryptography \
    --excludes "$root/intel-macos-excludes.txt" -e "$source_dir/npa"
sh "$root/smoke-test.sh" "$venv"
