#!/usr/bin/env bash
# Toolchain bits that have no dedicated setup-* action.
# Env: PLATFORM, XCODE_VERSION
set -euo pipefail

# New templates pin "packageManager": "yarn@4.x", which a global yarn 1 refuses;
# corepack's yarn shim honours it (and is yarn 1 for old templates without it).
if command -v corepack >/dev/null 2>&1; then
  corepack enable
elif ! command -v yarn >/dev/null 2>&1; then
  npm install --global yarn@1
fi
echo "yarn $(yarn --version)"

# yarn 1 fails on any transitive dep whose "engines" excludes the (old) Node that
# old RN needs, e.g. encoding@0.1.14 requires Node >= 20. Applies to every yarn 1
# run, including the CLI's own template install in a tmp dir.
echo "ignore-engines true" >> "$HOME/.yarnrc"

if [[ "$PLATFORM" == "ios" ]]; then
  xcode_app="/Applications/Xcode_${XCODE_VERSION}.app"
  if [[ -d "$xcode_app" ]]; then
    sudo xcode-select --switch "$xcode_app/Contents/Developer"
  else
    echo "::warning title=Xcode ${XCODE_VERSION} not installed::Using default $(xcode-select -p). Installed: $(ls -d /Applications/Xcode_*.app 2>/dev/null | xargs -n1 basename | tr '\n' ' ')"
  fi
  xcodebuild -version

  # Compiling storyboards needs the simulator runtime matching the Xcode's SDK.
  # The runner image only ships runtimes for its newest Xcodes (e.g. no iOS 18.2
  # for Xcode 16.2), so download it when missing.
  sdk_version="$(xcrun --sdk iphonesimulator --show-sdk-version)"
  if ! xcrun simctl list runtimes | grep -q "iOS ${sdk_version} "; then
    echo "iOS ${sdk_version} simulator runtime not installed, downloading"
    # ~8 GB from Apple's CDN; fails transiently ("general networking error").
    # Its exit status is unreliable (0 after "Download failed"), so look for "Done."
    # (it may install a newer point release, e.g. 18.3.1 for SDK 18.2, which builds fine)
    download_log="$(mktemp)"
    for attempt in 1 2 3 4 5; do
      xcodebuild -downloadPlatform iOS 2>&1 | tee "$download_log" || true
      if grep -q ': Done\.' "$download_log"; then
        break
      fi
      if (( attempt == 5 )); then
        echo "::error::Could not download the iOS ${sdk_version} simulator runtime"
        exit 1
      fi
      echo "::warning::Simulator runtime download failed (attempt $attempt), retrying in $((attempt * 30))s"
      sleep $((attempt * 30))
    done
  fi

  # Global CocoaPods on the selected Ruby; template Gemfiles pin Ruby/CocoaPods
  # versions that don't exist on current runners, so they are not used.
  if ! command -v pod >/dev/null 2>&1; then
    gem install cocoapods --no-document
  fi
  echo "cocoapods $(pod --version)"

  if ! command -v xcbeautify >/dev/null 2>&1; then
    brew install xcbeautify
  fi
fi
