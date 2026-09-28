#!/bin/zsh
set -euo pipefail
project_root="${0:A:h:h}"
app="${1:-$project_root/.build/Noodle Browser Dev.app}"
executable="$app/Contents/MacOS/NoodleBrowser"
identity="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")"
[[ "$identity" == com.pdparchitect.noodle.browser || "$identity" == com.pdparchitect.noodle.browser.local ]] || { print -u2 'Expected a Noodle Browser bundle.'; exit 1; }
fixture_id="$(uuidgen)"
root="$HOME/Library/Containers/$identity/Data/Library/Application Support/BrowserUI/$fixture_id"
artifacts="$project_root/.build/browser-ui-verification/$fixture_id"
mkdir -p "$artifacts"
cleanup() {
    "$executable" --browser-ui-test --browser-ui-id "$fixture_id" --cleanup-ui > "$artifacts/cleanup.log" 2>&1 || true
}
trap cleanup EXIT
# The argument domain hides both entry points without touching saved preferences. The
# values must be property-list booleans; a bare NO arrives as a string.
"$executable" --browser-ui-test --browser-ui-id "$fixture_id" -showInDock '<false/>' -showMenuBar '<false/>' > "$artifacts/ui.log" 2>&1 &
ui_pid=$!
# A passing run takes under half a minute. Stop a hung one well inside the CI step's limit,
# with its stacks sampled, so the cleanup trap still runs.
for _ in {1..90}; do kill -0 $ui_pid 2>/dev/null || break; sleep 1; done
if kill -0 $ui_pid 2>/dev/null; then
    sample $ui_pid 3 -file "$artifacts/hang-sample.txt" > /dev/null 2>&1 || true
    kill -9 $ui_pid 2>/dev/null || true
    cat "$artifacts/ui.log"
    print -u2 "Browser UI verification hung; stacks are in $artifacts/hang-sample.txt."
    exit 1
fi
wait $ui_pid || { cat "$artifacts/ui.log"; exit 1; }
cat "$artifacts/ui.log"
"$executable" --browser-ui-test --browser-ui-id "$fixture_id" --cleanup-ui > "$artifacts/cleanup.log" 2>&1 || { cat "$artifacts/cleanup.log"; exit 1; }
[[ ! -e "$root" ]] || { print -u2 'UI fixture cleanup failed.'; exit 1; }
trap - EXIT
print "Browser UI verification artifacts: $artifacts"
