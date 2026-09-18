/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

// Builds the demos page from a manifest an end-to-end run produced with
// CI/generate_documentation.py. Called from docusaurus.config.js so it runs for
// every Docusaurus command; the page, the manifest it imports and the media it
// serves are all gitignored.
//
// IDB_DEMOS_DIR names the run to publish, and is the only place a run is read
// from. Without it the site still builds and the page has nothing on it, which
// is what a plain checkout gets. With it the demos were asked for, so a
// manifest that is missing or malformed fails the build rather than quietly
// publishing an empty page.

const fs = require('fs');
const path = require('path');

const DEMOS_DIR_ENV = 'IDB_DEMOS_DIR';
const MANIFEST_NAME = 'demos.json';
const SERVED_PATH = '/demos/media';

// The one place a demo's source link may point: the published repository, at
// a commit. Anything else in a generated page's href is refused here rather
// than rendered into the site.
const SOURCE_PREFIX = 'https://github.com/facebook/idb/blob/';

const EMPTY = {demos: []};

const STREAM_KEYS = ['stdout', 'stderr'];

// The numbers the page reads back out of the manifest without checking them:
// each command's exit code, offset and duration, and each clip's size and
// length. A manifest missing one of these renders NaN or throws in the
// browser, so it fails the build here instead.
const COMMAND_NUMBERS = ['returncode', 'start', 'finished', 'seconds'];
const VIDEO_NUMBERS = ['width', 'height', 'duration'];
const TERMINAL_NUMBERS = ['columns', 'rows', 'duration'];

function sourceDirectory(env) {
  const named = env[DEMOS_DIR_ENV];
  return named ? path.resolve(named) : null;
}

function isNumber(value) {
  return typeof value === 'number' && Number.isFinite(value);
}

// Media is copied by joining the manifest's path onto the run's directory, so
// a path that is absolute, or that climbs out of the run, is refused rather
// than read from wherever it points.
function inside(relative) {
  const normalised = path.normalize(relative);
  return (
    !path.isAbsolute(normalised) &&
    normalised !== '..' &&
    !normalised.startsWith(`..${path.sep}`)
  );
}

// A stream is its size plus either the text it printed or, when the output was
// not text, the digest standing in for it. Half of one renders `undefined` in
// the browser, so a stream that lost its content fails the build here.
function whole(stream) {
  if (typeof stream !== 'object' || stream === null || !isNumber(stream.bytes)) {
    return false;
  }
  return stream.binary
    ? typeof stream.sha256 === 'string'
    : typeof stream.text === 'string';
}

function problemsWithClip(name, video) {
  const problems = [];
  if (typeof video.source !== 'string' || video.source === '') {
    problems.push(`${name} has a clip with no source`);
  } else if (!inside(video.source)) {
    problems.push(`${name} has a clip at ${video.source}, outside the run`);
  }
  if (typeof video.type !== 'string' || video.type === '') {
    problems.push(`${name} has a clip with no type`);
  }
  for (const key of VIDEO_NUMBERS) {
    if (!isNumber(video[key])) {
      problems.push(`${name} has a clip with no ${key}`);
    }
  }
  return problems;
}

// The terminal session the page plays beside the clip. Every demo has one,
// whether or not its clip could be cut, because it is written from the trace
// rather than from the recording.
function problemsWithTerminal(name, terminal) {
  const problems = [];
  if (typeof terminal.source !== 'string' || terminal.source === '') {
    problems.push(`${name} has a terminal session with no source`);
  } else if (!inside(terminal.source)) {
    problems.push(
      `${name} has a terminal session at ${terminal.source}, outside the run`
    );
  }
  if (typeof terminal.type !== 'string' || terminal.type === '') {
    problems.push(`${name} has a terminal session with no type`);
  }
  for (const key of TERMINAL_NUMBERS) {
    if (!isNumber(terminal[key])) {
      problems.push(`${name} has a terminal session with no ${key}`);
    }
  }
  return problems;
}

