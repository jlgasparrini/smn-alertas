#!/bin/sh
# Launches the built app for real and checks that it starts, stays up and reaches the SMN.
# Catches what unit tests can't: launch crashes, a broken feed, notifications turned off.
#   ./smoke-test.sh            (build first with ./build-app.sh)
set -u
cd "$(dirname "$0")"
APP="build/SMN Alertas.app"
[ -d "$APP" ] || { echo "✘ $APP not found; run ./build-app.sh first"; exit 1; }

pkill -f "SMN Alertas.app/Contents/MacOS/SMNAlertas" 2>/dev/null
sleep 1
START=$(date "+%Y-%m-%d %H:%M:%S")
open "$APP"
echo "Waiting 30 s for the first check…"
sleep 30

fail=0
logs=$(/usr/bin/log show --start "$START" --predicate 'subsystem == "local.smnalertas"' --style compact 2>/dev/null)

if pgrep -f "SMN Alertas.app/Contents/MacOS/SMNAlertas" >/dev/null; then
    echo "✔ app is running"
else
    echo "✘ app is not running (crashed?) — see ~/Library/Logs/DiagnosticReports"; fail=1
fi

if find ~/Library/Logs/DiagnosticReports -name 'SMNAlertas-*' -newermt "$START" 2>/dev/null | grep -q .; then
    echo "✘ new crash report since launch"; fail=1
fi

check=$(echo "$logs" | grep "check:" | tail -1)
if [ -n "$check" ]; then
    echo "✔ SMN check: ${check##*check: }"
elif echo "$logs" | grep -q "check failed"; then
    echo "✘ SMN check failed: $(echo "$logs" | grep 'check failed' | tail -1 | sed 's/.*check failed: //')"; fail=1
else
    echo "✘ no SMN check logged (is a city set?)"; fail=1
fi

if echo "$logs" | grep -q "notification status=allowed"; then
    echo "✔ macOS notifications allowed"
else
    echo "⚠ macOS notifications not allowed — alerts will only blink and sound"
fi

exit $fail
