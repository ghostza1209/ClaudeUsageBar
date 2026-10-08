#!/bin/sh
# Installs or updates Claude Usage Bar from the latest GitHub Release, then opens it:
#   curl -fsSL https://raw.githubusercontent.com/ghostza1209/ClaudeUsageBar/HEAD/install.sh | sh
# A file curl downloads carries no quarantine flag, so Gatekeeper does not block the ad-hoc signed app.
set -eu

url=https://github.com/ghostza1209/ClaudeUsageBar/releases/latest/download/ClaudeUsageBar.zip
dir=/Applications
[ -w "$dir" ] || dir=$HOME/Applications
app=$dir/ClaudeUsageBar.app
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo "Downloading Claude Usage Bar..."
curl -fsSL "$url" -o "$tmp/ClaudeUsageBar.zip"
ditto -x -k "$tmp/ClaudeUsageBar.zip" "$tmp"
pkill -x ClaudeUsageBar || true
mkdir -p "$dir"
rm -rf "$app"
mv "$tmp/ClaudeUsageBar.app" "$app"
open "$app"
echo "Installed to $app"
echo "Next: click the gauge in the menu bar and press Install... to show your Plan limits."
