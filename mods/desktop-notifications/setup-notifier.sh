#!/bin/sh
# Installs ~/Applications/Herdr Notifier.app: a copy of terminal-notifier.app
# carrying Herdr's icon and name, so every desktop notification from this mod
# shows one face (and clicking one focuses the agent). The mod finds the copy by
# itself; run this again after a big Homebrew or macOS change. The bundle id is
# kept, so a notification permission already granted to terminal-notifier
# carries over; nothing to re-allow.
set -e

SRC=$(brew --prefix terminal-notifier 2>/dev/null || true)
[ -n "$SRC" ] && [ -d "$SRC/terminal-notifier.app" ] || SRC=/opt/homebrew/opt/terminal-notifier
[ -d "$SRC/terminal-notifier.app" ] || SRC=/usr/local/opt/terminal-notifier
if [ ! -d "$SRC/terminal-notifier.app" ]; then
  echo "terminal-notifier is not installed anywhere known (brew install terminal-notifier)." >&2
  exit 1
fi

DST="$HOME/Applications/Herdr Notifier.app"
rm -rf "$DST"
cp -R "$SRC/terminal-notifier.app" "$DST"

ICON=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$DST/Contents/Info.plist")
HERDR_ICON=/Applications/Herdr.app/Contents/Resources/Herdr.icns
if [ -f "$HERDR_ICON" ]; then
  cp "$HERDR_ICON" "$DST/Contents/Resources/${ICON%.icns}.icns"
else
  echo "Note: $HERDR_ICON not found; keeping terminal-notifier's own icon." >&2
fi
/usr/libexec/PlistBuddy -c 'Set :CFBundleName Herdr Notifier' "$DST/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName Herdr Notifier' "$DST/Contents/Info.plist" 2>/dev/null ||
  /usr/libexec/PlistBuddy -c 'Add :CFBundleDisplayName string Herdr Notifier' "$DST/Contents/Info.plist"
touch "$DST"
echo "Installed $DST. The mod picks it up the next time it loads."
