#!/bin/bash
set -eu

DATE_FORMAT="%Y-%m-%d %H:%M:%S"
VERSION_PATTERN='^[0-9]+\.[0-9]+\.[0-9]+$'

info() {
  echo "$(date +"$DATE_FORMAT") [INFO] $*"
}

err() {
  echo "$(date +"$DATE_FORMAT") [ERR] $*" >&2
}

is_version() {
  [[ "$1" =~ $VERSION_PATTERN ]]
}

latest_version() {
  sort -V | tail -n 1
}

# List released Nim versions (tags without the leading "v").
fetch_versions() {
  git ls-remote --tags https://github.com/nim-lang/nim 'refs/tags/v*' 2>/dev/null |
    sed -E 's:.*refs/tags/v?::' |
    sed 's/\^{}//' |
    grep -E "$VERSION_PATTERN"
}

move_nim_compiler() {
  src_dir="$1"
  dst_dir="$2"
  if [[ -d "$dst_dir" ]]; then
    info "remove cached directory (path = $dst_dir)"
    rm -rf "$dst_dir"
  fi
  mv "$src_dir" "$dst_dir"
}

url_available() {
  local code
  code="$(curl -sIL -o /dev/null -w '%{http_code}' "$1" 2>/dev/null || true)"
  [[ "$code" == "200" ]]
}

brew_stable_matches() {
  if ! command -v brew >/dev/null 2>&1; then
    return 1
  fi
  local stable
  stable="$(brew info nim 2>/dev/null | head -n 1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)"
  [[ -n "$stable" && "$stable" == "$nim_version" ]]
}

download_and_extract_tarxz() {
  local url="$1"
  local file="$2"
  info "downloading $url"
  curl -fsSL "$url" -o "$file"
  tar xf "$file"
  rm -f "$file"
  move_nim_compiler "nim-${nim_version}" "$nim_install_dir"
}

build_from_source() {
  local work="$PWD"
  local src_dir="$work/Nim-src"
  rm -rf "$src_dir"
  info "building Nim ${nim_version} from source (this may take a while)"
  git clone --depth 1 --branch "v${nim_version}" https://github.com/nim-lang/Nim "$src_dir"
  cd "$src_dir"
  ./build_all.sh
  cd "$work"
  move_nim_compiler "$src_dir" "$nim_install_dir"
}

# releases.json mirror (nimbase/nim-prebuilts `latest` release, byte-copy of
# https://nim-lang.org/releases.json). Always prefer `github_url` (GitHub) over
# `nimlang_url` for reliability.
MIRROR_URL="https://github.com/nimbase/nim-prebuilts/releases/download/latest/releases.json"
UPSTREAM_URL="https://nim-lang.org/releases.json"

# Map host to releases.json platform key. Empty means "not built upstream"
# (notably Windows arm64).
releases_key() {
  local key=""
  case "$os" in
    Linux)
      case "$(uname -m)" in
        x86_64 | amd64) key="linux_x64" ;;
        aarch64 | arm64) key="linux_arm64" ;;
      esac
      ;;
    macOS)
      case "$(uname -m)" in
        arm64) key="macosx_arm64" ;;
        x86_64) key="macosx_x64" ;;
      esac
      ;;
    Windows)
      case "$(uname -m)" in
        x86_64 | amd64) key="windows_x64" ;;
      esac
      ;;
  esac
  echo "$key"
}

# Print "<github_url> <digest>" for version/key from a releases.json file.
releases_entry() {
  local json="$1" ver="$2" key="$3" py
  py="$(command -v python3 || command -v python || true)"
  [[ -n "$py" ]] || return 1
  "$py" -c "
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
e = d.get(sys.argv[2], {}).get(sys.argv[3], {})
print(e.get('github_url', ''), e.get('digest', ''))
" "$json" "$ver" "$key" 2>/dev/null
}

verify_sha256() {
  local file="$1" digest="$2" hex=""
  hex="${digest#sha256:}"
  [[ -n "$hex" && "$hex" != "$digest" ]] || return 0
  if command -v sha256sum >/dev/null 2>&1; then
    echo "${hex}  ${file}" | sha256sum -c - >/dev/null 2>&1
  elif command -v shasum >/dev/null 2>&1; then
    echo "${hex}  ${file}" | shasum -a 256 -c >/dev/null 2>&1
  else
    return 0
  fi
}

