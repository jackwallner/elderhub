#!/bin/bash
set -e

if [[ -x /opt/homebrew/bin/fastlane ]]; then
  exec /opt/homebrew/bin/fastlane "$@"
elif [[ -x /usr/local/bin/fastlane ]]; then
  exec /usr/local/bin/fastlane "$@"
else
  exec fastlane "$@"
fi
