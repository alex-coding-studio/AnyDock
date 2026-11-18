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

sign "$app/Contents/Frameworks/Sparkle.framework/Versions/Current/Autoupdate"
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
feed_dir="$staging/feed"
mkdir "$feed_dir"
cp "$dmg" "$feed_dir/"
sparkle_tools="$PWD/.build/artifacts/sparkle/Sparkle/bin"
account="com.cuxiao.mac.anydock"
public_key="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$app/Contents/Info.plist")"
[[ "$("$sparkle_tools/generate_keys" --account "$account" -p)" == "$public_key" ]] ||
  fail "Sparkle signing key does not match the public key embedded in AnyDock."
"$sparkle_tools/generate_appcast" --account "$account" --maximum-deltas 0 \
  --download-url-prefix "https://github.com/alex-coding-studio/AnyDock/releases/download/v$version/" \
  -o "$feed_dir/appcast.xml" "$feed_dir"
"$sparkle_tools/sign_update" --account "$account" --verify "$feed_dir/appcast.xml"
signature="$(xmllint --xpath 'string(/rss/channel/item/enclosure/@*[local-name()="edSignature"])' "$feed_dir/appcast.xml")"
[[ -n "$signature" ]] || fail "Appcast is missing the archive signature."
"$sparkle_tools/sign_update" --account "$account" --verify "$dmg" "$signature"
cp "$feed_dir/appcast.xml" "$PWD/dist/appcast.xml"
printf '%s\n' "$dmg" "$PWD/dist/appcast.xml"
