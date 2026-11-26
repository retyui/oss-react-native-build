#!/usr/bin/env node
'use strict';

// Resolves an RN version spec (0.88, 0.88.1, 0.86-stable, latest, next, 0.89.0-rc.3)
// to an exact version, validates the requested build and prints the toolchain.
//
// Env in:  RN_VERSION, PLATFORM, NEW_ARCH, IOS_PACKAGE_MANAGER
//          NODE_VERSION / JAVA_VERSION / RUBY_VERSION / XCODE_VERSION (optional overrides)
// Out:     key=value lines appended to $GITHUB_OUTPUT (or stdout when unset)

const {execFileSync} = require('child_process');
const fs = require('fs');
const {toolchainFor, initModeFor, validate} = require('./rules');

function resolveExact(spec) {
  const raw = execFileSync('npm', ['view', `react-native@${spec}`, 'version', '--json'], {
    encoding: 'utf8',
  }).trim();
  if (!raw) throw new Error(`No react-native version matches "${spec}"`);
  const parsed = JSON.parse(raw);
  // A range returns an ascending array; take the newest.
  return Array.isArray(parsed) ? parsed[parsed.length - 1] : parsed;
}

function fail(message) {
  console.log(`::error title=Unsupported React Native build::${message}`);
  process.exit(1);
}

const spec = (process.env.RN_VERSION || '').trim();
if (!spec) fail('rn-version is required');

let version;
try {
  version = resolveExact(spec);
} catch (e) {
  fail(e.message);
}

const [major, minorStr] = version.split('.');
const minor = Number(minorStr);
if (major !== '0' || Number.isNaN(minor)) fail(`Unexpected react-native version "${version}"`);

const platform = (process.env.PLATFORM || '').trim();
let newArch = (process.env.NEW_ARCH || 'auto').trim();
// auto: new architecture wherever it exists
if (newArch === 'auto') newArch = minor >= 68 ? '1' : '0';
const iosPackageManager = (process.env.IOS_PACKAGE_MANAGER || 'pods').trim();

const error = validate({minor, platform, newArch, iosPackageManager});
if (error) fail(error);

const tc = toolchainFor(minor);
const out = {
  'rn-version': version,
  'rn-minor': String(minor),
  'new-arch': newArch,
  'init-mode': initModeFor(minor),
  'node-version': process.env.NODE_VERSION || tc.node,
  'java-version': process.env.JAVA_VERSION || tc.java,
  'ruby-version': process.env.RUBY_VERSION || tc.ruby,
  'xcode-version': process.env.XCODE_VERSION || tc.xcode,
};

const lines = Object.entries(out).map(([k, v]) => `${k}=${v}`);
console.log(`Resolved react-native@${spec} -> ${version}\n${lines.join('\n')}`);
if (process.env.GITHUB_OUTPUT) {
  fs.appendFileSync(process.env.GITHUB_OUTPUT, lines.join('\n') + '\n');
}
