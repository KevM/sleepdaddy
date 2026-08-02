#!/usr/bin/env node
// Vercel build step for the static site.
//
// Copies the site into dist/ and substitutes the TESTFLIGHT_URL placeholder in
// the HTML on the way through. Set a TESTFLIGHT_URL environment variable on the
// Vercel project to point the "Join TestFlight" buttons at the real beta link.
// Until one exists, they fall back to the on-page #download anchor, which
// main.js handles.
//
// Building into dist/ rather than rewriting the sources in place keeps a local
// `vercel build` from dirtying the working tree. This replaces the previous
// `sed -i` build command, which was GNU-only and failed on macOS.

const fs = require('node:fs');
const path = require('node:path');

const PLACEHOLDER = 'TESTFLIGHT_URL';
const FALLBACK = 'index.html#download';
const OUT_DIR = 'dist';

// Build machinery, not site content.
const EXCLUDE = new Set([OUT_DIR, 'build.js', 'vercel.json', '.gitignore', '.vercel']);

const src = __dirname;
const out = path.join(src, OUT_DIR);
const url = process.env.TESTFLIGHT_URL || FALLBACK;

fs.rmSync(out, { recursive: true, force: true });
fs.mkdirSync(out, { recursive: true });

let copied = 0;
let replaced = 0;

for (const entry of fs.readdirSync(src, { withFileTypes: true })) {
  if (EXCLUDE.has(entry.name)) continue;

  const from = path.join(src, entry.name);
  const to = path.join(out, entry.name);

  if (entry.isDirectory()) {
    fs.cpSync(from, to, { recursive: true });
    copied++;
    continue;
  }

  if (entry.name.endsWith('.html')) {
    const html = fs.readFileSync(from, 'utf8');
    const hits = html.split(PLACEHOLDER).length - 1;
    fs.writeFileSync(to, html.split(PLACEHOLDER).join(url));
    replaced += hits;
  } else {
    fs.copyFileSync(from, to);
  }

  copied++;
}

console.log(`Built ${copied} entries into ${OUT_DIR}/`);
console.log(`Replaced ${replaced} ${PLACEHOLDER} placeholder(s) with ${url}`);

if (replaced === 0) {
  console.warn(`Warning: no ${PLACEHOLDER} placeholders found — check the HTML sources.`);
}