download_from_releases() {
  local key tmp url digest
  key="$(releases_key)"
  [[ -n "$key" ]] || return 1
  tmp="$(mktemp)"
  if curl -fsSL "$MIRROR_URL" -o "$tmp" 2>/dev/null; then
    info "using nim-prebuilts releases mirror"
  elif curl -fsSL "$UPSTREAM_URL" -o "$tmp" 2>/dev/null; then
    info "mirror unavailable, using nim-lang.org/releases.json"
  else
    rm -f "$tmp"
    return 1
  fi
  read -r url digest < <(releases_entry "$tmp" "$nim_version" "$key" || true)
  rm -f "$tmp"
  [[ -n "$url" ]] || return 1
  case "$url" in
    *.tar.xz)
      info "downloading $url"
      curl -fsSL "$url" -o nim.tar.xz
      if [[ -n "$digest" ]] && ! verify_sha256 nim.tar.xz "$digest"; then
        err "checksum mismatch for $url"
        rm -f nim.tar.xz
        return 1
      fi
      tar xf nim.tar.xz
      rm -f nim.tar.xz
      move_nim_compiler "nim-${nim_version}" "$nim_install_dir"
      ;;
    *.zip)
      info "downloading $url"
      curl -fsSL "$url" -o nim.zip
      if [[ -n "$digest" ]] && ! verify_sha256 nim.zip "$digest"; then
        err "checksum mismatch for $url"
        rm -f nim.zip
        return 1
      fi
      powershell.exe -NoProfile -Command "Expand-Archive -Force -LiteralPath 'nim.zip' -DestinationPath '.'"
      rm -f nim.zip
      move_nim_compiler "nim-${nim_version}" "$nim_install_dir"
      ;;
    *)
      return 1
      ;;
  esac
}

# parse command line args
nim_version="stable"
nim_install_dir=".nim_runtime"
os="Linux"
repo_token=""
homebrew_only=false
while ((0 < $#)); do
  case $1 in
    --nim-version)
      nim_version=$2
      shift 2
      ;;
    --nim-install-directory)
      nim_install_dir=$2
      shift 2
      ;;
    --os)
      os=$2
      shift 2
      ;;
    --repo-token)
      repo_token=$2
      shift 2
      ;;
    --homebrew-nim)
      homebrew_only=true
      shift
      ;;
    *)
      err "unknown option: $1"
      exit 1
      ;;
  esac
done

if [[ "$nim_version" == "devel" ]]; then
  err "'devel' is not supported yet. Use a released version, e.g. 'stable', '2.2.10' or '2.x'."
  exit 1
fi

# resolve 'stable'
if [[ "$nim_version" == "stable" ]]; then
  resolved="$(curl -fsSL https://nim-lang.org/channels/stable 2>/dev/null | grep -E "$VERSION_PATTERN" | head -n 1 || true)"
  if [[ -z "$resolved" ]]; then
    info "could not resolve 'stable' from nim-lang.org/channels/stable, falling back to latest tag"
    resolved="$(fetch_versions | latest_version)"
  fi
  nim_version="$resolved"
fi

# resolve version ranges (2.x, 2.2.x, 2.2)
case "$nim_version" in
  *\.x)
    prefix="${nim_version%\.x}"
    ;;
  *)
    if [[ "$nim_version" =~ ^[0-9]+\.[0-9]+$ ]]; then
      prefix="$nim_version"
    else
      prefix=""
    fi
    ;;
esac
if [[ -n "$prefix" ]] && ! is_version "$nim_version"; then
  regexp="^$(echo "$prefix" | sed 's/\./\\./g')"
  resolved="$(fetch_versions | grep -E "$regexp" | latest_version)"
  if [[ -z "$resolved" ]]; then
    err "no released Nim version matches '${nim_version}'"
    exit 1
  fi
  info "resolved '${nim_version}' -> ${resolved}"
  nim_version="$resolved"
fi

if ! is_version "$nim_version"; then
  err "invalid nim-version: $nim_version"
  exit 1
fi

# --homebrew-nim: install via Homebrew and skip prebuilt/source download (macOS only)
if [[ "$homebrew_only" == "true" ]]; then
  if [[ "$os" != "macOS" ]]; then
    info "--homebrew-nim is only supported on macOS; ignoring"
    homebrew_only=false
  fi
fi

if [[ "$homebrew_only" == "true" ]]; then
  # Ensure Homebrew is in PATH (arm64 runners install to /opt/homebrew)
  if ! command -v brew >/dev/null 2>&1; then
    if [[ -x /opt/homebrew/bin/brew ]]; then
      eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -x /usr/local/bin/brew ]]; then
      eval "$(/usr/local/bin/brew shellenv)"
    fi
  fi
  if ! command -v brew >/dev/null 2>&1; then
    err "Homebrew not found; cannot use --homebrew-nim"
    exit 1
  fi
  info "installing Nim via Homebrew (--homebrew-nim)"
  brew install nim
  mkdir -p "${nim_install_dir}/bin"
  for tool in nim nimble nimgrep nimsuggest; do
    path="$(command -v "$tool" 2>/dev/null || true)"
    if [[ -n "$path" && -x "$path" ]]; then
      ln -sfn "$path" "${nim_install_dir}/bin/${tool}"
    fi
  done
  if [[ ! -x "${nim_install_dir}/bin/nim" ]]; then
    err "nim binary not found after brew install"
    exit 1
  fi
  brew_version="$(brew info nim 2>/dev/null | head -n 1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)"
  if [[ -n "$brew_version" ]]; then
    nim_version="$brew_version"
  fi
  echo "$nim_version" > "${nim_install_dir}/.nim-version"
  info "RESOLVED_VERSION=${nim_version}"
  info "Nim ${nim_version} installed at ${PWD}/${nim_install_dir}"
  exit 0
