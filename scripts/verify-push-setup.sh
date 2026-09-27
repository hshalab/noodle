#!/bin/zsh
# Checks, before a public release, that Apple's side of telling devices away from the Hub about unread
# replies matches what the code writes and what the release entitlements claim: the CloudKit schema in
# the environment the releases use, and each named app's Developer ID profile. Nothing is skipped here.
#   scripts/verify-push-setup.sh [APP…]   Noodle, Hub, or both when none are named
# It needs CLOUDKIT_MANAGEMENT_TOKEN, or a token saved with `xcrun cktool save-token --type management`,
# and APP_PROVISIONING_PROFILE_PATH for each app, as NOODLE_PROVISIONING_PROFILE_PATH.
set -euo pipefail
cd "${0:A:h:h}"
PUSH_SETUP_REQUIRED=1 PUSH_SETUP_APPS="${*:-Noodle Hub}" \
    swift test --disable-sandbox --filter HubCoreTests.PushSetupTests --scratch-path .build/push-setup
