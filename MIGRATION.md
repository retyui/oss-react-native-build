# Migrating the 4 repos

`build-app` keeps the input names of the per-repo `.github/actions/build-app`
(`rn-ver`, `platform`, `new-arch-enabled`, `module-to-install`, `android-arch`,
`ios-package-manager`, `store-artifacts`, `node-version`, `java-version`), the app
name (`Example<rn-ver><newArch>App`) and the artifact name
(`<platform>-<rn-ver>-newArch-<0|1>`), so existing E2E steps keep working.

Differences:
- `new-arch-enabled` defaults to `auto` (= `1` on RN ≥ 0.68, `0` below) instead of `1`.
- Toolchain (Node / Java / Ruby / Xcode) is picked per RN version. Passing
  `node-version` / `java-version` still overrides it.
- The SPM artifact name gets a `-spm` suffix (it was not uploaded before).
- `module-to-install` defaults to `${{ github.workspace }}`.

## callstack/react-native-image-editor — `.github/workflows/main.yml`

```diff
-      - uses: ./.github/actions/build-app
+      - uses: retyui/oss-react-native-build/build-app@v1
         with:
-          arch: arm64-v8a
+          android-arch: arm64-v8a
```
(`arch` was never an input of the old action, so all 4 ABIs were built.)
Then delete `.github/actions/build-app` and `lock-java-ver`, `lock-ruby-ver` (if unused).

## retyui/react-native-detect-maestro — `ci.yaml`, `e2e.yaml`

```diff
-      - uses: ./.github/actions/build-app
+      - uses: retyui/oss-react-native-build/build-app@v1
         with:
           ...
+          app-file: .maestro/_App.js
```
The old action hardcoded the `.maestro/_App.js` copy and the package name;
both are now generic (`app-file` input, name read from `package.json`).

## retyui/react-native-fbtee — `build_android.yaml`

Replace the setup-java / setup-node / "Build Tmp React Native App" steps with:

```yaml
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      - uses: retyui/oss-react-native-build/build-app@v1
        with:
          platform: android
          rn-ver: ${{ matrix.rn_ver }}
          new-arch-enabled: ${{ matrix.new_arch_enabled }}
          android-arch: x86_64
```

## retyui/react-native-widget-picker — `build_android.yaml` (`build_app` job)

```yaml
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
      - uses: retyui/oss-react-native-build/build-app@v1
        with:
          platform: android
          rn-ver: ${{ matrix.rn_ver }}
          new-arch-enabled: 1
          android-arch: x86_64
```
