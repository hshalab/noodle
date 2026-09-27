#!/bin/zsh
set -euo pipefail
project_root="${0:A:h:h}"
app="${1:?Pass the Hub app bundle}"
info="$app/Contents/Info.plist"
bundle="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info")"
[[ "$bundle" == com.pdparchitect.noodle.hub || "$bundle" == com.pdparchitect.noodle.hub.local ]]
codesign --verify --deep --strict "$app"
cmp "$project_root/Hub/Support/AppSymbol.svg" "$app/Contents/Resources/AppSymbol.svg"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info")" == "$(tr -d '[:space:]' < "$project_root/Hub/VERSION")" ]]
# The Hub lives in the menu bar only.
[[ "$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$info")" == true ]]
# A development bundle carries development hooks; a production bundle must not.
if [[ "$bundle" == com.pdparchitect.noodle.hub ]]; then zsh "$project_root/scripts/verify-launch-hooks.sh" "$app"; fi
zsh "$project_root/scripts/verify-updater.sh" "$app"
zsh "$project_root/scripts/verify-agent-host.sh" "$app"
# The signed app holds exactly Hub/Support/Hub.entitlements, with its bundle identifier, team and
# Computer pairing filled in. A public release holds Hub/Support/Hub-Release.entitlements instead,
# with the two keys its provisioning profile adds, and must embed that profile.
team="$(codesign -dv --verbose=4 "$app" 2>&1 | awk -F= '/^TeamIdentifier=/ { print $2 }')"
suffix=""; [[ "$bundle" == *.local ]] && suffix=".local"
policy="$project_root/Hub/Support/Hub.entitlements"; profiled=0
if [[ -f "$app/Contents/embedded.provisionprofile" ]]; then
    policy="$project_root/Hub/Support/Hub-Release.entitlements"; profiled=1
elif [[ "${NOODLE_REQUIRE_DEVELOPER_ID:-0}" == "1" ]]; then
    print -u2 "A public release must embed its Developer ID provisioning profile."
    exit 1
fi
signed="$(mktemp /tmp/hub-entitlements.XXXXXX)"
trap 'rm -f "$signed"' EXIT
codesign -d --entitlements :- "$app" > "$signed" 2>/dev/null
python3 - "$signed" "$policy" "$bundle" "$team" "$suffix" "$profiled" <<'PY'
import plistlib, sys
signed, expected = (plistlib.load(open(path, 'rb')) for path in sys.argv[1:3])
bundle, team, suffix, profiled = sys.argv[3:7]
def fill(value):
    if isinstance(value, str):
        return (value.replace('$(PRODUCT_BUNDLE_IDENTIFIER)', bundle).replace('$(TeamIdentifierPrefix)', team + '.')
                .replace('$(HUB_COMPANION_SUFFIX)', suffix))
    if isinstance(value, list): return [fill(item) for item in value]
    if isinstance(value, dict): return {key: fill(item) for key, item in value.items()}
    return value
expected = fill(expected)
if profiled == '1':
    expected['com.apple.application-identifier'] = f'{team}.{bundle}'
    expected['com.apple.developer.team-identifier'] = team
if signed != expected:
    sys.exit(f'Hub entitlements differ from {sys.argv[2]}:\n{signed}')
PY
print "Hub bundle, identity, updater, Agent Host and entitlements verified"
