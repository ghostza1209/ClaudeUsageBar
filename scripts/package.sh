#!/bin/sh
# Builds the app and zips it to dist/ClaudeUsageBar.zip for sharing (universal: Apple silicon and Intel).
set -eu
cd "$(dirname "$0")/.."

SWIFT_FLAGS="--arch arm64 --arch x86_64" NO_OPEN=1 sh scripts/bundle.sh
mkdir -p dist
rm -f dist/ClaudeUsageBar.zip
ditto -c -k --keepParent .build/ClaudeUsageBar.app dist/ClaudeUsageBar.zip
echo "dist/ClaudeUsageBar.zip"
