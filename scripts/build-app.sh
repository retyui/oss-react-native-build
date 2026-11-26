#!/usr/bin/env bash
# Creates a temp RN app, installs the library into it and builds it.
# Env: RN_SPEC (as given), RN_VERSION (exact), RN_MINOR, INIT_MODE, NEW_ARCH (1|0), PLATFORM,
#      IOS_PACKAGE_MANAGER, ANDROID_ARCH, MODULE_PATH, APP_FILE, WORK_DIR
set -euo pipefail
set -x

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Same naming as the previous per-repo action, so app ids stay stable
# (e.g. 0.73 + new arch -> Example0731App -> com.example0731app)
APP_NAME="Example${RN_SPEC}${NEW_ARCH}App"
APP_NAME="${APP_NAME//[^a-zA-Z0-9]/}"
if [[ "${MODULE_PATH:-none}" != "none" ]]; then
  MODULE_PATH="$(cd "$MODULE_PATH" && pwd)"
fi
if [[ -n "${APP_FILE:-}" ]]; then
  APP_FILE="$(cd "${GITHUB_WORKSPACE:-$PWD}" && realpath "$APP_FILE")"
fi

export CI=true
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
export YARN_ENABLE_IMMUTABLE_INSTALLS=false
export npm_config_legacy_peer_deps=true # npx installs of old react-native have stale peers
export NO_FLIPPER=1
export RCT_NEW_ARCH_ENABLED="$NEW_ARCH"

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# 1. Create the app
case "$INIT_MODE" in
  community)
    npx --yes @react-native-community/cli@latest init "$APP_NAME" --version "$RN_VERSION" \
      --skip-git-init --install-pods false --pm yarn
    ;;
  legacy-pm)
    npx --yes "react-native@$RN_VERSION" init "$APP_NAME" --version "$RN_VERSION" \
      --skip-git-init --install-pods false --pm yarn
    ;;
  legacy-skip-install)
    # --npm: CLI 4-11 install the template silently; with yarn it fails for RN 0.68 - 0.72
    npx --yes "react-native@$RN_VERSION" init "$APP_NAME" --version "$RN_VERSION" --skip-install --npm --verbose
    (cd "$APP_NAME" && yarn install)
    ;;
  legacy)
    # CLI 2/3 always installs deps (and pods on macOS; CocoaPods is preinstalled)
    npx --yes "react-native@$RN_VERSION" init "$APP_NAME" --version "$RN_VERSION"
    ;;
  *)
    echo "::error::Unknown init mode $INIT_MODE"
    exit 1
    ;;
esac

cd "$APP_NAME"
APP_DIR="$PWD"

# Old CLIs exit 0 even when installing dependencies failed
if [[ ! -f node_modules/react-native/package.json ]]; then
  echo "::error::react-native init did not install dependencies (see the log above)"
  exit 1
fi
echo "app_dir=$APP_DIR" >> "${GITHUB_OUTPUT:-/dev/null}"

# 2. Install the library (skipped when module-to-install is "none")
if [[ "${MODULE_PATH:-none}" != "none" ]]; then
  PKG_NAME="$(node -p "require('$MODULE_PATH/package.json').name")"
  if [[ "$(yarn --version)" == 1.* ]]; then
    yarn add "file:$MODULE_PATH"
  else
    yarn add "$PKG_NAME@portal:$MODULE_PATH"
    # The portal symlink points outside the project root: let Metro watch the library
    # and resolve its imports (react-native, ...) from the app's node_modules
    node -e '
      const [modulePath, appModules] = process.argv.slice(1);
      require("fs").appendFileSync("metro.config.js", `
const __baseConfig = module.exports;
module.exports = {
  ...__baseConfig,
  watchFolders: [...(__baseConfig.watchFolders || []), ${JSON.stringify(modulePath)}],
  resolver: {
    ...__baseConfig.resolver,
    nodeModulesPaths: [
      ...((__baseConfig.resolver && __baseConfig.resolver.nodeModulesPaths) || []),
      ${JSON.stringify(appModules)},
    ],
  },
};
`);
    ' "$MODULE_PATH" "$APP_DIR/node_modules"
  fi
fi

# 3. Optional custom entry component
if [[ -n "${APP_FILE:-}" ]]; then
  rm -f App.tsx App.ts App.js
  cp "$APP_FILE" App.js
fi

./node_modules/.bin/react-native info || true

