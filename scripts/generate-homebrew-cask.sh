#!/usr/bin/env bash
set -euo pipefail

VERSION=""
SHA256=""
REPO=""
OUTPUT="Casks/lingothing.rb"

usage() {
  cat <<USAGE
Usage: $0 --version <version> --sha256 <sha256> --repo <owner/repo> [--output <path>]
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="$2"
      shift 2
      ;;
    --sha256)
      SHA256="$2"
      shift 2
      ;;
    --repo)
      REPO="$2"
      shift 2
      ;;
    --output)
      OUTPUT="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "${VERSION}" || -z "${SHA256}" || -z "${REPO}" ]]; then
  usage
  exit 1
fi

mkdir -p "$(dirname "${OUTPUT}")"

cat > "${OUTPUT}" <<CASK
cask "lingothing" do
  version "${VERSION}"
  sha256 "${SHA256}"

  url "https://github.com/${REPO}/releases/download/v#{version}/LingoThing-#{version}.app.zip"
  name "LingoThing"
  desc "Menu bar language practice app"
  homepage "https://github.com/${REPO}"

  depends_on macos: ">= :sonoma"

  app "LingoThing.app"

  zap trash: [
    "~/Library/Application Support/LingoThing",
    "~/Library/Preferences/com.lingothing.app.plist",
  ]
end
CASK

echo "Wrote ${OUTPUT}"