fi

# reuse an existing installation (e.g. restored from cache)
if [[ -f "${nim_install_dir}/.nim-version" ]] &&
  [[ "$(cat "${nim_install_dir}/.nim-version")" == "$nim_version" ]] &&
  [[ -x "${nim_install_dir}/bin/nim" || -x "${nim_install_dir}/bin/nim.exe" ]]; then
  # Verify the cached binary matches the host architecture; an x86_64 binary
  # under Rosetta will link against x86_64 libs, causing architecture mismatches
  # with arm64 homebrew kegs.
  nim_arch="$(file -b "${nim_install_dir}/bin/nim" 2>/dev/null || true)"
  host_arch="$(uname -m)"
  if [[ "$nim_arch" == *"$host_arch"* ]]; then
    info "Nim ${nim_version} already installed at ${nim_install_dir}; skipping download"
    exit 0
  else
    info "installed Nim architecture ($nim_arch) does not match host ($host_arch); reinstalling"
    rm -rf "$nim_install_dir"
  fi
fi

info "installing Nim ${nim_version} (os = $os)"

if ! download_from_releases; then
  case "$os" in
    Linux)
      case "$(uname -m)" in
        x86_64 | amd64)
          download_and_extract_tarxz \
            "https://nim-lang.org/download/nim-${nim_version}-linux_x64.tar.xz" "nim.tar.xz"
          ;;
        aarch64 | arm64)
          build_from_source
          ;;
        *)
          err "unsupported architecture: $(uname -m)"
          exit 1
          ;;
      esac
      ;;
    macOS)
      case "$(uname -m)" in
        arm64)
          if url_available "https://nim-lang.org/download/nim-${nim_version}-macosx_arm64.tar.xz"; then
            download_and_extract_tarxz \
              "https://nim-lang.org/download/nim-${nim_version}-macosx_arm64.tar.xz" "nim.tar.xz"
          elif url_available "https://nim-lang.org/download/nim-${nim_version}-macosx_x64.tar.xz"; then
            download_and_extract_tarxz \
              "https://nim-lang.org/download/nim-${nim_version}-macosx_x64.tar.xz" "nim.tar.xz"
          elif brew_stable_matches; then
            info "installing Nim ${nim_version} via Homebrew"
            brew install nim
            mkdir -p "${nim_install_dir}/bin"
            for tool in nim nimble nimgrep nimsuggest; do
              path="$(command -v "$tool" 2>/dev/null || true)"
              if [[ -n "$path" && -x "$path" ]]; then
                ln -sfn "$path" "${nim_install_dir}/bin/${tool}"
              fi
            done
          else
            build_from_source
          fi
          ;;
        x86_64)
          if url_available "https://nim-lang.org/download/nim-${nim_version}-macosx_x64.tar.xz"; then
            download_and_extract_tarxz \
              "https://nim-lang.org/download/nim-${nim_version}-macosx_x64.tar.xz" "nim.tar.xz"
          elif brew_stable_matches; then
            info "installing Nim ${nim_version} via Homebrew"
            brew install nim
            mkdir -p "${nim_install_dir}/bin"
            for tool in nim nimble nimgrep nimsuggest; do
              path="$(command -v "$tool" 2>/dev/null || true)"
              if [[ -n "$path" && -x "$path" ]]; then
                ln -sfn "$path" "${nim_install_dir}/bin/${tool}"
              fi
            done
          else
            build_from_source
          fi
          ;;
        *)
          err "unsupported macOS architecture: $(uname -m)"
          exit 1
          ;;
      esac
      ;;
    Windows)
      info "downloading https://nim-lang.org/download/nim-${nim_version}_x64.zip"
      curl -fsSL "https://nim-lang.org/download/nim-${nim_version}_x64.zip" -o nim.zip
      powershell.exe -NoProfile -Command "Expand-Archive -Force -LiteralPath 'nim.zip' -DestinationPath '.'"
      rm -f nim.zip
      move_nim_compiler "nim-${nim_version}" "$nim_install_dir"
      ;;
    *)
      err "unsupported os: $os"
      exit 1
      ;;
  esac
fi

if [[ ! -x "${nim_install_dir}/bin/nim" ]] && [[ ! -x "${nim_install_dir}/bin/nim.exe" ]]; then
  err "nim binary not found after install (expected: ${nim_install_dir}/bin/nim)"
  exit 1
fi

echo "$nim_version" > "${nim_install_dir}/.nim-version"
info "RESOLVED_VERSION=${nim_version}"
info "Nim ${nim_version} installed at ${PWD}/${nim_install_dir}"
