#!/usr/bin/env bash
set -euo pipefail

APP_NAME="LingoThing"
PROJECT_PATH="NotchGreek.xcodeproj"
SCHEME="NotchGreek"
BUNDLE_ID="com.lingothing.app"
MIN_MACOS="14.0"
ICON_SOURCE_DEFAULT="icons/install.png"
DIST_DIR="dist"
DERIVED_DATA_DIR=""
VERSION=""
BUILD_NUMBER=""
CREATE_PKG="false"
GENERATE_CASK="false"
GITHUB_REPO=""
UNIVERSAL="false"

usage() {
  cat <<USAGE
Usage: $0 [options]

Options:
  --version <semver>         Release version (default: latest git tag without leading v, or 0.1.0)
  --build-number <number>    Build number (default: UTC timestamp)
  --project <path>           Xcode project path (default: NotchGreek.xcodeproj)
  --scheme <name>            Xcode scheme (default: NotchGreek)
  --bundle-id <id>           Bundle identifier (default: com.lingothing.app)
  --icon <path>              Source PNG icon path (default: icons/install.png)
  --dist <path>              Output directory (default: dist)
  --derived-data <path>      DerivedData path (default: <dist>/DerivedData)
  --pkg                       Also create .pkg installer output
  --universal                Build universal binary (arm64 + x86_64)
  --github-repo <owner/repo> Generate Casks/lingothing.rb with release URL + checksum
  --help                     Show this help

Outputs:
  - <dist>/LingoThing.app
  - <dist>/LingoThing-<version>.app.zip
  - <dist>/LingoThing-<version>.pkg (when --pkg is passed)
  - <dist>/checksums.txt
USAGE
}

upsert_plist_string() {
  local plist_path="$1"
  local key="$2"
  local value="$3"

  if /usr/libexec/PlistBuddy -c "Print :${key}" "${plist_path}" >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c "Set :${key} ${value}" "${plist_path}"
  else
    /usr/libexec/PlistBuddy -c "Add :${key} string ${value}" "${plist_path}"
  fi
}

ICON_SOURCE="${ICON_SOURCE_DEFAULT}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="$2"
      shift 2
      ;;
    --build-number)
      BUILD_NUMBER="$2"
      shift 2
      ;;
    --project)
      PROJECT_PATH="$2"
      shift 2
      ;;
    --scheme)
      SCHEME="$2"
      shift 2
      ;;
    --bundle-id)
      BUNDLE_ID="$2"
      shift 2
      ;;
    --icon)
      ICON_SOURCE="$2"
      shift 2
      ;;
    --dist)
      DIST_DIR="$2"
      shift 2
      ;;
    --derived-data)
      DERIVED_DATA_DIR="$2"
      shift 2
      ;;
    --pkg)
      CREATE_PKG="true"
      shift
      ;;
    --universal)
      UNIVERSAL="true"
      shift
      ;;
    --github-repo)
      GITHUB_REPO="$2"
      GENERATE_CASK="true"
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

if [[ -z "${VERSION}" ]]; then
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    TAG="$(git describe --tags --abbrev=0 2>/dev/null || true)"
    if [[ -n "${TAG}" ]]; then
      VERSION="${TAG#v}"
    fi
  fi
fi

VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-$(date -u +%Y%m%d%H%M%S)}"
DERIVED_DATA_DIR="${DERIVED_DATA_DIR:-${DIST_DIR}/DerivedData}"

for cmd in xcodebuild ditto shasum awk; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Missing required command: ${cmd}" >&2
    exit 1
  fi
done

mkdir -p "${DIST_DIR}"
rm -rf "${DIST_DIR:?}/${APP_NAME}.app"

echo "==> Building release app"
HOST_ARCH="$(uname -m)"
BUILD_CMD=(
  xcodebuild
  -project "${PROJECT_PATH}"
  -scheme "${SCHEME}"
  -configuration Release
  -derivedDataPath "${DERIVED_DATA_DIR}"
)
if [[ "${UNIVERSAL}" == "true" ]]; then
  BUILD_CMD+=(-destination "generic/platform=macOS")
  BUILD_CMD+=(ONLY_ACTIVE_ARCH=NO)
  BUILD_CMD+=("ARCHS=arm64 x86_64")
else
  BUILD_CMD+=(-destination "platform=macOS,arch=${HOST_ARCH}")
  BUILD_CMD+=(ONLY_ACTIVE_ARCH=YES)
fi
BUILD_CMD+=(build)
"${BUILD_CMD[@]}"

BUILT_APP="${DERIVED_DATA_DIR}/Build/Products/Release/${APP_NAME}.app"
APP_PATH="${DIST_DIR}/${APP_NAME}.app"
if [[ ! -d "${BUILT_APP}" ]]; then
  echo "Missing built app at ${BUILT_APP}" >&2
  exit 1
fi

echo "==> Copying app bundle to ${APP_PATH}"
ditto "${BUILT_APP}" "${APP_PATH}"

