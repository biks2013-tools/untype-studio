#!/usr/bin/env bash
# scripts/release.sh — build, sign, notarize and package untype studio for a
# GitHub release, and write its Homebrew cask.
#
#   bash scripts/release.sh
#
# Required environment (no defaults — a release is always Developer ID
# signed and notarized):
#   UNTYPE_STUDIO_SIGN_IDENTITY  Developer ID Application identity, by SHA-1
#                                (two identities share the name). List them:
#                                security find-identity -v -p codesigning
#   NOTARY_PROFILE               notarytool keychain profile
#                                (xcrun notarytool store-credentials <name>).
#
# Output in dist/release/: untype-studio-<version>.zip, a stapled .dmg and
# SHA256SUMS; and homebrew-tap/Casks/untype-studio.rb. Publishing (tag,
# GitHub release, tap) is described in docs/tools/untype-studio.md, "Releasing".
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
PRODUCT="untype-studio"
PLIST="Resources/UntypeStudio-Info.plist"
REPO="biks2013-tools/untype-studio"
TAP_NAME="biks2013-tools/untype"

[[ -n "${UNTYPE_STUDIO_SIGN_IDENTITY:-}" ]] || { echo "error: UNTYPE_STUDIO_SIGN_IDENTITY is not set (Developer ID Application SHA-1)" >&2; exit 1; }
[[ -n "${NOTARY_PROFILE:-}" ]] || { echo "error: NOTARY_PROFILE is not set (a release must be notarized)" >&2; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST")"
OUT="$ROOT/dist/release"
ZIP="$OUT/$PRODUCT-$VERSION.zip"
DMG="$OUT/$PRODUCT-$VERSION.dmg"
CASK="$ROOT/homebrew-tap/Casks/$PRODUCT.rb"
TAG="v$VERSION"
echo "=== Releasing $PRODUCT $VERSION ($BUNDLE_ID) ==="

# 1. Tests. Anything failing that is not in scripts/release-known-failures.txt stops the release.
LOG="$(mktemp)"
swift test > "$LOG" 2>&1 || true
FAILED="$( { sed -n 's/^✘ Test "\(.*\)" failed after.*/\1/p' "$LOG"; sed -n "s/^Test Case '\(.*\)' failed.*/\1/p" "$LOG"; } | sort -u)"
UNEXPECTED="$(grep -vxF -f <(grep -v '^#' scripts/release-known-failures.txt) <<<"$FAILED" || true)"
if ! grep -qE "Test run with [0-9]+ tests|Executed [0-9]+ tests" "$LOG"; then
  echo "error: the tests did not run:" >&2; tail -20 "$LOG" >&2; exit 1
fi
if [[ -n "$UNEXPECTED" ]]; then
  echo "error: tests failing that are not known failures:" >&2; echo "$UNEXPECTED" >&2; exit 1
fi
echo "tests: no new failures ($(grep -c . <<<"$FAILED" || true) known)"

rm -rf "$OUT"; mkdir -p "$OUT"
notarize() { xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait | tee /dev/stderr | grep "status: Accepted" >/dev/null; }

APP="$ROOT/dist/$PRODUCT.app"
# 2. Release build, hardened runtime, Developer ID.
CODESIGN_IDENTITY="$UNTYPE_STUDIO_SIGN_IDENTITY" bash "scripts/package-$PRODUCT-app.sh"
codesign --verify --strict --verbose=2 "$APP"
SIG="$(codesign -dvv "$APP" 2>&1)"
[[ "$SIG" == *"Authority=Developer ID Application"* ]] || { echo "error: $APP is not Developer ID signed" >&2; exit 1; }
[[ "$SIG" =~ flags=0x[0-9a-f]+\(runtime\) ]] || { echo "error: $APP lacks the hardened runtime" >&2; exit 1; }
# 3. Zip → notarize → staple → zip again.
make_zip() { rm -f "$ZIP"; ditto -c -k --norsrc --keepParent "$APP" "$ZIP"; }
make_zip; notarize "$ZIP"
xcrun stapler staple "$APP"; xcrun stapler validate "$APP"
make_zip
spctl --assess --type execute --verbose=2 "$APP"
# 4. Drag-to-Applications disk image, signed, notarized, stapled.
STAGE="$ROOT/dist/dmg-root"; rm -rf "$STAGE"; mkdir -p "$STAGE"
ditto "$APP" "$STAGE/$PRODUCT.app"
ln -s /Applications "$STAGE/Applications"
cp "packaging/$PRODUCT/INSTALL.txt" "$STAGE/INSTALL.txt"
hdiutil create -volname "$PRODUCT $VERSION" -srcfolder "$STAGE" -ov -format UDZO -quiet "$DMG"
rm -rf "$STAGE"
codesign --force --timestamp --sign "$UNTYPE_STUDIO_SIGN_IDENTITY" "$DMG"
notarize "$DMG"
xcrun stapler staple "$DMG"; xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
(cd "$OUT" && shasum -a 256 "$(basename "$ZIP")" "$(basename "$DMG")" > SHA256SUMS)
SHA="$(shasum -a 256 "$ZIP" | awk '{print $1}')"

# 5. Homebrew cask for this version.
mkdir -p "$(dirname "$CASK")"
cat > "$CASK" <<CASKEOF
cask "untype-studio" do
  version "$VERSION"
  sha256 "$SHA"

  url "https://github.com/$REPO/releases/download/v#{version}/$PRODUCT-#{version}.zip"
  name "untype studio"
  desc "Explore recordings: transcripts, playback, cuts, Q&A and minutes"
  homepage "https://github.com/$REPO"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :tahoe

  app "untype-studio.app"

  uninstall quit: "$BUNDLE_ID"

  zap trash: [
    "~/Library/Preferences/$BUNDLE_ID.plist",
    "~/Library/Saved Application State/$BUNDLE_ID.savedState",
  ]

  caveats <<~EOS
    untype studio opens the recordings ntakker saved (NTAKKER_RECORDINGS_DIR).
    It reads ntakker's settings file, ~/.tool-agents/ntakker/.env
    (Ask provider, keys, echo filter).
  EOS
end
CASKEOF

echo ""
echo "=== $PRODUCT $VERSION packaged ==="
echo "Archives:   $OUT"
echo "Zip SHA256: $SHA"
echo "Cask:       $CASK"
echo "Next: tag $TAG, create the GitHub release on $REPO with the files in $OUT, copy the cask to the $TAP_NAME tap."
