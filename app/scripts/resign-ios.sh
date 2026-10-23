#!/usr/bin/env bash
# Keep the self-built iPhone app from expiring.
#
# A free Apple developer account signs an app for 7 days; after that iOS
# says "<app> is no longer available" and will not open it. This checks how
# long the installed app's signing has left and, when it is close, rebuilds
# and reinstalls with build-local.sh -- unattended, over Wi-Fi or cable.
#
# Run by launchd (see scripts/com.omilocal.resign-ios.plist) several times a
# day; most runs see plenty of time left and exit at once. A run that cannot
# reach the phone, or finds it locked, says so in a macOS notification and
# leaves the next run to try again.
#
#   scripts/resign-ios.sh           rebuild only if expiring within RESIGN_WITHIN_DAYS
#   scripts/resign-ios.sh --force   rebuild now
set -uo pipefail
cd "$(dirname "$0")/.."

RESIGN_WITHIN_DAYS="${RESIGN_WITHIN_DAYS:-2}"
BUNDLE_ID="${RESIGN_BUNDLE_ID:-com.romande.omilocal}"
STATE_DIR="${HOME}/Library/Logs/omi-resign"
LOG="${STATE_DIR}/last-build.log"
mkdir -p "$STATE_DIR"
# launchd starts with a bare PATH; flutter, pod and xcrun must be found.
export PATH="/opt/homebrew/bin:/usr/local/bin:${HOME}/flutter/bin:${HOME}/development/flutter/bin:${PATH}"

say() { echo "$(date '+%F %T') $*" | tee -a "${STATE_DIR}/resign.log"; }
notify() {
  osascript -e "display notification \"$2\" with title \"Omi app: $1\"" >/dev/null 2>&1 || true
}

device_id() {
  set -a; . ./.env.local-build 2>/dev/null; set +a
  echo "${OMI_IOS_DEVICE_ID:-}"
}

# Expiry of the newest provisioning profile Xcode holds for the app. The
# installed app was signed with the newest one this Mac produced.
expires_epoch() {
  local newest=0 f exp t
  for f in "${HOME}/Library/Developer/Xcode/UserData/Provisioning Profiles/"*.mobileprovision; do
    [[ -f "$f" ]] || continue
    security cms -D -i "$f" 2>/dev/null > "${STATE_DIR}/pp.plist" || continue
    [[ "$(plutil -extract Name raw "${STATE_DIR}/pp.plist" 2>/dev/null)" == *": ${BUNDLE_ID}" ]] || continue
    exp=$(plutil -extract ExpirationDate raw "${STATE_DIR}/pp.plist" 2>/dev/null) || continue
    t=$(date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$exp" +%s 2>/dev/null) || continue
    (( t > newest )) && newest=$t
  done
  echo "$newest"
}

DEVICE=$(device_id)
if [[ -z "$DEVICE" ]]; then
  say "no OMI_IOS_DEVICE_ID in .env.local-build; nothing to do"
  exit 2
fi

if [[ "${1:-}" != "--force" ]]; then
  exp=$(expires_epoch)
  left=$(( exp - $(date +%s) ))
  if (( exp > 0 && left > RESIGN_WITHIN_DAYS * 86400 )); then
    say "signing has $(( left / 3600 ))h left; nothing to do"
    exit 0
  fi
  say "signing expires in $(( left / 3600 ))h; rebuilding"
fi

# The phone must be reachable (cable or same Wi-Fi) before an 8-minute build.
if ! timeout 60 xcrun devicectl list devices --timeout 45 2>/dev/null \
     | grep -F "$DEVICE" | grep -qiE "connected|available"; then
  say "phone not reachable"
  notify "phone not reachable" "Connect the iPhone (same Wi-Fi or cable) — the app needs re-signing before it expires."
  exit 3
fi

# build-local.sh ends in `flutter run`, which stays attached after the app is
# installed and launched. Run it detached, stop it once installed.
OMI_IOS_DEVICE_ID="$DEVICE" ./build-local.sh ios > "$LOG" 2>&1 < /dev/null &
BUILD_PID=$!
deadline=$(( $(date +%s) + 45 * 60 ))
outcome=timeout
while (( $(date +%s) < deadline )); do
  if grep -q "Flutter run key commands" "$LOG" 2>/dev/null; then outcome=installed; break; fi
  # Installed, but iOS will not launch it until the developer is trusted again
  # (it asks after the signing certificate is renewed). The install is what
  # counts; the launch is the user's tap away.
  if grep -q "Installing and launching" "$LOG" 2>/dev/null \
     && grep -qiE "not trusted|untrusted|VM Service was not discovered|Unable to launch" "$LOG" 2>/dev/null; then
    outcome=needs_trust; break
  fi
  if grep -qiE "device is locked|passcode protected|unlock" "$LOG" 2>/dev/null; then outcome=locked; break; fi
  if ! kill -0 "$BUILD_PID" 2>/dev/null; then outcome=failed; break; fi
  sleep 10
done
pkill -P "$BUILD_PID" 2>/dev/null; kill "$BUILD_PID" 2>/dev/null
pkill -f "flutter_tools.*run.*${DEVICE}" 2>/dev/null || true

case "$outcome" in
  installed)
    say "reinstalled; signing now expires $(date -r "$(expires_epoch)" '+%a %d %b %H:%M')"
    notify "re-signed" "Reinstalled on your iPhone; good for another 7 days."
    exit 0 ;;
  needs_trust)
    say "reinstalled; iOS wants the developer trusted before it opens"
    notify "trust needed" "Reinstalled. On the iPhone: Settings > General > VPN & Device Management > Apple Development > Trust."
    exit 0 ;;
  locked)
    say "phone was locked"
    notify "unlock your iPhone" "The app needs re-signing; it will try again at the next check." ;;
  *)
    say "build ${outcome}; see ${LOG}"
    notify "re-sign failed" "Build ${outcome}. Log: ${LOG}" ;;
esac
exit 1
