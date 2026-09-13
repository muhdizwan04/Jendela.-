#!/bin/zsh
#
# Builds, signs, notarises and packages Jendela. for distribution outside the
# App Store.
#
#   ./Support/release.sh --check     preflight only, changes nothing
#   ./Support/release.sh             full release
#
# Everything that can be verified before the slow steps is verified first: a
# notarisation that fails after a four-minute upload because of a missing
# entitlement wastes far more time than the check costs.

set -euo pipefail

HERE="${0:A:h}"
ROOT="${HERE:h}"
BUILD="/tmp/jendela-release"
DIST="$ROOT/dist"
CHECK_ONLY=0
[[ "${1:-}" == "--check" ]] && CHECK_ONLY=1

info()  { print -P "%F{cyan}▸%f $*" }
ok()    { print -P "%F{green}✓%f $*" }
warn()  { print -P "%F{yellow}!%f $*" }
fail()  { print -P "%F{red}✗%f $*"; exit 1 }

# ---------------------------------------------------------------- configuration
if [[ -f "$HERE/release.env" ]]; then
  source "$HERE/release.env"
else
  warn "Support/release.env not found — copy release.env.example and fill it in"
fi
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
DOWNLOAD_BASE="${DOWNLOAD_BASE:-https://example.invalid/downloads}"

# ------------------------------------------------------------------- preflight
info "Preflight"

command -v xcodebuild >/dev/null || fail "xcodebuild not found"
command -v xcrun >/dev/null || fail "xcrun not found"
ok "Xcode tools present"

if [[ -z "$SIGN_IDENTITY" ]]; then
  warn "SIGN_IDENTITY is not set — cannot sign or notarise"
  HAVE_IDENTITY=0
elif security find-identity -v -p codesigning | grep -qF "$SIGN_IDENTITY"; then
  ok "Signing identity found"
  HAVE_IDENTITY=1
else
  warn "Signing identity not in the keychain: $SIGN_IDENTITY"
  HAVE_IDENTITY=0
fi

# A Developer ID certificate is the one Gatekeeper accepts for downloads.
if [[ $HAVE_IDENTITY == 1 && "$SIGN_IDENTITY" != Developer\ ID\ Application* ]]; then
  warn "That is not a Developer ID Application certificate."
  warn "Apple Development certificates cannot be notarised; downloads will be blocked."
fi

if [[ -n "$NOTARY_PROFILE" ]] && xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  ok "Notary credentials work"
  HAVE_NOTARY=1
else
  warn "No working notary profile named '${NOTARY_PROFILE:-<unset>}'"
  HAVE_NOTARY=0
fi

# Version comes from the generator, which is the single source of truth for the
# build. `|| true` throughout: a failed grep must not take the whole script down
# under `set -e` before it can explain itself.
read_setting() {
  grep -oE "'$1' *=> *'[^']*'" "$ROOT/Support/generate_project.rb" 2>/dev/null \
    | tail -1 | sed -E "s/.*=> *'([^']*)'/\1/" || true
}
VERSION=$(read_setting MARKETING_VERSION)
BUILD_NUMBER=$(read_setting CURRENT_PROJECT_VERSION)
[[ -n "$VERSION" ]] || fail "could not read MARKETING_VERSION from Support/generate_project.rb"
ok "Version $VERSION (build ${BUILD_NUMBER:-?})"

if [[ $CHECK_ONLY == 1 ]]; then
  print ""
  if [[ $HAVE_IDENTITY == 1 && $HAVE_NOTARY == 1 ]]; then
    ok "Ready to release"
  else
    warn "Not ready: a Developer ID certificate and notary credentials are required."
    warn "Both come with a paid Apple Developer Program membership."
  fi
  exit 0
fi

[[ $HAVE_IDENTITY == 1 ]] || fail "refusing to build a release that cannot be signed"
[[ $HAVE_NOTARY == 1 ]] || fail "refusing to ship a build that cannot be notarised"

# ----------------------------------------------------------------------- build
info "Generating the Xcode project"
ruby "$HERE/generate_project.rb" >/dev/null

info "Building Release"
rm -rf "$BUILD" "$DIST"
mkdir -p "$DIST"
xcodebuild -project "$ROOT/Jendela.xcodeproj" -scheme Jendela \
  -configuration Release -derivedDataPath "$BUILD" \
  CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
  CODE_SIGN_STYLE=Manual \
  OTHER_CODE_SIGN_FLAGS="--timestamp --options=runtime" \
  build | grep -E "error:|warning: unable|BUILD" || true

APP="$BUILD/Build/Products/Release/Jendela.app"
[[ -d "$APP" ]] || fail "build produced no app"
ok "Built"

# ------------------------------------------------------------------- verifying
info "Verifying the signature"
codesign --verify --deep --strict --verbose=1 "$APP" 2>&1 | sed 's/^/    /'

# get-task-allow marks a debuggable build and is rejected by the notary service.
if codesign -d --entitlements - --xml "$APP" 2>/dev/null | plutil -p - | grep -q "get-task-allow.*1"; then
  fail "get-task-allow is present — this is a debug signature, notarisation will reject it"
fi
ok "Entitlements clean"

# ------------------------------------------------------------------ packaging
info "Packaging the disk image"
STAGE=$(mktemp -d)
# ditto rather than cp: it reproduces the bundle faithfully, including symlinks
# and attributes. The staging directory is a temp one, so either would do here —
# copying a signed app into an iCloud-synced folder is what actually breaks a
# signature, by stamping com.apple.FinderInfo on it.
ditto "$APP" "$STAGE/$(basename "$APP")"

# Signing is verified on the copy that actually ships, not the build output.
codesign --verify --deep --strict "$STAGE/$(basename "$APP")" \
  || fail "the staged app failed signature verification"
ln -s /Applications "$STAGE/Applications"
DMG="$DIST/Jendela-$VERSION.dmg"
hdiutil create -volname "Jendela." -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
ok "$(basename "$DMG")"

# ----------------------------------------------------------------- notarising
info "Notarising (this takes a few minutes)"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait | sed 's/^/    /'

info "Stapling"
# Staple both: the app so it validates when copied out, the dmg so it validates
# before it is even opened.
xcrun stapler staple "$APP" >/dev/null && ok "app stapled"
xcrun stapler staple "$DMG" >/dev/null && ok "dmg stapled"

info "Final gatekeeper check"
spctl --assess --type execute --verbose=2 "$APP" 2>&1 | sed 's/^/    /'

# ------------------------------------------------------------------- manifest
SHA=$(shasum -a 256 "$DMG" | cut -d' ' -f1)
SIZE=$(stat -f%z "$DMG")
cat > "$DIST/appcast.json" <<JSON
{
  "version": "$VERSION",
  "build": ${BUILD_NUMBER:-1},
  "url": "$DOWNLOAD_BASE/$(basename "$DMG")",
  "sha256": "$SHA",
  "size": $SIZE,
  "minimumSystemVersion": "15.0",
  "publishedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON
ok "appcast.json written"

print ""
ok "Release ready in dist/"
print "    upload both files, then the app's update check will find them"
