#!/usr/bin/env bash
set -euo pipefail

APP_NAME="LingoThing"
PROJECT_PATH="LingoThing.xcodeproj"
SCHEME="LingoThing"
ICON_SOURCE="icons/install.png"
DIST_DIR="dist"
CASK_PATH="Casks/lingothing.rb"
NOTARY_PROFILE="lingothing-notary"
VERSION=""
REPO=""
REMOTE=""
IDENTITY=""

RUN_TESTS="true"
CREATE_TAG="false"
PUSH_TAG="false"
UPLOAD_RELEASE="false"
ALLOW_DIRTY="false"

usage() {
  cat <<USAGE
Usage: $0 --version <semver> [options]

Required:
  --version <semver>               Release version, e.g. 0.1.3

Options:
  --repo <owner/repo>              GitHub repo (default: inferred from git remote)
  --remote <name>                  Git remote name for pushing tags (default: inferred)
  --project <path>                 Xcode project path (default: LingoThing.xcodeproj)
  --scheme <name>                  Xcode scheme (default: LingoThing)
  --icon <path>                    Source PNG icon path (default: icons/install.png)
  --identity <codesign identity>   Developer ID Application identity name or SHA
  --notary-profile <profile>       notarytool keychain profile (default: lingothing-notary)
  --dist <path>                    Output directory (default: dist)
  --cask-path <path>               Cask file path (default: Casks/lingothing.rb)
  --skip-tests                     Skip test step
  --create-tag                     Create git tag v<version>
  --push-tag                       Push tag to selected remote (implies --create-tag)
  --upload-release                 Create/update GitHub release via gh CLI
  --allow-dirty                    Allow running with uncommitted changes
  --help                           Show this help

What this script does:
  1) Runs tests if XCTest targets exist (optional)
  2) Builds app bundle with package-macos-app.sh
  3) Signs with Developer ID Application
  4) Notarizes and staples app
  5) Re-zips stapled app and computes SHA256
  6) Regenerates Homebrew cask with version + SHA
  7) Optionally tags and uploads release assets
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      VERSION="$2"
      shift 2
      ;;
    --repo)
      REPO="$2"
      shift 2
      ;;
    --remote)
      REMOTE="$2"
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
    --icon)
      ICON_SOURCE="$2"
      shift 2
      ;;
    --identity)
      IDENTITY="$2"
      shift 2
      ;;
    --notary-profile)
      NOTARY_PROFILE="$2"
      shift 2
      ;;
    --dist)
      DIST_DIR="$2"
      shift 2
      ;;
    --cask-path)
      CASK_PATH="$2"
      shift 2
      ;;
    --skip-tests)
      RUN_TESTS="false"
      shift
      ;;
    --create-tag)
      CREATE_TAG="true"
      shift
      ;;
    --push-tag)
      CREATE_TAG="true"
      PUSH_TAG="true"
      shift
      ;;
    --upload-release)
      UPLOAD_RELEASE="true"
      shift
      ;;
    --allow-dirty)
      ALLOW_DIRTY="true"
      shift
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
  echo "Missing required argument: --version" >&2
  usage
  exit 1
fi

for cmd in xcodebuild codesign xcrun ditto shasum awk sed grep security; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Missing required command: ${cmd}" >&2
    exit 1
  fi
done

if [[ "${UPLOAD_RELEASE}" == "true" ]] && ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI is required for --upload-release. Install with: brew install gh" >&2
  exit 1
fi

if [[ "${ALLOW_DIRTY}" != "true" ]]; then
  if [[ -n "$(git status --porcelain)" ]]; then
    echo "Working tree is not clean. Commit/stash changes or use --allow-dirty." >&2
    exit 1
  fi
fi

infer_remote_name() {
  if git remote get-url origin >/dev/null 2>&1; then
    echo "origin"
    return 0
  fi
  if git remote get-url lingothing >/dev/null 2>&1; then
    echo "lingothing"
    return 0
  fi
  git remote | head -n1
}

infer_repo_from_remote() {
  local remote_name="$1"
  local remote_url
  remote_url="$(git remote get-url "${remote_name}" 2>/dev/null || true)"
  if [[ -z "${remote_url}" ]]; then
    return 1
  fi

  echo "${remote_url}" | sed -E \
    -e 's#^git@github.com:##' \
    -e 's#^https://github.com/##' \
    -e 's#\.git$##'
}

if [[ -z "${REPO}" ]]; then
  if [[ -z "${REMOTE}" ]]; then
    REMOTE="$(infer_remote_name || true)"
  fi
  REPO="$(infer_repo_from_remote "${REMOTE}" || true)"
fi

if [[ -z "${REPO}" ]]; then
  echo "Could not infer GitHub repo. Pass --repo <owner/repo>." >&2
  exit 1
fi

if [[ -z "${REMOTE}" ]]; then
  REMOTE="$(infer_remote_name || true)"
fi

if [[ -z "${REMOTE}" ]]; then
  echo "Could not infer git remote. Pass --remote <name>." >&2
  exit 1
fi

if [[ -z "${IDENTITY}" ]]; then
  IDENTITY="$(security find-identity -v -p codesigning | awk -F\" '/Developer ID Application/ {print $2; exit}')"
fi

if [[ -z "${IDENTITY}" ]]; then
  echo "No Developer ID Application identity found. Run:" >&2
  echo "  security find-identity -v -p codesigning | grep \"Developer ID Application\"" >&2
  exit 1
fi

