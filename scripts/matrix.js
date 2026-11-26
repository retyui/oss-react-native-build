#!/usr/bin/env node
'use strict';

// Prints the CI matrix: every RN minor from the lowest supported one up to npm's
// `latest`, plus `next` when it is a newer release candidate, times every valid
// platform / arch / iOS package manager.
//
// Usage: node scripts/matrix.js

const fs = require('fs');
const {execFileSync} = require('child_process');
const {FEATURES, MIN_SUPPORTED} = require('./rules');

const tags = JSON.parse(
  execFileSync('npm', ['view', 'react-native', 'dist-tags', '--json'], {encoding: 'utf8'}),
);
const minorOf = (version) => Number(version.split('.')[1]);

const FIRST = Math.min(...Object.values(MIN_SUPPORTED));
const LAST = minorOf(tags.latest); // e.g. 0.88.1 -> 88

const versions = [];
for (let m = FIRST; m <= LAST; m++) versions.push({spec: `0.${m}`, minor: m});
// `next` lags behind `latest` between release cycles (e.g. 0.88.0-rc.5 after 0.88.1)
if (tags.next && minorOf(tags.next) > LAST) versions.push({spec: tags.next, minor: minorOf(tags.next)});
console.log(`latest: ${tags.latest}, next: ${tags.next}`);

const android = [];
const ios = [];
for (const {spec, minor} of versions) {
  const arches = [];
  if (minor <= FEATURES.oldArchUntil) arches.push('0');
  if (minor >= FEATURES.newArchFrom) arches.push('1');

  for (const arch of arches) {
    if (minor >= MIN_SUPPORTED.android) android.push({rn: spec, 'new-arch': arch});
    if (minor >= MIN_SUPPORTED.ios) {
      ios.push({rn: spec, 'new-arch': arch, pm: 'pods'});
      if (arch === '1' && minor >= FEATURES.spmFrom) ios.push({rn: spec, 'new-arch': arch, pm: 'spm'});
    }
  }
}

// Optional ONLY="android:0.65:0 ios:0.68:1:pods ...": keep just these jobs
// (platform:rn:newArch[:pm]) to re-check a few failures quickly.
const only = (process.env.ONLY || '').split(/[\s,]+/).filter(Boolean);
if (only.length) {
  const key = (platform, job) => [platform, job.rn, job['new-arch'], job.pm].filter(Boolean).join(':');
  const keep = (platform) => (job) => only.includes(key(platform, job));
  android.splice(0, android.length, ...android.filter(keep('android')));
  ios.splice(0, ios.length, ...ios.filter(keep('ios')));
  const found = [...android.map((j) => key('android', j)), ...ios.map((j) => key('ios', j))];
  for (const k of only) if (!found.includes(k)) console.log(`::warning::ONLY: no such job ${k}`);
}

const out = `android=${JSON.stringify({include: android})}\nios=${JSON.stringify({include: ios})}\n`;
console.log(`android: ${android.length} jobs, ios: ${ios.length} jobs`);
if (process.env.GITHUB_OUTPUT) fs.appendFileSync(process.env.GITHUB_OUTPUT, out);
else console.log(out);
