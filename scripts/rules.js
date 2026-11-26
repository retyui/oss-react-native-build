'use strict';

// Single source of truth: which toolchain to use for which React Native minor,
// and which build combinations exist at all.
//
// Each table is a list of [fromMinor, value]; the last entry whose fromMinor <= minor wins.
const TOOLCHAIN = {
  node: [
    [60, '16'],
    [68, '18'],
    [73, '20'],
    [81, '22'], // RN 0.81+ requires >= 20.19.4
    [87, '24'], // RN 0.87+ requires ^22.13 || ^24.3
  ],
  java: [
    [60, '8'], // AGP 3.x / 4.x
    [67, '11'], // AGP 7.x
    [73, '17'], // AGP 8+
  ],
  ruby: [[60, '3.3']],
  // Xcode installed on the macos-15 runner image. Xcode 16.3+ (clang 19 / libc++ 19)
  // breaks folly in older RN, so stay on 16.2 there; its iOS 18.2 simulator runtime is
  // not preinstalled and gets downloaded by setup-tools.sh. 0.76+ patches build on 16.4.
  xcode: [
    [60, '16.2'],
    [76, '16.4'],
  ],
};

// Lowest RN minor that is known to build on the toolchain above.
// Determined by the full matrix in .github/workflows/ci.yml; raise it when an
// old version stops building on the current runner images.
const MIN_SUPPORTED = {
  // 0.62 - 0.64 depend on fresco 2.2.0 / flipper 0.33.1, which only existed on
  // the shut-down jcenter; 0.60 - 0.61 fail Metro's Release bundling (Flow types left in).
  android: 65,
  // 0.60 - 0.62: Metro Release bundling fails (main.jsbundle not produced).
  ios: 63,
};

const FEATURES = {
  newArchFrom: 68, // first RN with newArchEnabled / RCT_NEW_ARCH_ENABLED
  oldArchUntil: 81, // legacy architecture removed in 0.82
  spmFrom: 87, // first RN shipping `react-native spm`
};

function pick(table, minor) {
  let value = table[0][1];
  for (const [from, v] of table) {
    if (minor >= from) value = v;
  }
  return value;
}

function toolchainFor(minor) {
  return {
    node: pick(TOOLCHAIN.node, minor),
    java: pick(TOOLCHAIN.java, minor),
    ruby: pick(TOOLCHAIN.ruby, minor),
    xcode: pick(TOOLCHAIN.xcode, minor),
  };
}

// How the temp app is created; driven by which flags the bundled CLI accepts.
function initModeFor(minor) {
  if (minor >= 75) return 'community'; // npx @react-native-community/cli init
  if (minor >= 73) return 'legacy-pm'; // react-native init, CLI 12/13 (--pm, --install-pods)
  if (minor >= 62) return 'legacy-skip-install'; // CLI 4–11 (--skip-install)
  return 'legacy'; // CLI 2/3: no install flags at all
}

// Returns an error message, or null when the combination is buildable.
function validate({minor, platform, newArch, iosPackageManager}) {
  if (platform !== 'android' && platform !== 'ios') {
    return `Unknown platform "${platform}" (expected android or ios)`;
  }
  if (minor < MIN_SUPPORTED[platform]) {
    return `RN 0.${minor} is below the lowest version that builds for ${platform} on current runners (0.${MIN_SUPPORTED[platform]})`;
  }
  if (newArch === '1' && minor < FEATURES.newArchFrom) {
    return `New architecture is not available before RN 0.${FEATURES.newArchFrom} (got 0.${minor})`;
  }
  if (newArch === '0' && minor > FEATURES.oldArchUntil) {
    return `Old architecture was removed after RN 0.${FEATURES.oldArchUntil} (got 0.${minor})`;
  }
  if (newArch !== '0' && newArch !== '1') {
    return `new-arch must be 1 or 0 (got "${newArch}")`;
  }
  if (platform === 'ios') {
    if (iosPackageManager !== 'pods' && iosPackageManager !== 'spm') {
      return `ios-package-manager must be pods or spm (got "${iosPackageManager}")`;
    }
    if (iosPackageManager === 'spm' && minor < FEATURES.spmFrom) {
      return `SPM is not available before RN 0.${FEATURES.spmFrom} (got 0.${minor})`;
    }
  }
  return null;
}

module.exports = {TOOLCHAIN, MIN_SUPPORTED, FEATURES, toolchainFor, initModeFor, validate};