# 4. Build
if [[ "$PLATFORM" == "ios" ]]; then
  if [[ "$IOS_PACKAGE_MANAGER" == "spm" ]]; then
    npx react-native spm add --deintegrate --yes
    container=(-project "ios/$APP_NAME.xcodeproj")
  else
    # boostorg.jfrog.io (pinned by RN <= 0.7x) is gone; same tarball on the official mirror
    boost_podspec=node_modules/react-native/third-party-podspecs/boost.podspec
    if [[ -f "$boost_podspec" ]]; then
      sed -i.bak 's#https://boostorg.jfrog.io/artifactory/main/release/#https://archives.boost.io/release/#' "$boost_podspec" && rm -f "$boost_podspec.bak"
    fi
    # Podfiles of RN <= 0.70 enable Flipper unconditionally (NO_FLIPPER is ignored);
    # its pods (YogaKit Swift, Flipper-Folly/libevent) no longer link with Xcode 16
    sed -i.bak -E \
      -e 's/^([[:space:]]*)(add_flipper_pods!|use_flipper!|flipper_post_install\()/\1# \2/' \
      -e 's/FlipperConfiguration\.enabled/FlipperConfiguration.disabled/' \
      ios/Podfile && rm -f ios/Podfile.bak
    (cd ios && pod install)
    container=(-workspace "ios/$APP_NAME.xcworkspace")
  fi

  extra_settings=()
  if (( RN_MINOR < 69 )); then
    # Xcode 16 clang: -Werror in old Yoga/RN C++ trips -Wbitwise-instead-of-logical;
    # Xcode 16 libc++ removed std::unary_function (used by boost 1.76 in RN 0.68)
    extra_settings+=(OTHER_CFLAGS='$(inherited) -Wno-error=bitwise-instead-of-logical')
    extra_settings+=(OTHER_CPLUSPLUSFLAGS='$(inherited) -Wno-error=bitwise-instead-of-logical -D_LIBCPP_ENABLE_CXX17_REMOVED_UNARY_BINARY_FUNCTION')
  fi

  set -o pipefail
  # ${arr[@]+...}: macOS bash 3.2 treats an empty array as unbound under `set -u`
  xcodebuild "${container[@]}" ${extra_settings[@]+"${extra_settings[@]}"} \
    -scheme "$APP_NAME" \
    -configuration Release \
    -sdk iphonesimulator \
    -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath "$WORK_DIR/DerivedData" \
    ARCHS="$(uname -m)" \
    CODE_SIGNING_ALLOWED=NO \
    COMPILER_INDEX_STORE_ENABLE=NO \
    | xcbeautify --quiet

  app_path="$(find "$WORK_DIR/DerivedData/Build/Products" -maxdepth 2 -type d -name "$APP_NAME.app" | head -1)"
else
  props=android/gradle.properties
  value=$([[ "$NEW_ARCH" == "1" ]] && echo true || echo false)
  if grep -q '^newArchEnabled=' "$props"; then
    sed -i.bak "s/^newArchEnabled=.*/newArchEnabled=$value/" "$props" && rm -f "$props.bak"
  elif [[ "$NEW_ARCH" == "1" ]]; then
    echo "newArchEnabled=true" >> "$props"
  fi

  # New arch on RN <= 0.70 builds ReactAndroid from source: boost URL on the dead jfrog host
  rn_android_gradle=node_modules/react-native/ReactAndroid/build.gradle
  if [[ -f "$rn_android_gradle" ]]; then
    sed -i.bak 's#https://boostorg.jfrog.io/artifactory/main/release/#https://archives.boost.io/release/#' "$rn_android_gradle" && rm -f "$rn_android_gradle.bak"
  fi
  if (( RN_MINOR < 71 )); then
    # Hermes built from source misses <cstdint> includes required by GCC 13
    export CXXFLAGS="${CXXFLAGS:-} -include cstdint"
  fi

  # Maven Central answers parallel CI runners with HTTP 429: maven-mirror.gradle
  # resolves it from Google's mirror; retry with backoff for anything left
  for attempt in 1 2 3 4 5; do
    if (cd android && ./gradlew assembleRelease --no-daemon --init-script "$SCRIPTS_DIR/maven-mirror.gradle" \
      -PreactNativeArchitectures="$ANDROID_ARCH"); then
      break
    fi
    if (( attempt == 5 )); then
      exit 1
    fi
    echo "::warning::Gradle build failed (attempt $attempt), retrying in $((attempt * 60))s"
    sleep $((attempt * 60))
  done

  app_path="$(find "$APP_DIR/android/app/build/outputs/apk/release" -name '*.apk' | head -1)"
fi

if [[ -z "$app_path" ]]; then
  echo "::error::Build finished but no app binary was found"
  exit 1
fi
echo "app_path=$app_path" >> "${GITHUB_OUTPUT:-/dev/null}"
