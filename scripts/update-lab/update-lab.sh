#!/usr/bin/env bash
# Local Sparkle update-flow lab — backs the `make update-test-*` targets.
#
#   update-lab.sh <none|download-fail|extract-fail|success|stop>
#
# Expects the Debug app to already exist (the Makefile targets depend on
# `build`). The lab never mutates the build product or the project: it copies
# the app into build/update-lab/run/, swaps `SUPublicEDKey` for a throwaway
# dev key (kept in a file, not the keychain), re-signs ad-hoc, serves a
# scenario-shaped appcast from a loopback HTTP server, and launches the copy
# with the Debug-only `LOCKIME_UPDATE_FEED` override. Archives are signed with
# Sparkle's own `sign_update` from the SPM artifact, so the verify path is
# exactly what production uses.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LAB_DIR="$REPO_ROOT/build/update-lab"
APP_SRC="${UPDATE_LAB_APP:-$REPO_ROOT/build/DerivedData/Build/Products/Debug/LockIME Dev.app}"
PORT="${UPDATE_LAB_PORT:-8767}"
PLISTBUDDY=/usr/libexec/PlistBuddy
APP_NAME="${UPDATE_LAB_APP_NAME:-LockIME Dev}"
BUNDLE_ID="${UPDATE_LAB_BUNDLE_ID:-com.oomol.LockIME.dev}"
EXECUTABLE_NAME="${UPDATE_LAB_EXECUTABLE_NAME:-$APP_NAME}"
NEW_SHORT="99.0.0"
NEW_BUILD="209901010101"
# ~4 MB/s so the in-app download progress UI is actually visible.
THROTTLE_BPS=4194304

SERVE_DIR="$LAB_DIR/serve"
RUN_APP="$LAB_DIR/run/$APP_NAME.app"
PID_FILE="$LAB_DIR/server.pid"
SEED_FILE="$LAB_DIR/dev-ed25519.seed"

usage() { echo "usage: $(basename "$0") <none|download-fail|extract-fail|success|stop>" >&2; exit 2; }
[[ $# -eq 1 ]] || usage
SCENARIO="$1"

clear_skip_keys() {
    # Sparkle 2's persisted skip keys (SUConstants.m). A "Skip This Version"
    # click in the lab window writes SUSkippedVersion=209901010101 into the app's
    # defaults domain, so always clear them, including on stop.
    local key
    for key in SUSkippedVersion SUSkippedMajorVersion SUSkippedMajorSubreleaseVersion; do
        defaults delete "$BUNDLE_ID" "$key" 2>/dev/null || true
    done
}

stop_lab() {
    if [[ -f "$PID_FILE" ]]; then
        local pid
        pid="$(cat "$PID_FILE" 2>/dev/null || true)"
        # Only kill if the PID still belongs to the lab server (PIDs recycle).
        if [[ -n "$pid" ]] && ps -p "$pid" -o command= 2>/dev/null | grep -q "update-lab/server.py"; then
            kill "$pid" 2>/dev/null || true
        fi
        rm -f "$PID_FILE"
    fi
    pkill -f "update-lab/server.py" 2>/dev/null || true
    pkill -x "$EXECUTABLE_NAME" 2>/dev/null || true
    local i=0
    while pgrep -x "$EXECUTABLE_NAME" >/dev/null && [[ $i -lt 50 ]]; do sleep 0.1; i=$((i + 1)); done
    clear_skip_keys
}

if [[ "$SCENARIO" == "stop" ]]; then
    stop_lab
    rm -rf "$LAB_DIR/run" "$LAB_DIR/payload" "$SERVE_DIR"
    echo "[update-lab] stopped."
    exit 0
fi

case "$SCENARIO" in
    none | download-fail | extract-fail | success) ;;
    *) usage ;;
esac

[[ -d "$APP_SRC" ]] || { echo "error: $APP_SRC not found — run 'make build' first" >&2; exit 1; }
APP_NAME="$(basename "$APP_SRC" .app)"
BUNDLE_ID="$("$PLISTBUDDY" -c "Print :CFBundleIdentifier" "$APP_SRC/Contents/Info.plist")"
EXECUTABLE_NAME="$("$PLISTBUDDY" -c "Print :CFBundleExecutable" "$APP_SRC/Contents/Info.plist")"
RUN_APP="$LAB_DIR/run/$APP_NAME.app"

