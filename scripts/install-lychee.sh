#!/usr/bin/env bash
# Install the lychee link checker.
#
# Shared by both CI definitions and by check-links.sh, which calls it when the
# binary is missing. Tool installation that is genuinely identical belongs in a
# script for the same reason the checks themselves do.
#
# The version is pinned. "latest" makes the build depend on whatever was
# released this morning, which turns an unrelated upstream change into a broken
# pipeline on a day nobody touched this repository.
set -euo pipefail

. "$(dirname "$0")/tools.sh"

# The release tag carries the project name: "lychee-v0.24.2", not "v0.24.2".
LYCHEE_VERSION="${LYCHEE_VERSION:-lychee-v0.24.2}"

tools_platform

# lychee names its assets by Rust target triple.
case "$tools_arch" in
  amd64) rust_arch="x86_64" ;;
  arm64) rust_arch="aarch64" ;;
esac

case "$tools_os" in
  linux)   target="${rust_arch}-unknown-linux-gnu"; archive_ext="tar.gz"; binary="lychee" ;;
  darwin)  target="${rust_arch}-apple-darwin";      archive_ext="tar.gz"; binary="lychee" ;;
  windows) target="x86_64-pc-windows-msvc";         archive_ext="zip";    binary="lychee.exe" ;;
esac

if tools_installed "$binary" "${LYCHEE_VERSION#lychee-v}"; then
  echo "==> lychee ${LYCHEE_VERSION} already installed"
  exit 0
fi

archive="lychee-${target}.${archive_ext}"
base="https://github.com/lycheeverse/lychee/releases/download/${LYCHEE_VERSION}"

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

echo "==> downloading lychee ${LYCHEE_VERSION} for ${target}"
curl -fsSL -o "${workdir}/${archive}" "${base}/${archive}"

tools_extract "${workdir}/${archive}" "$workdir"
tools_install "$(tools_locate "$workdir" "$binary")" "$binary"

"${tools_bin_dir}/${binary}" --version
