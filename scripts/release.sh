#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

identity="${ANYDOCK_SIGN_IDENTITY:-Developer ID Application: Cunqi Xiao (2PQ63WGMNP)}"
team_id="${ANYDOCK_TEAM_ID:-2PQ63WGMNP}"
notary_profile="${ANYDOCK_NOTARY_PROFILE:-MyQuickFinderApi}"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
app="$PWD/dist/AnyDock.app"
dmg="$PWD/dist/AnyDock-$version.dmg"

fail() {
  printf 'release.sh: %s\n' "$1" >&2
  exit 1
}

identities="$(security find-identity -v -p codesigning)"
grep -qF "\"$identity\"" <<<"$identities" ||
  fail "signing identity \"$identity\" is not in the keychain. Set ANYDOCK_SIGN_IDENTITY to override."

rm -rf "$app" "$dmg"
./scripts/build.sh >/dev/null

sign() {
  codesign --force --options runtime --timestamp --sign "$identity" "$1"
}

while IFS= read -r -d '' nested; do
  sign "$nested"
done < <(find "$app/Contents" -depth \( -name '*.framework' -o -name '*.dylib' \
  -o -name '*.xpc' -o -name '*.appex' -o -name '*.app' \) -print0)
sign "$app"
codesign --verify --strict --deep --verbose=2 "$app"
signature="$(codesign -dv "$app" 2>&1)"
grep -qx "TeamIdentifier=$team_id" <<<"$signature" ||
  fail "AnyDock.app is not signed by team $team_id."

staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
ditto "$app" "$staging/AnyDock.app"
ln -s /Applications "$staging/Applications"
hdiutil create -volname AnyDock -srcfolder "$staging" -fs HFS+ -format UDZO -ov "$dmg" >/dev/null
sign "$dmg"
codesign --verify --verbose=2 "$dmg"
printf 'Signed %s\n' "$dmg"

xcrun notarytool history --keychain-profile "$notary_profile" >/dev/null 2>&1 ||
  fail "notary profile \"$notary_profile\" is missing or invalid. Create it with:
  xcrun notarytool store-credentials $notary_profile --apple-id <Apple ID> --team-id $team_id
and enter an app-specific password when prompted, then run this script again."

xcrun notarytool submit "$dmg" --keychain-profile "$notary_profile" --wait
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
spctl -a -t open --context context:primary-signature -vv "$dmg"
spctl -a -vv "$app"
printf '%s\n' "$dmg"
