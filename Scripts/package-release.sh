#!/bin/bash
#
# Build, sign and package a Clicklet release.
#
#   Scripts/package-release.sh [--development] [--skip-notarize] [--version 1.0.0]
#
# Two signing modes:
#
#   developer-id   Needs a paid Apple Developer Program membership and a
#                  "Developer ID Application" certificate. The app is exported
#                  for distribution and notarized, so anyone can open it.
#                  Chosen automatically when such a certificate is installed.
#
#   development    Signs with the local "Apple Development" certificate and
#                  skips notarization. The build cannot be exported (that needs
#                  a distribution certificate), so it is taken straight out of
#                  the archive. Every user has to approve the app once in
#                  System Settings > Privacy & Security. Forced by
#                  --development, and used automatically when no Developer ID
#                  certificate is present.
#
# Environment:
#   TEAM_ID          developer team id             (default: the project's)
#   NOTARY_PROFILE   notarytool keychain profile  (default: clicklet-notary)
#   EXPORT_OPTIONS   path to ExportOptions.plist  (default: Scripts/ExportOptions.plist)
#
# One-time setup for the notarized mode:
#   xcrun notarytool store-credentials clicklet-notary \
#       --apple-id <your apple id> --team-id <TEAM_ID> \
#       --password <app-specific password>
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

TEAM_ID="${TEAM_ID:-6T9RSL7KL6}"
NOTARY_PROFILE="${NOTARY_PROFILE:-clicklet-notary}"
EXPORT_OPTIONS="${EXPORT_OPTIONS:-Scripts/ExportOptions.plist}"

FORCE_DEVELOPMENT=0
SKIP_NOTARIZE=0
REQUESTED_VERSION=""
while [ $# -gt 0 ]; do
    case "$1" in
        --development) FORCE_DEVELOPMENT=1 ;;
        --skip-notarize) SKIP_NOTARIZE=1 ;;
        --version) REQUESTED_VERSION="${2:?--version needs a value}"; shift ;;
        -h|--help) sed -n '3,32p' "$0"; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

# ---------------------------------------------------------------- preflight
PROJECT_VERSION="$(awk -F'"' '/^[[:space:]]*MARKETING_VERSION:/ { print $2; exit }' project.yml)"
if [ -z "$PROJECT_VERSION" ]; then
    echo "error: could not read MARKETING_VERSION from project.yml" >&2
    exit 1
fi
VERSION="${REQUESTED_VERSION:-$PROJECT_VERSION}"
if [ "$VERSION" != "$PROJECT_VERSION" ]; then
    echo "error: --version $VERSION does not match MARKETING_VERSION $PROJECT_VERSION in project.yml" >&2
    exit 1
fi

for tool in xcodegen xcodebuild xcrun hdiutil shasum security osascript; do
    command -v "$tool" >/dev/null || { echo "error: $tool not found" >&2; exit 1; }
done

# Matched with a shell case, not `| grep -q`: under `set -o pipefail` an early
# exit from grep can make the pipeline report a failure and send the script down
# the development path even though a Developer ID identity is installed.
keychain_identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"
case "$keychain_identities" in
    *"Developer ID Application"*) HAVE_DEVELOPER_ID=1 ;;
    *) HAVE_DEVELOPER_ID=0 ;;
esac

SIGNING="developer-id"
if [ "$FORCE_DEVELOPMENT" = "1" ] || [ "$HAVE_DEVELOPER_ID" = "0" ]; then
    SIGNING="development"
fi

if [ "$SIGNING" = "developer-id" ]; then
    [ -f "$EXPORT_OPTIONS" ] || { echo "error: $EXPORT_OPTIONS not found" >&2; exit 1; }
    if [ "$SKIP_NOTARIZE" = "0" ] && ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
        echo "error: notarytool profile '$NOTARY_PROFILE' is missing or unusable." >&2
        echo "       See the setup note at the top of this script." >&2
        exit 1
    fi
elif [ "$FORCE_DEVELOPMENT" = "0" ]; then
    echo "note: no 'Developer ID Application' identity in the keychain, so falling" >&2
    echo "      back to a development-signed, un-notarized build." >&2
fi

BUILD_DIR="$REPO_ROOT/.build"
ARCHIVE="$BUILD_DIR/Clicklet.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
STAGING="$BUILD_DIR/dmg"
DMG="$BUILD_DIR/Clicklet-$VERSION.dmg"

echo "==> Clicklet $VERSION  (team $TEAM_ID, $SIGNING signing)"
rm -rf "$ARCHIVE" "$EXPORT_DIR" "$STAGING" "$DMG" "$DMG.sha256"

# ------------------------------------------------------------ build archive
echo "==> xcodegen generate"
xcodegen generate

