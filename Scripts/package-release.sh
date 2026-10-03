#!/bin/bash
#
# Build, sign, notarize and package a RightKit release.
#
#   Scripts/package-release.sh [--skip-notarize] [--version 1.0.0]
#
# Environment:
#   TEAM_ID          developer team id             (default: the project's)
#   NOTARY_PROFILE   notarytool keychain profile  (default: rightkit-notary)
#   EXPORT_OPTIONS   path to ExportOptions.plist  (default: Scripts/ExportOptions.plist)
#
# One-time setup:
#   1. A "Developer ID Application" certificate in the login keychain.
#   2. A notarytool credential profile:
#        xcrun notarytool store-credentials rightkit-notary \
#            --apple-id <your apple id> --team-id <TEAM_ID> \
#            --password <app-specific password>
#
# The version comes from MARKETING_VERSION in project.yml; --version only
# exists to assert that a release tag and the project agree.
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

TEAM_ID="${TEAM_ID:-6T9RSL7KL6}"
NOTARY_PROFILE="${NOTARY_PROFILE:-rightkit-notary}"
EXPORT_OPTIONS="${EXPORT_OPTIONS:-Scripts/ExportOptions.plist}"

SKIP_NOTARIZE=0
REQUESTED_VERSION=""
while [ $# -gt 0 ]; do
    case "$1" in
        --skip-notarize) SKIP_NOTARIZE=1 ;;
        --version) REQUESTED_VERSION="${2:?--version needs a value}"; shift ;;
        -h|--help) sed -n '3,19p' "$0"; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

# ---------------------------------------------------------------- preflight
PROJECT_VERSION="$(sed -nE 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*"(.*)".*/\1/p' project.yml | head -1)"
if [ -z "$PROJECT_VERSION" ]; then
    echo "error: could not read MARKETING_VERSION from project.yml" >&2
    exit 1
fi
VERSION="${REQUESTED_VERSION:-$PROJECT_VERSION}"
if [ "$VERSION" != "$PROJECT_VERSION" ]; then
    echo "error: --version $VERSION does not match MARKETING_VERSION $PROJECT_VERSION in project.yml" >&2
    exit 1
fi

for tool in xcodegen xcodebuild xcrun hdiutil shasum security; do
    command -v "$tool" >/dev/null || { echo "error: $tool not found" >&2; exit 1; }
done
[ -f "$EXPORT_OPTIONS" ] || { echo "error: $EXPORT_OPTIONS not found" >&2; exit 1; }

if ! security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
    echo "error: no 'Developer ID Application' identity in the keychain." >&2
    echo "       A development identity cannot be notarized. Create the certificate" >&2
    echo "       in the Apple Developer portal, install it, then run this again." >&2
    exit 1
fi

if [ "$SKIP_NOTARIZE" = "0" ] && ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    echo "error: notarytool profile '$NOTARY_PROFILE' is missing or unusable." >&2
    echo "       See the setup note at the top of this script." >&2
    exit 1
fi

BUILD_DIR="$REPO_ROOT/.build"
ARCHIVE="$BUILD_DIR/RightKit.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
STAGING="$BUILD_DIR/dmg"
APP="$EXPORT_DIR/RightKit.app"
DMG="$BUILD_DIR/RightKit-$VERSION.dmg"

echo "==> RightKit $VERSION  (team $TEAM_ID)"
rm -rf "$ARCHIVE" "$EXPORT_DIR" "$STAGING" "$DMG" "$DMG.sha256"

# ------------------------------------------------------------ build archive
echo "==> xcodegen generate"
xcodegen generate

echo "==> xcodebuild archive"
xcodebuild -project RightKit.xcodeproj -scheme RightKit -configuration Release \
    -derivedDataPath "$BUILD_DIR/dd" -archivePath "$ARCHIVE" \
    archive -allowProvisioningUpdates

echo "==> xcodebuild -exportArchive"
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
    -exportOptionsPlist "$EXPORT_OPTIONS" -exportPath "$EXPORT_DIR"

# --------------------------------------------------------- inspect the app
echo "==> verifying $APP"

bundle_version="$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")"
[ "$bundle_version" = "$VERSION" ] || {
    echo "error: bundle reports $bundle_version, expected $VERSION" >&2; exit 1; }

echo -n "    architectures: "; lipo -archs "$APP/Contents/MacOS/RightKit"

# A release build must not carry the debugging entitlement, or notarization
# and the resulting Gatekeeper verdict both go wrong.
if codesign -d --entitlements :- "$APP" 2>/dev/null | grep -q "get-task-allow"; then
    echo "error: signed with get-task-allow; this is a development build" >&2
    exit 1
fi

codesign --verify --deep --strict "$APP"
codesign -dv --verbose=4 "$APP" 2>&1 | grep -q "TeamIdentifier=$TEAM_ID" || {
    echo "error: app is not signed by team $TEAM_ID" >&2; exit 1; }

# The extension and the XPC service ship inside the app; a broken signature
# there is what makes the menu silently stop working on someone else's Mac.
for nested in "$APP/Contents/PlugIns/"*.appex "$APP/Contents/XPCServices/"*.xpc; do
    [ -e "$nested" ] || continue
    codesign --verify --strict "$nested"
    echo "    signed: $(basename "$nested")"
done

# The sandboxed extension reaches the shared container through an App Group, and
# on a Developer ID build that group has to be authorised by an embedded
# profile. Its absence does not fail a local build, but it does break the
# container on someone else's Mac, so say so loudly.
for target in "$APP" "$APP/Contents/PlugIns/"*.appex; do
    [ -e "$target" ] || continue
    if codesign -d --entitlements :- "$target" 2>/dev/null | grep -q "application-groups" &&
       [ ! -f "$target/Contents/embedded.provisionprofile" ]; then
        echo "warning: $(basename "$target") declares an App Group but has no embedded provisioning profile" >&2
    fi
done

for resource in BuiltinTemplates BuiltinScripts; do
    [ -d "$APP/Contents/Resources/$resource" ] || {
        echo "error: $resource is missing from the app bundle" >&2; exit 1; }
done

# ----------------------------------------------------------------- make dmg
echo "==> building $DMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "RightKit" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null

# ------------------------------------------------- notarize and staple
if [ "$SKIP_NOTARIZE" = "1" ]; then
    echo "==> skipping notarization (--skip-notarize): $DMG is NOT distributable"
else
    echo "==> notarytool submit (this usually takes a few minutes)"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    echo "==> stapler"
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
    echo -n "    Gatekeeper: "
    spctl -a -vvv -t open --context context:primary-signature "$DMG" 2>&1 | tail -1
fi

# --------------------------------------------------------------- checksums
echo "==> checksums"
shasum -a 256 "$DMG" | tee "$DMG.sha256"

cat <<EOF

Done.

  1. Create the release on GitHub with the commit this was built from:

       git tag -a v$VERSION -m "RightKit $VERSION"
       git push origin v$VERSION

  2. Upload both assets:

       $DMG
       $DMG.sha256

  3. Paste the release notes for v$VERSION (see docs/RELEASING.md).

EOF
