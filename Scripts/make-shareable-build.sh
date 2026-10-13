#!/bin/bash
#
# Produce a shareable build of AppDrop.
#
# Why this exists: a normal archive embeds the Xcode-managed *development*
# provisioning profile, whose ProvisionedDevices list only contains the Mac
# that produced it (and which expires after 7 days). Such a build refuses to
# launch on any other Mac ("应用程序“AppDrop”无法打开。"), even with Gatekeeper
# relaxed and quarantine removed.
#
# This script strips the embedded profiles and re-signs both bundles with the
# Apple Development certificate only (no profile), keeping the sandbox and
# App Group entitlements. The result launches on other Macs after either
# right-click → Open, or with Gatekeeper disabled, plus Full Disk Access for
# AppDrop and AppDrop Helper (personal-team signature → TCC-protected group
# container).
#
# Usage:
#   Scripts/make-shareable-build.sh <Release .app> <output .app> [signing identity]
#
# Example:
#   Scripts/make-shareable-build.sh \
#     /private/tmp/AppDrop-Release-DD/Build/Products/Release/AppDrop.app \
#     /private/tmp/AppDrop-shareable/AppDrop.app

set -euo pipefail

SOURCE_APP="${1:?usage: make-shareable-build.sh <Release .app> <output .app> [identity]}"
OUTPUT_APP="${2:?usage: make-shareable-build.sh <Release .app> <output .app> [identity]}"
IDENTITY="${3:-Apple Development: 3044465914@qq.com (8LS94292BG)}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_ENTITLEMENTS="$REPO_ROOT/AppDrop/AppDrop.entitlements"
HELPER_ENTITLEMENTS="$REPO_ROOT/AppDropHelper/AppDropHelper.entitlements"
HELPER_APP="$OUTPUT_APP/Contents/Library/LoginItems/AppDropHelper.app"

mkdir -p "$(dirname "$OUTPUT_APP")"
if [ -e "$OUTPUT_APP" ]; then
    mv "$OUTPUT_APP" "$OUTPUT_APP.previous-$(date +%s)"
fi

ditto --norsrc --noextattr "$SOURCE_APP" "$OUTPUT_APP"
xattr -cr "$OUTPUT_APP" || true

# Remove the device-locked development profiles from both bundles.
find "$OUTPUT_APP" -name "embedded.provisionprofile" -delete

# Re-sign inside-out: nested helper first, then the main app.
codesign --force --sign "$IDENTITY" --timestamp=none \
    --entitlements "$HELPER_ENTITLEMENTS" "$HELPER_APP"
codesign --force --sign "$IDENTITY" --timestamp=none \
    --entitlements "$APP_ENTITLEMENTS" "$OUTPUT_APP"

codesign --verify --deep --strict --verbose=2 "$OUTPUT_APP"

if find "$OUTPUT_APP" -name "embedded.provisionprofile" | grep -q .; then
    echo "error: a provisioning profile is still embedded" >&2
    exit 1
fi

echo "shareable build written to: $OUTPUT_APP"
echo "(no embedded provisioning profile; signed by '$IDENTITY')"
