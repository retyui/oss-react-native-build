# oss-react-native-build

Reusable GitHub composite actions that build a React Native library inside a fresh
temp app, for **RN 0.63 – 0.89 (Android from 0.65)**, on Android and iOS,
old / new architecture, CocoaPods / SPM.

| Action | What it does |
| --- | --- |
| [`build-app`](build-app/action.yml) | Sets up the toolchain, creates a temp app with `init`, installs your library, builds a Release `.apk` / simulator `.app`, optionally uploads it |
| [`setup-toolchain`](setup-toolchain/action.yml) | Only installs the Node.js / Java / Ruby / Xcode / CocoaPods versions that a given RN version needs (for your own custom steps) |

## Usage

```yaml
jobs:
  build-android:
    runs-on: ubuntu-24.04
    strategy:
      fail-fast: false
      matrix:
        rn_ver: [0.86.3, 0.87.1, 0.88.1, 0.89.0-rc.3]
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      - uses: retyui/oss-react-native-build/build-app@v1
        with:
          platform: android
          rn-ver: ${{ matrix.rn_ver }}
          android-arch: x86_64

  build-ios:
    runs-on: macos-15
    strategy:
      fail-fast: false
      matrix:
        rn_ver: [0.87.1, 0.88.1, 0.89.0-rc.3]
        ios-package-manager: [pods, spm]
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      - uses: retyui/oss-react-native-build/build-app@v1
        with:
          platform: ios
          rn-ver: ${{ matrix.rn_ver }}
          ios-package-manager: ${{ matrix.ios-package-manager }}
```

### `build-app` inputs

| Input | Default | Notes |
| --- | --- | --- |
| `rn-ver` | **required** | `0.88.1`, `0.88`, `0.86-stable`, `latest`, `next`, `0.89.0-rc.3`. A minor (`0.88`) resolves to its newest patch |
| `platform` | **required** | `android` / `ios` |
| `module-to-install` | `${{ github.workspace }}` | Path to the library; `none` builds the bare template app |
| `new-arch-enabled` | `auto` | `1`, `0`, or `auto` (= `1` on RN ≥ 0.68) |
| `ios-package-manager` | `pods` | `pods` / `spm` (RN ≥ 0.87) |
| `android-arch` | `armeabi-v7a,arm64-v8a,x86,x86_64` | Pass one ABI (`x86_64`) for faster builds |
| `app-file` | – | File that replaces the template's `App.js` / `App.tsx` |
| `store-artifacts` | `false` | Upload the `.apk` / `.app` |
| `node-version`, `java-version`, `ruby-version`, `xcode-version` | auto | Override the picked toolchain |

Outputs: `rn-version` (exact), `new-arch`, `app-dir`, `app-path`.

Invalid combinations fail immediately with a clear error instead of a long build:
new arch before 0.68, old arch after 0.81, SPM before 0.87.

## Toolchain per RN version

All in [`scripts/rules.js`](scripts/rules.js) — the only file to touch when a new RN
version or runner image changes something.

| RN | Node | Java | Xcode (macos-15) | `init` |
| --- | --- | --- | --- | --- |
| 0.63 – 0.64 (iOS only) | 16 | – | 16.2 | `react-native init --skip-install --npm` |
| 0.65 – 0.66 | 16 | 8 | 16.2 | 〃 |
| 0.67 | 16 | 11 | 16.2 | 〃 |
| 0.68 – 0.72 | 18 | 11 | 16.2 | 〃 |
| 0.73 – 0.74 | 20 | 17 | 16.2 | `react-native init --pm yarn --install-pods false` |
| 0.75 | 20 | 17 | 16.2 | `@react-native-community/cli init` |
| 0.76 – 0.80 | 20 | 17 | 16.4 | 〃 |
| 0.81 – 0.86 | 22 | 17 | 16.4 | 〃 |
| 0.87 + | 24 | 17 | 16.4 | 〃 |

Ruby is 3.3 with the latest CocoaPods for every version; the template `Gemfile`s
(which pin Ruby 2.7 / old CocoaPods) are not used.

### Lowest supported versions

Old RN is built with the modern runner toolchain. RN's sources are not patched; the action
only works around infrastructure that no longer exists or newer compiler defaults:

- `boostorg.jfrog.io` (boost for RN ≤ 0.7x) is gone → the boost URL (iOS podspec, Android
  `ReactAndroid/build.gradle`) is pointed at the official mirror `archives.boost.io`
  (same tarball, same checksum).
- Xcode 16 clang makes old Yoga/RN C++ fail with `-Werror,-Wbitwise-instead-of-logical`
  → `-Wno-error=bitwise-instead-of-logical` for RN < 0.69.
- Xcode 16 libc++ removed `std::unary_function` (boost 1.76 in RN 0.68) →
  `-D_LIBCPP_ENABLE_CXX17_REMOVED_UNARY_BINARY_FUNCTION` for RN < 0.69.
- Maven Central rate-limits GitHub runners (HTTP 429) → a Gradle init script resolves it
  from Google's mirror `maven-central.storage-download.googleapis.com`.
- Podfiles of RN ≤ 0.70 enable Flipper unconditionally; its pods no longer build with
  Xcode 16 → Flipper is turned off in the generated Podfile.
- Hermes built from source (new arch, RN < 0.71) misses `<cstdint>` for GCC 13 →
  `CXXFLAGS=-include cstdint`.
- yarn 1 `ignore-engines`: new releases of old transitive deps require newer Node.

| Platform | Lowest RN | Why not lower |
| --- | --- | --- |
| Android | **0.65** | 0.62 – 0.64 need fresco 2.2.0 / flipper 0.33.1, published only on the shut-down jcenter. 0.60 – 0.61 fail Metro's Release bundling |
| iOS | **0.63** | 0.60 – 0.62 fail Metro's Release bundling |

Below that, the action fails right away with an explanation (`MIN_SUPPORTED` in
[`scripts/rules.js`](scripts/rules.js)).

## Self-test

[`.github/workflows/ci.yml`](.github/workflows/ci.yml) builds the bare template app
(`module-to-install: none`) for every supported minor up to npm `latest` (+ `next` when it is a newer rc) × every valid
arch / package manager (39 Android + 44 iOS jobs). It also runs every 3 weeks to catch
runner-image changes. Library-specific builds are covered by each library's own CI.

New RN releases and release candidates are picked up automatically from npm dist-tags.