# The lab hooks are #if DEBUG; a Release binary would silently ignore the
# loopback feed and poll production with the swapped dev key instead.
grep -rq "LOCKIME_UPDATE_FEED" "$APP_SRC/Contents/MacOS" 2>/dev/null \
    || { echo "error: $APP_SRC lacks the Debug-only lab hooks — build with CONFIG=Debug" >&2; exit 1; }

SIGN_UPDATE="$(find "$REPO_ROOT/build/DerivedData/SourcePackages/artifacts" \
    -type f -name sign_update -path "*/bin/*" -print -quit 2>/dev/null || true)"
[[ -n "$SIGN_UPDATE" ]] || { echo "error: Sparkle sign_update not found under DerivedData — run 'make build' first" >&2; exit 1; }

echo "[update-lab] scenario: $SCENARIO"
stop_lab
rm -rf "$SERVE_DIR" "$LAB_DIR/run" "$LAB_DIR/payload" "$LAB_DIR/app.log" "$LAB_DIR/server.log"
mkdir -p "$SERVE_DIR" "$LAB_DIR/run"

# Throwaway dev keypair (file-backed; reused across runs).
DEV_PUBKEY="$(swift "$REPO_ROOT/scripts/update-lab/keygen.swift" "$SEED_FILE")"

# The app copy under test: trust the dev key instead of the production one.
ditto "$APP_SRC" "$RUN_APP"
"$PLISTBUDDY" -c "Set :SUPublicEDKey $DEV_PUBKEY" "$RUN_APP/Contents/Info.plist"
codesign --force --sign - "$RUN_APP" 2>/dev/null

CUR_SHORT="$("$PLISTBUDDY" -c "Print :CFBundleShortVersionString" "$RUN_APP/Contents/Info.plist")"
CUR_BUILD="$("$PLISTBUDDY" -c "Print :CFBundleVersion" "$RUN_APP/Contents/Info.plist")"

sign_archive() { "$SIGN_UPDATE" --ed-key-file - -p "$1" < "$SEED_FILE"; }

build_payload_zip() { # <zip-path> — the "new version" app, zipped like CI does
    local zip="$1" payload="$LAB_DIR/payload/$APP_NAME.app"
    mkdir -p "$LAB_DIR/payload"
    ditto "$APP_SRC" "$payload"
    "$PLISTBUDDY" -c "Set :SUPublicEDKey $DEV_PUBKEY" "$payload/Contents/Info.plist"
    "$PLISTBUDDY" -c "Set :CFBundleShortVersionString $NEW_SHORT" "$payload/Contents/Info.plist"
    "$PLISTBUDDY" -c "Set :CFBundleVersion $NEW_BUILD" "$payload/Contents/Info.plist"
    codesign --force --sign - "$payload" 2>/dev/null
    ditto -c -k --keepParent "$payload" "$zip"
}

write_appcast() { # <item-xml...>
    cat > "$SERVE_DIR/appcast.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>LockIME update lab</title>
$*
  </channel>
</rss>
EOF
}

update_item() { # <enclosure-url> <length> <signature>
    cat <<EOF
    <item>
      <title>$NEW_SHORT</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$NEW_BUILD</sparkle:version>
      <sparkle:shortVersionString>$NEW_SHORT</sparkle:shortVersionString>
      <description><![CDATA[
## LockIME $NEW_SHORT — update lab

A simulated release served from \`localhost:$PORT\` (scenario: **$SCENARIO**).

- Exercises the real Sparkle pipeline: download, EdDSA verify, extract, install
- Safe to install: it is this very build, re-versioned
      ]]></description>
      <enclosure url="$1" length="$2" type="application/octet-stream" sparkle:edSignature="$3"/>
    </item>
EOF
}

case "$SCENARIO" in
none)
    # Latest advertised version == the running one → "You're up to date."
    write_appcast "$(cat <<EOF
    <item>
      <title>$CUR_SHORT</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$CUR_BUILD</sparkle:version>
      <sparkle:shortVersionString>$CUR_SHORT</sparkle:shortVersionString>
      <enclosure url="http://localhost:$PORT/unused.zip" length="1" type="application/octet-stream"/>
    </item>
EOF
    )"
    ;;
download-fail)
    # Real, correctly signed archive — but served through /truncate/, which
    # resets the connection mid-transfer.
    ZIP="$SERVE_DIR/LockIME-$NEW_SHORT.zip"
    build_payload_zip "$ZIP"
    SIG="$(sign_archive "$ZIP")"
    LEN="$(stat -f%z "$ZIP")"
    write_appcast "$(update_item "http://localhost:$PORT/truncate/LockIME-$NEW_SHORT.zip" "$LEN" "$SIG")"
    ;;
extract-fail)
    # Garbage bytes with a VALID EdDSA signature: passes verification, then
    # fails to unarchive (SUUnarchivingError, Sparkle's 3000s bucket).
    ZIP="$SERVE_DIR/LockIME-$NEW_SHORT.zip"
    head -c 6291456 /dev/urandom > "$ZIP"
    SIG="$(sign_archive "$ZIP")"
    LEN="$(stat -f%z "$ZIP")"
    write_appcast "$(update_item "http://localhost:$PORT/LockIME-$NEW_SHORT.zip" "$LEN" "$SIG")"
    ;;
success)
    ZIP="$SERVE_DIR/LockIME-$NEW_SHORT.zip"
    build_payload_zip "$ZIP"
    SIG="$(sign_archive "$ZIP")"
    LEN="$(stat -f%z "$ZIP")"
    write_appcast "$(update_item "http://localhost:$PORT/LockIME-$NEW_SHORT.zip" "$LEN" "$SIG")"
    ;;
esac

# Stale per-user Sparkle state from earlier runs (or the real install) can
# short-circuit the flow — clear the bits that would.
clear_skip_keys
# Pretend a scheduled check just happened so one can't race the lab's check.
defaults write "$BUNDLE_ID" SULastCheckTime -date "$(date -u "+%Y-%m-%d %H:%M:%S +0000")" 2>/dev/null || true
rm -rf "$HOME/Library/Caches/$BUNDLE_ID/org.sparkle-project.Sparkle"

python3 -B "$REPO_ROOT/scripts/update-lab/server.py" \
    --root "$SERVE_DIR" --port "$PORT" --throttle-bps "$THROTTLE_BPS" \
    > "$LAB_DIR/server.log" 2>&1 &
echo $! > "$PID_FILE"
for _ in $(seq 1 50); do
    curl -sf -o /dev/null "http://localhost:$PORT/appcast.xml" && break
    sleep 0.1
done
curl -sf -o /dev/null "http://localhost:$PORT/appcast.xml" || {
    echo "error: lab server failed to start (see $LAB_DIR/server.log)" >&2
    kill "$(cat "$PID_FILE" 2>/dev/null)" 2>/dev/null || true
    rm -f "$PID_FILE"
    exit 1
}

# UPDATE_LAB_AUTO=1 auto-accepts the install prompts (hands-free runs).
LOCKIME_UPDATE_FEED="http://localhost:$PORT/appcast.xml" \
LOCKIME_UPDATE_CHECK_ON_LAUNCH=1 \
LOCKIME_UPDATE_AUTO_INSTALL="${UPDATE_LAB_AUTO:-0}" \
    "$RUN_APP/Contents/MacOS/$EXECUTABLE_NAME" > "$LAB_DIR/app.log" 2>&1 &
disown

INSTALL_STEP="click Install —"
[[ "${UPDATE_LAB_AUTO:-0}" == "1" ]] && INSTALL_STEP="auto-install accepts the prompt —"

echo
echo "[update-lab] app launched ($CUR_SHORT/$CUR_BUILD), feed http://localhost:$PORT/appcast.xml"
echo "[update-lab] a user-style update check fires automatically ~1s after launch"
case "$SCENARIO" in
none)
    echo "[update-lab] EXPECT: \"You're up to date.\" alert; no update window." ;;
download-fail)
    echo "[update-lab] EXPECT: update window for $NEW_SHORT; $INSTALL_STEP"
    echo "[update-lab]         download dies mid-transfer → \"couldn't be downloaded\" error in the window." ;;
extract-fail)
    echo "[update-lab] EXPECT: update window for $NEW_SHORT; $INSTALL_STEP"
    echo "[update-lab]         download completes, extraction fails → \"couldn't be verified\" error in the window."
    echo "[update-lab]         (unarchive errors share Sparkle's 3000s bucket with signature errors)" ;;
success)
    echo "[update-lab] EXPECT: update window for $NEW_SHORT; $INSTALL_STEP"
    echo "[update-lab]         downloads, extracts, installs, relaunches as $NEW_SHORT."
    echo "[update-lab] VERIFY after relaunch: About window shows $NEW_SHORT, app is running, and:"
    echo "[update-lab]           /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \\"
    echo "[update-lab]               '$RUN_APP/Contents/Info.plist'" ;;
esac
echo "[update-lab] logs:  tail -f $LAB_DIR/server.log $LAB_DIR/app.log"
echo "[update-lab] done:  make update-test-stop"
