#!/bin/zsh
# Runs the signed app's noodlet rendering check: live views of HTML and Swift noodlets, animation
# and test clocks. Usage: Applet/scripts/test-rendering.sh "path/to/Noodle Applet.app"
# The app is launched through LaunchServices, in the background: started from a shell, macOS holds
# the shell responsible for the Swift compiler Applet starts, which may then not read Applet's own
# storage. open does not pass on the app's exit status, so the check's last line decides.
set -euo pipefail
app="${1:?Usage: Applet/scripts/test-rendering.sh APP}"
log="$(mktemp -t applet-rendering)"
trap 'rm -f "$log"' EXIT
# Applet allows one copy, and open would wait on a running one rather than start the check.
if pgrep -f "${app:A}/Contents/MacOS/" >/dev/null; then
  print -u2 "Quit ${app:A} first: it is already running."
  exit 1
fi
open -g -n -W --stdout "$log" --stderr "$log" -a "${app:A}" --args --noodle-background --rendering-test
cat "$log"
[[ "$(tail -n 1 "$log")" == "APPLET RENDERING TEST PASSED" ]]