echo "==> xcodebuild archive"
xcodebuild -project Clicklet.xcodeproj -scheme Clicklet -configuration Release \
    -derivedDataPath "$BUILD_DIR/dd" -archivePath "$ARCHIVE" \
    archive -allowProvisioningUpdates

if [ "$SIGNING" = "developer-id" ]; then
    echo "==> xcodebuild -exportArchive"
    xcodebuild -exportArchive -archivePath "$ARCHIVE" \
        -exportOptionsPlist "$EXPORT_OPTIONS" -exportPath "$EXPORT_DIR"
    APP="$EXPORT_DIR/Clicklet.app"
else
    # A development-signed archive cannot be exported for distribution, and it
    # does not need to be: Products/Applications already holds the signed app.
    echo "==> taking the app straight out of the archive"
    APP="$ARCHIVE/Products/Applications/Clicklet.app"
fi

# --------------------------------------------------------- inspect the app
echo "==> verifying $APP"

bundle_version="$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")"
[ "$bundle_version" = "$VERSION" ] || {
    echo "error: bundle reports $bundle_version, expected $VERSION" >&2; exit 1; }

echo -n "    architectures: "; lipo -archs "$APP/Contents/MacOS/Clicklet"

# codesign's output is captured before it is matched. Piping into `grep -q` would
# end the pipe as soon as grep matched, and with `set -o pipefail` the SIGPIPE
# codesign then takes makes the whole pipeline look like a failure -- which is how
# a correctly signed build gets reported as unsigned.
app_entitlements="$(codesign -d --entitlements :- "$APP" 2>/dev/null || true)"
case "$app_entitlements" in
    *get-task-allow*)
        echo "error: signed with get-task-allow; this is a debug build" >&2
        exit 1 ;;
esac

codesign --verify --deep --strict "$APP"

signing_info="$(codesign -dv --verbose=4 "$APP" 2>&1 || true)"
case "$signing_info" in
    *"TeamIdentifier=$TEAM_ID"*) ;;
    *)
        echo "error: app is not signed by team $TEAM_ID" >&2
        exit 1 ;;
esac

for nested in "$APP/Contents/PlugIns/"*.appex "$APP/Contents/XPCServices/"*.xpc; do
    [ -e "$nested" ] || continue
    codesign --verify --strict "$nested"
    echo "    signed: $(basename "$nested")"
done

# The sandboxed extension reaches the shared container through an App Group,
# which a distribution build has to authorise with an embedded profile. A local
# build can get away without one, so this is a warning rather than an error.
for target in "$APP" "$APP/Contents/PlugIns/"*.appex; do
    [ -e "$target" ] || continue
    target_entitlements="$(codesign -d --entitlements :- "$target" 2>/dev/null || true)"
    case "$target_entitlements" in
        *application-groups*)
            [ -f "$target/Contents/embedded.provisionprofile" ] ||
                echo "    note: $(basename "$target") has an App Group but no embedded profile" ;;
    esac
done

for resource in BuiltinTemplates BuiltinScripts; do
    [ -d "$APP/Contents/Resources/$resource" ] || {
        echo "error: $resource is missing from the app bundle" >&2; exit 1; }
done

# ----------------------------------------------------------------- make dmg
echo "==> building $DMG"
# make-dmg.sh stages the app, mounts a writable image, lets Finder lay the window
# out and converts the result. A plain `hdiutil create -srcfolder` cannot do that:
# the layout only reaches the image's .DS_Store while it is mounted.
"$REPO_ROOT/Scripts/make-dmg.sh" "$APP" "$DMG"

# ------------------------------------------------- notarize and staple
if [ "$SIGNING" = "development" ]; then
    echo
    echo "!! This DMG is signed with an Apple Development certificate and is NOT"
    echo "!! notarized. macOS will refuse to open it until each user approves it"
    echo "!! once: right-click the app, choose Open, then Open again -- or turn it"
    echo "!! on under System Settings > Privacy & Security."
    echo "!!"
    echo "!! The README has to say so, and the DMG must never be presented as a"
    echo "!! one-click install. Enrolling in the Apple Developer Program and"
    echo "!! installing a Developer ID certificate removes this step."
    echo
elif [ "$SKIP_NOTARIZE" = "1" ]; then
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
# The file name is written bare, so `shasum -a 256 -c` works for whoever
# downloads the two files side by side. An absolute path would only verify on
# the machine that built it.
( cd "$BUILD_DIR" && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256" )
cat "$DMG.sha256"

cat <<EOF

Done.

  1. Tag the commit this was built from:

       git tag -a v$VERSION -m "Clicklet $VERSION"
       git push origin v$VERSION

  2. Upload both assets to the GitHub release:

       $DMG
       $DMG.sha256

  3. Paste the release notes for v$VERSION (docs/RELEASING.md), and make sure
     the first-launch instructions still match how this build was signed.

EOF