// Where the test that performed the demo is declared. A run that recorded no
// declaration publishes none, and one that did not know which commit it
// tested publishes the file and line without a link.
function problemsWithSource(name, source) {
  const problems = [];
  if (typeof source.path !== 'string' || source.path === '') {
    problems.push(`${name} names a source file it cannot link`);
  }
  if (!isNumber(source.line)) {
    problems.push(`${name} has a source with no line`);
  }
  const url = source.url;
  if (url !== null && url !== undefined && !String(url).startsWith(SOURCE_PREFIX)) {
    problems.push(`${name} links its source somewhere other than ${SOURCE_PREFIX}`);
  }
  return problems;
}

// What the test made of a step's output, published beside it: text, and the
// pieces of the output it names. A note the page cannot show fails the build
// rather than rendering as `undefined`.
function problemsWithNotes(name, notes) {
  if (notes === undefined) {
    return [];
  }
  if (!Array.isArray(notes)) {
    return [`${name} has a step whose notes are not a list`];
  }
  const problems = [];
  for (const note of notes) {
    const fields = note || {};
    if (typeof fields.text !== 'string' || fields.text === '') {
      problems.push(`${name} has a step with a note that says nothing`);
    }
    if (
      !Array.isArray(fields.marks) ||
      !fields.marks.every((mark) => typeof mark === 'string')
    ) {
      problems.push(`${name} has a step with a note that marks something that is not text`);
    }
  }
  return problems;
}

function problemsWithCommands(name, commands) {
  const problems = [];
  for (const command of commands) {
    const fields = command || {};
    const argv = fields.argv;
    if (
      typeof fields.step !== 'string' ||
      !Array.isArray(argv) ||
      argv.length === 0 ||
      !argv.every((argument) => typeof argument === 'string')
    ) {
      problems.push(`${name} has a command with no step or argv`);
    }
    for (const key of COMMAND_NUMBERS) {
      if (!isNumber(fields[key])) {
        problems.push(`${name} has a command with no ${key}`);
      }
    }
    for (const key of STREAM_KEYS) {
      if (!whole(fields[key])) {
        problems.push(`${name} has a command with no ${key}`);
      }
    }
    problems.push(...problemsWithNotes(name, fields.notes));
  }
  return problems;
}

// Everything the site serves out of a run: each demo's clip, when it has
// one, its terminal session, and its poster.
function media(manifest) {
  return manifest.demos
    .flatMap((demo) => [
      ((demo || {}).video || {}).source,
      ((demo || {}).terminal || {}).source,
      (demo || {}).poster,
    ])
    .filter(Boolean);
}

// The site serves all of it from one directory, so two files of the run that
// share a name would publish as a single URL with one overwriting the other.
function problemsWithMedia(manifest) {
  const problems = [];
  const byName = new Map();
  for (const source of media(manifest)) {
    if (typeof source !== 'string') {
      continue;
    }
    const name = path.basename(source);
    const first = byName.get(name);
    if (first === undefined) {
      byName.set(name, source);
    } else if (first !== source) {
      problems.push(`${source} and ${first} are both served as ${name}`);
    }
  }
  return problems;
}

function problemsWith(manifest) {
  if (!manifest || !Array.isArray(manifest.demos)) {
    return ['it has no demos array'];
  }
  const problems = [];
  for (const demo of manifest.demos) {
    const name = demo && demo.slug ? demo.slug : JSON.stringify(demo);
    for (const key of ['slug', 'title', 'summary', 'test']) {
      if (typeof (demo || {})[key] !== 'string' || demo[key] === '') {
        problems.push(`${name} has no ${key}`);
      }
    }
    const video = (demo || {}).video;
    // A demo whose clip could not be cut publishes its transcript and poster,
    // so a missing clip is a demo to publish rather than a manifest to refuse.
    if (video !== null && video !== undefined) {
      problems.push(...problemsWithClip(name, video));
    }
    const source = (demo || {}).source;
    if (source !== null && source !== undefined) {
      problems.push(...problemsWithSource(name, source));
    }
    const terminal = (demo || {}).terminal;
    if (typeof terminal !== 'object' || terminal === null) {
      problems.push(`${name} publishes no terminal session`);
    } else {
      problems.push(...problemsWithTerminal(name, terminal));
    }
    const poster = (demo || {}).poster;
    if (poster !== null && poster !== undefined) {
      if (typeof poster !== 'string' || !inside(poster)) {
        problems.push(`${name} has a poster outside the run`);
      }
    }
    if (!Array.isArray((demo || {}).commands) || demo.commands.length === 0) {
      problems.push(`${name} publishes no commands`);
      continue;
    }
    problems.push(...problemsWithCommands(name, demo.commands));
  }
  problems.push(...problemsWithMedia(manifest));
  return problems;
}

