/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

// Generates the framework doc pages from the corresponding in-repo READMEs,
// so each framework's README is the one copy to edit and renders both on
// GitHub and on this site. Required by docusaurus.config.js so it runs for
// every Docusaurus command; the generated pages are gitignored.

const fs = require('fs');
const path = require('path');

const FRAMEWORKS = [
  { repoPath: 'FBSimulatorControl', id: 'fbsimulatorcontrol' },
  { repoPath: 'FBDeviceControl', id: 'fbdevicecontrol' },
];

const websiteDir = path.join(__dirname, '..');
const repoRoot = path.join(websiteDir, '..');

for (const { repoPath, id } of FRAMEWORKS) {
  const readmePath = path.join(repoRoot, repoPath, 'README.md');
  let text = fs.readFileSync(readmePath, 'utf8');

  // The leading H1 becomes the page title, so it is not rendered twice.
  const titleMatch = text.match(/^# (.+)\n/);
  if (!titleMatch) {
    throw new Error(`${readmePath} does not start with an H1 title`);
  }
  const title = titleMatch[1].replace(/`/g, '');
  text = text.slice(titleMatch[0].length);

  // Repo-relative links only resolve on GitHub; absolute links and pure
  // anchors are left alone.
  text = text.replace(/\]\((?!https?:\/\/|#)([^)]+)\)/g, (_, target) => {
    const resolved = path.posix.normalize(path.posix.join(repoPath, target));
    return `](https://github.com/facebook/idb/tree/main/${resolved})`;
  });

  const generated = [
    '---',
    `id: ${id}`,
    `title: ${title}`,
    '---',
    '',
    `{/* Generated from ${repoPath}/README.md by scripts/generate-framework-docs.js — edit the README, not this file. */}`,
    '',
    text,
  ].join('\n');

  const outPath = path.join(websiteDir, 'docs', 'idb', `${id}.mdx`);
  fs.writeFileSync(outPath, generated);
  console.log(`generated docs/idb/${id}.mdx from ${repoPath}/README.md`);
}