APP_PATH="${DIST_DIR}/${APP_NAME}.app"
ZIP_PATH="${DIST_DIR}/${APP_NAME}-${VERSION}.app.zip"
CHECKSUMS_PATH="${DIST_DIR}/checksums.txt"
TAG="v${VERSION}"
SIGNING_ENTITLEMENTS_PATH="${DIST_DIR}/${APP_NAME}.release-signing-entitlements.plist"

echo "==> Release ${VERSION}"
echo "Repo: ${REPO}"
echo "Remote: ${REMOTE}"
echo "Project: ${PROJECT_PATH}"
echo "Scheme: ${SCHEME}"
echo "Signing identity: ${IDENTITY}"
echo "Notary profile: ${NOTARY_PROFILE}"

if [[ "${RUN_TESTS}" == "true" ]]; then
  if grep -Eq 'product-type\.bundle\.(unit-test|ui-testing)' "${PROJECT_PATH}/project.pbxproj"; then
    echo "==> Running tests"
    xcodebuild -project "${PROJECT_PATH}" -scheme "${SCHEME}" -destination "platform=macOS" test
  else
    echo "==> No XCTest targets found; skipping tests"
  fi
fi

echo "==> Building app bundle"
./scripts/package-macos-app.sh \
  --version "${VERSION}" \
  --project "${PROJECT_PATH}" \
  --scheme "${SCHEME}" \
  --icon "${ICON_SOURCE}" \
  --dist "${DIST_DIR}"

if [[ ! -d "${APP_PATH}" ]]; then
  echo "Missing app bundle: ${APP_PATH}" >&2
  exit 1
fi

echo "==> Signing app"
rm -f "${SIGNING_ENTITLEMENTS_PATH}"
codesign -d --entitlements - --xml "${APP_PATH}" 2>&1 \
  | awk 'BEGIN{printing=0} /^<\?xml/{printing=1} printing{print}' > "${SIGNING_ENTITLEMENTS_PATH}"
if [[ -s "${SIGNING_ENTITLEMENTS_PATH}" ]]; then
  echo "==> Preserving embedded entitlements for Developer ID signature"
  codesign --force --deep --options runtime --timestamp --sign "${IDENTITY}" --entitlements "${SIGNING_ENTITLEMENTS_PATH}" "${APP_PATH}"
else
  echo "==> No embedded entitlements detected; signing without explicit entitlements"
  codesign --force --deep --options runtime --timestamp --sign "${IDENTITY}" "${APP_PATH}"
fi
codesign --verify --deep --strict --verbose=2 "${APP_PATH}"
if ! codesign -d --entitlements - --xml "${APP_PATH}" 2>&1 | grep -q "com.apple.security.device.audio-input"; then
  echo "Missing com.apple.security.device.audio-input entitlement after release signing." >&2
  exit 1
fi

echo "==> Creating signed ZIP for notarization"
rm -f "${ZIP_PATH}"
ditto -c -k --sequesterRsrc --keepParent "${APP_PATH}" "${ZIP_PATH}"

echo "==> Submitting notarization"
xcrun notarytool submit "${ZIP_PATH}" --keychain-profile "${NOTARY_PROFILE}" --wait

echo "==> Stapling notarization ticket"
xcrun stapler staple "${APP_PATH}"
xcrun stapler validate "${APP_PATH}"

echo "==> Gatekeeper verification"
spctl -a -vvv "${APP_PATH}" || true

echo "==> Repacking stapled app (final release artifact)"
rm -f "${ZIP_PATH}"
ditto -c -k --sequesterRsrc --keepParent "${APP_PATH}" "${ZIP_PATH}"
ZIP_SHA="$(shasum -a 256 "${ZIP_PATH}" | awk '{print $1}')"
printf "%s  %s\n" "${ZIP_SHA}" "$(basename "${ZIP_PATH}")" > "${CHECKSUMS_PATH}"
rm -f "${SIGNING_ENTITLEMENTS_PATH}"

echo "==> Updating Homebrew cask"
./scripts/generate-homebrew-cask.sh \
  --version "${VERSION}" \
  --sha256 "${ZIP_SHA}" \
  --repo "${REPO}" \
  --output "${CASK_PATH}"

if [[ "${CREATE_TAG}" == "true" ]]; then
  if git rev-parse -q --verify "refs/tags/${TAG}" >/dev/null; then
    echo "Tag ${TAG} already exists. Skipping tag creation."
  else
    echo "==> Creating git tag ${TAG}"
    git tag "${TAG}"
  fi
fi

if [[ "${PUSH_TAG}" == "true" ]]; then
  echo "==> Pushing tag ${TAG} to ${REMOTE}"
  git push "${REMOTE}" "${TAG}"
fi

if [[ "${UPLOAD_RELEASE}" == "true" ]]; then
  echo "==> Uploading release assets with gh"
  if gh release view "${TAG}" >/dev/null 2>&1; then
    gh release upload "${TAG}" "${ZIP_PATH}" --clobber
    gh release upload "${TAG}" "${CHECKSUMS_PATH}" --clobber
  else
    gh release create "${TAG}" "${ZIP_PATH}" "${CHECKSUMS_PATH}" \
      --title "${TAG}" \
      --notes "LingoThing ${TAG}"
  fi
fi

cat <<SUMMARY

Release pipeline complete.

Version: ${VERSION}
ZIP: ${ZIP_PATH}
ZIP SHA256: ${ZIP_SHA}
Cask updated: ${CASK_PATH}

Next:
1. git add ${CASK_PATH} ${CHECKSUMS_PATH}
2. git commit -m "release: v${VERSION}"
3. git push origin main
4. Ensure GitHub release ${TAG} includes $(basename "${ZIP_PATH}")
SUMMARY