function readManifest(directory) {
  const manifest = path.join(directory, MANIFEST_NAME);
  if (!fs.existsSync(manifest)) {
    throw new Error(
      `${DEMOS_DIR_ENV} names ${directory}, which holds no ${MANIFEST_NAME}`
    );
  }
  let parsed;
  try {
    parsed = JSON.parse(fs.readFileSync(manifest, 'utf8'));
  } catch (error) {
    throw new Error(`${manifest} is not valid JSON: ${error.message}`);
  }
  const problems = problemsWith(parsed);
  // Looking for the files is worth doing only once the manifest that names
  // them holds up, and saying which one is missing beats the copy failing on
  // it with nothing but a path.
  if (problems.length === 0) {
    problems.push(
      ...media(parsed)
        .filter((relative) => !fs.existsSync(path.join(directory, relative)))
        .map((relative) => `${relative} is named but the run does not hold it`)
    );
  }
  if (problems.length > 0) {
    throw new Error(`${manifest} cannot be published:\n  ${problems.join('\n  ')}`);
  }
  return parsed;
}

// Manifest paths are relative to the run's output; the site serves them from
// one place, so they are rewritten once here rather than in the component.
function served(source) {
  return typeof source === 'string' ? `${SERVED_PATH}/${path.basename(source)}` : null;
}

function copyMedia(source, websiteDir, manifest) {
  const destination = path.join(websiteDir, 'static', 'demos', 'media');
  fs.rmSync(path.join(websiteDir, 'static', 'demos'), {recursive: true, force: true});
  const wanted = media(manifest);
  // A run with neither a clip nor a poster, or no run at all, leaves the site
  // with nothing to serve, so the source is never read.
  if (wanted.length === 0) {
    return;
  }
  fs.mkdirSync(destination, {recursive: true});
  for (const relative of wanted) {
    fs.copyFileSync(
      path.join(source, relative),
      path.join(destination, path.basename(relative))
    );
  }
}

function page() {
  return [
    '---',
    'id: demos',
    'title: Demos',
    '---',
    '',
    '{/* Generated from an end-to-end run by scripts/generate-demos.js — do not edit. */}',
    '',
    "import DemoTranscript from '@site/src/components/DemoTranscript';",
    "import manifest from '@site/src/demos/demos.json';",
    '',
    'Every demo below is one end-to-end test. The commands are the ones the test',
    'ran against a real simulator, and the output is what `idb` printed, with',
    'run-specific values replaced so two runs read the same. A demo whose test',
    'fails is never published.',
    '',
    '<DemoTranscript {...manifest} />',
    '',
  ].join('\n');
}

function generate(options) {
  const settings = options || {};
  const env = settings.env || process.env;
  const websiteDir = settings.websiteDir || path.join(__dirname, '..');
  const directory = sourceDirectory(env);
  const manifest = directory === null ? EMPTY : readManifest(directory);

  copyMedia(directory, websiteDir, manifest);
  const published = {
    demos: manifest.demos.map((demo) => ({
      ...demo,
      poster: served(demo.poster),
      video: demo.video
        ? {...demo.video, source: served(demo.video.source)}
        : null,
      terminal: {...demo.terminal, source: served(demo.terminal.source)},
    })),
  };

  const manifestPath = path.join(websiteDir, 'src', 'demos', MANIFEST_NAME);
  fs.mkdirSync(path.dirname(manifestPath), {recursive: true});
  fs.writeFileSync(manifestPath, `${JSON.stringify(published, null, 2)}\n`);

  const pagePath = path.join(websiteDir, 'docs', 'idb', 'demos.mdx');
  fs.mkdirSync(path.dirname(pagePath), {recursive: true});
  fs.writeFileSync(pagePath, page());

  console.log(
    directory === null
      ? `generated docs/idb/demos.mdx with no demos, as no ${DEMOS_DIR_ENV} names a run`
      : `generated docs/idb/demos.mdx with ${published.demos.length} demo(s) from ${directory}`
  );
  return published;
}

module.exports = {generate, problemsWith, readManifest, sourceDirectory};

if (require.main === module) {
  generate();
}