INFO_PLIST="${APP_PATH}/Contents/Info.plist"
upsert_plist_string "${INFO_PLIST}" "CFBundleIdentifier" "${BUNDLE_ID}"
upsert_plist_string "${INFO_PLIST}" "CFBundleShortVersionString" "${VERSION}"
upsert_plist_string "${INFO_PLIST}" "CFBundleVersion" "${BUILD_NUMBER}"
upsert_plist_string "${INFO_PLIST}" "LSMinimumSystemVersion" "${MIN_MACOS}"

if [[ -f "${ICON_SOURCE}" ]] && command -v sips >/dev/null 2>&1 && command -v iconutil >/dev/null 2>&1; then
  echo "==> Generating AppIcon.icns from ${ICON_SOURCE}"
  ICONSET_DIR="${DIST_DIR}/AppIcon.iconset"
  RESOURCES_PATH="${APP_PATH}/Contents/Resources"
  rm -rf "${ICONSET_DIR}"
  mkdir -p "${ICONSET_DIR}" "${RESOURCES_PATH}"

  sips -z 16 16 "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_16x16.png" >/dev/null
  sips -z 32 32 "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_16x16@2x.png" >/dev/null
  sips -z 32 32 "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_32x32.png" >/dev/null
  sips -z 64 64 "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_32x32@2x.png" >/dev/null
  sips -z 128 128 "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_128x128.png" >/dev/null
  sips -z 256 256 "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_128x128@2x.png" >/dev/null
  sips -z 256 256 "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_256x256.png" >/dev/null
  sips -z 512 512 "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_256x256@2x.png" >/dev/null
  sips -z 512 512 "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_512x512.png" >/dev/null
  sips -z 1024 1024 "${ICON_SOURCE}" --out "${ICONSET_DIR}/icon_512x512@2x.png" >/dev/null

  iconutil -c icns "${ICONSET_DIR}" -o "${RESOURCES_PATH}/AppIcon.icns"
  upsert_plist_string "${INFO_PLIST}" "CFBundleIconFile" "AppIcon"
  rm -rf "${ICONSET_DIR}"
else
  echo "==> Skipping icon conversion (missing icon, sips, or iconutil)"
fi

if command -v codesign >/dev/null 2>&1; then
  echo "==> Applying ad-hoc signature"
  codesign --force --deep --sign - "${APP_PATH}"
fi

ZIP_PATH="${DIST_DIR}/${APP_NAME}-${VERSION}.app.zip"
rm -f "${ZIP_PATH}"
echo "==> Creating ZIP package"
ditto -c -k --sequesterRsrc --keepParent "${APP_PATH}" "${ZIP_PATH}"

CHECKSUMS_PATH="${DIST_DIR}/checksums.txt"
SHA_ZIP="$(shasum -a 256 "${ZIP_PATH}" | awk '{print $1}')"
printf "%s  %s\n" "${SHA_ZIP}" "$(basename "${ZIP_PATH}")" > "${CHECKSUMS_PATH}"

if [[ "${CREATE_PKG}" == "true" ]]; then
  if ! command -v pkgbuild >/dev/null 2>&1; then
    echo "pkgbuild is required for --pkg" >&2
    exit 1
  fi

  echo "==> Creating PKG installer"
  PKG_ROOT="${DIST_DIR}/pkgroot"
  mkdir -p "${PKG_ROOT}/Applications"
  rm -rf "${PKG_ROOT}/Applications/${APP_NAME}.app"
  ditto "${APP_PATH}" "${PKG_ROOT}/Applications/${APP_NAME}.app"

  PKG_PATH="${DIST_DIR}/${APP_NAME}-${VERSION}.pkg"
  rm -f "${PKG_PATH}"
  pkgbuild \
    --root "${PKG_ROOT}" \
    --identifier "${BUNDLE_ID}" \
    --version "${VERSION}" \
    --install-location "/" \
    "${PKG_PATH}"

  SHA_PKG="$(shasum -a 256 "${PKG_PATH}" | awk '{print $1}')"
  printf "%s  %s\n" "${SHA_PKG}" "$(basename "${PKG_PATH}")" >> "${CHECKSUMS_PATH}"
  rm -rf "${PKG_ROOT}"
fi

if [[ "${GENERATE_CASK}" == "true" ]]; then
  if [[ -z "${GITHUB_REPO}" ]]; then
    echo "--github-repo is required to generate cask" >&2
    exit 1
  fi

  echo "==> Generating Homebrew cask"
  ./scripts/generate-homebrew-cask.sh \
    --version "${VERSION}" \
    --sha256 "${SHA_ZIP}" \
    --repo "${GITHUB_REPO}"
fi

cat <<SUMMARY

Release artifacts created:
- ${APP_PATH}
- ${ZIP_PATH}
- ${CHECKSUMS_PATH}

Version: ${VERSION}
Build number: ${BUILD_NUMBER}
ZIP SHA256: ${SHA_ZIP}
SUMMARY
