#!/usr/bin/env bash
# Shared plumbing for the pinned tools the checks depend on.
#
# Sourced, never executed. It puts the local tool directory on PATH and defines
# the helpers the installers and the check scripts both use, so a check runs the
# same way on a workstation with nothing installed and on a CI runner.
#
# Tools live in .tools/ at the repository root, which is gitignored. Installing
# there rather than into a system directory means no sudo, no interference with
# a version the operator installed for their own reasons, and nothing left on
# the machine when the repository is deleted.

tools_repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tools_bin_dir="${TOOLS_BIN_DIR:-${tools_repo_root}/.tools}"

# Prepended, so the pinned version is the one that runs even on a machine that
# has its own copy. Hosted runner images ship Bicep, for one, at whatever
# version the image was built with. Pinning only means something if the pinned
# binary is the one that wins.
export PATH="${tools_bin_dir}:${PATH}"

# Sets tools_os to linux, darwin or windows and tools_arch to amd64 or arm64.
#
# uname reports arm64 on Apple silicon and aarch64 on Linux for the same
# architecture. Both normalise to arm64 here, and each installer translates to
# whatever its own release assets are named.
tools_platform() {
  case "$(uname -s)" in
    Linux)                tools_os="linux" ;;
    Darwin)               tools_os="darwin" ;;
    MINGW*|MSYS*|CYGWIN*) tools_os="windows" ;;
    *)
      echo "FAIL: unsupported platform '$(uname -s)'. Install the tool manually and put it on PATH." >&2
      return 1
      ;;
  esac

  case "$(uname -m)" in
    x86_64|amd64)  tools_arch="amd64" ;;
    aarch64|arm64) tools_arch="arm64" ;;
    *)
      echo "FAIL: unsupported architecture '$(uname -m)'. Install the tool manually and put it on PATH." >&2
      return 1
      ;;
  esac
}

tools_extract() {
  local archive="$1" dest="$2"

  case "$archive" in
    *.zip)
      # unzip is not on every image, and Python usually is. Ubuntu ships only
      # python3 and Git for Windows usually only python, so both are tried.
      if command -v unzip > /dev/null 2>&1; then
        unzip -q -o "$archive" -d "$dest"
      else
        local py
        py="$(command -v python3 || command -v python)" || {
          echo "FAIL: extracting ${archive} needs unzip or Python, and neither is installed" >&2
          return 1
        }
        "$py" -c "import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" \
          "$archive" "$dest"
      fi
      ;;
    *.tar.gz)
      tar -xzf "$archive" -C "$dest"
      ;;
    *)
      echo "FAIL: unknown archive type '${archive}'" >&2
      return 1
      ;;
  esac
}

# tools_locate <search root> <binary name>
#
# Releases disagree on whether the binary sits at the root of the archive or
# inside a directory named after the target, so it is searched for rather than
# assumed. A layout change upstream then prints the archive contents instead of
# a missing file error that names only the symptom.
tools_locate() {
  local root="$1" binary="$2" found

  found="$(find "$root" -name "$binary" -type f -print -quit)"
  if [ -z "$found" ]; then
    echo "FAIL: no ${binary} in the archive. The release layout may have changed:" >&2
    find "$root" -type f | head -20 >&2
    return 1
  fi
  printf '%s\n' "$found"
}

tools_install() {
  local source="$1" name="$2"

  mkdir -p "$tools_bin_dir"
  mv "$source" "${tools_bin_dir}/${name}"
  chmod +x "${tools_bin_dir}/${name}"
  echo "==> installed ${tools_bin_dir}/${name}"
}

# tools_installed <binary> <version string>
#
# True when the pinned version is already in place, which is what makes the
# installers cheap enough for the check scripts to call on every run.
tools_installed() {
  [ -x "${tools_bin_dir}/$1" ] && "${tools_bin_dir}/$1" --version 2>/dev/null | grep -qF "$2"
}

# ensure_tool <binary> <installer script>
#
# Used by the check scripts. A check that cannot run without a separate install
# step is a check that only runs in CI, which is the last place worth finding a
# problem.
#
# It runs the installer rather than looking for the binary on PATH, because any
# copy on PATH could be any version. The installer returns straight away when
# the pinned version is already in place.
ensure_tool() {
  local binary="$1" installer="$2"

  if ! "${tools_repo_root}/scripts/${installer}"; then
    echo "FAIL: could not install ${binary}. Install it manually and re-run." >&2
    return 1
  fi
}
