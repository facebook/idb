/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

// Docusaurus plugin that parse-checks every fenced mermaid block in the docs.
// Mermaid renders client-side, so a syntax error otherwise builds green and
// only fails in the browser. Registered in docusaurus.config.js; a parse
// failure fails the build with the offending file and mermaid's error.

const fs = require('fs');
const path = require('path');

function collectMermaidBlocks(docsDir) {
  const blocks = [];
  const entries = fs.readdirSync(docsDir, { recursive: true });
  for (const entry of entries) {
    if (!/\.mdx?$/.test(entry)) {
      continue;
    }
    const filePath = path.join(docsDir, entry.toString());
    const text = fs.readFileSync(filePath, 'utf8');
    const re = /```mermaid\n([\s\S]*?)```/g;
    let match;
    let index = 0;
    while ((match = re.exec(text)) !== null) {
      index += 1;
      blocks.push({ file: path.relative(docsDir, filePath), index, code: match[1] });
    }
  }
  return blocks;
}

async function loadMermaidParser() {
  // Mermaid expects a DOM. Parsing does not need one, except that the
  // flowchart parser sanitizes labels through DOMPurify, which is inert
  // without a document — stub the handful of methods it would otherwise
  // be missing so parse() can run under Node.
  const dompurify = (await import('dompurify')).default;
  for (const method of ['sanitize', 'addHook', 'removeHook']) {
    if (typeof dompurify[method] !== 'function') {
      dompurify[method] = method === 'sanitize' ? (value) => value : () => {};
    }
  }
  const mermaid = (await import('mermaid')).default;
  mermaid.initialize({ startOnLoad: false, suppressErrorRendering: true });
  return mermaid;
}

module.exports = function validateMermaidPlugin(context) {
  return {
    name: 'validate-mermaid',
    async loadContent() {
      const docsDir = path.join(context.siteDir, 'docs');
      const blocks = collectMermaidBlocks(docsDir);
      if (blocks.length === 0) {
        return;
      }
      const mermaid = await loadMermaidParser();
      const failures = [];
      for (const block of blocks) {
        try {
          await mermaid.parse(block.code);
        } catch (error) {
          failures.push(
            `${block.file} (mermaid block #${block.index}):\n${error.message || error}`
          );
        }
      }
      if (failures.length > 0) {
        throw new Error(
          `Mermaid parse check failed for ${failures.length} diagram(s):\n\n` +
            failures.join('\n\n')
        );
      }
      console.log(`validated ${blocks.length} mermaid diagram(s)`);
    },
  };
};
