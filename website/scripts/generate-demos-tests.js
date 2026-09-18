/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

// Tests for scripts/generate-demos.js, run with `node scripts/generate-demos-tests.js`.
// Plain Node and plain asserts, so they run without installing the site.

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');

const {generate} = require('./generate-demos');

const SLUG = 'open-a-url';
const TEST = 'EndToEndTests.test_system.OpenUrlTests.test_opening_a_url';
const OTHER_SLUG = 'scroll-a-list';
const OTHER_TEST = 'EndToEndTests.test_accessibility.AccessibilityTests.test_scroll';

// Each demo names its own clip, so the media a run holds is one file per demo
// rather than one recording every demo seeks into.
function demoFixture(slug, test, duration) {
  return {
    slug,
    title: 'Open a URL on a simulator',
    summary: 'Hand a URL to the simulator and let it pick the app.',
    test,
    source: {
      path: 'EndToEndTests/test_system.py',
      line: 31,
      sha: '0123456789abcdef0123456789abcdef01234567',
      url:
        'https://github.com/facebook/idb/blob/' +
        '0123456789abcdef0123456789abcdef01234567/' +
        'EndToEndTests/test_system.py#L31',
    },
    poster: `media/${slug}.png`,
    video: {
      source: `media/${slug}.mp4`,
      type: 'video/mp4',
      width: 590,
      height: 1278,
      duration,
    },
    terminal: {
      source: `media/${slug}.cast`,
      type: 'application/x-asciicast',
      columns: 100,
      rows: 24,
      duration,
    },
    commands: [
      {
        step: 'Open a URL on the simulator',
        argv: ['idb', 'open', 'https://example.com'],
        returncode: 0,
        start: 4.58,
        finished: 5.0,
        seconds: 0.42,
        stdout: {bytes: 0, text: '', truncated: false},
        stderr: {bytes: 0, text: '', truncated: false},
      },
    ],
  };
}

function manifestFixture(overrides) {
  return {
    demos: [
      demoFixture(SLUG, TEST, 7.0),
      demoFixture(OTHER_SLUG, OTHER_TEST, 12.5),
    ],
    ...overrides,
  };
}

function scratch(manifest) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'idb-demos-'));
  const websiteDir = path.join(root, 'website');
  const source = path.join(root, 'run');
  fs.mkdirSync(websiteDir, {recursive: true});
  if (manifest !== null) {
    fs.mkdirSync(path.join(source, 'media'), {recursive: true});
    fs.writeFileSync(
      path.join(source, 'demos.json'),
      JSON.stringify(manifest, null, 2)
    );
    for (const slug of [SLUG, OTHER_SLUG]) {
      fs.writeFileSync(path.join(source, 'media', `${slug}.mp4`), `a clip of ${slug}`);
      fs.writeFileSync(path.join(source, 'media', `${slug}.png`), 'a screenshot');
      fs.writeFileSync(
        path.join(source, 'media', `${slug}.cast`),
        `{"version": 2}\n[0.0, "o", "$ idb ${slug}\\r\\n"]\n`
      );
    }
  }
  return {websiteDir, source};
}

function run(websiteDir, env) {
  const log = console.log;
  console.log = () => {};
  try {
    return generate({env, websiteDir});
  } finally {
    console.log = log;
  }
}

function read(websiteDir, ...parts) {
  return fs.readFileSync(path.join(websiteDir, ...parts), 'utf8');
}

const tests = [];

function test(name, body) {
  tests.push({name, body});
}

test('publishes the demos a run produced', () => {
  const {websiteDir, source} = scratch(manifestFixture());

  const published = run(websiteDir, {IDB_DEMOS_DIR: source});

  assert.deepStrictEqual(
    published.demos.map((demo) => demo.slug),
    [SLUG, OTHER_SLUG]
  );
  assert.deepStrictEqual(
    JSON.parse(read(websiteDir, 'src', 'demos', 'demos.json')),
    published
  );
});

test('rewrites media paths to what the site serves', () => {
  const {websiteDir, source} = scratch(manifestFixture());

  const published = run(websiteDir, {IDB_DEMOS_DIR: source});

  assert.strictEqual(published.demos[0].video.source, '/demos/media/open-a-url.mp4');
  assert.strictEqual(published.demos[0].poster, '/demos/media/open-a-url.png');
});

test('gives each demo a clip of its own to play', () => {
  const {websiteDir, source} = scratch(manifestFixture());

  const published = run(websiteDir, {IDB_DEMOS_DIR: source});

  assert.deepStrictEqual(
    published.demos.map((demo) => [demo.video.source, demo.video.duration]),
    [
      ['/demos/media/open-a-url.mp4', 7.0],
      ['/demos/media/scroll-a-list.mp4', 12.5],
    ]
  );
});

test("serves each demo's clip and poster as static files", () => {
  const {websiteDir, source} = scratch(manifestFixture());

  run(websiteDir, {IDB_DEMOS_DIR: source});

  assert.deepStrictEqual(
    fs.readdirSync(path.join(websiteDir, 'static', 'demos', 'media')).sort(),
    [
      'open-a-url.cast',
      'open-a-url.mp4',
      'open-a-url.png',
      'scroll-a-list.cast',
      'scroll-a-list.mp4',
      'scroll-a-list.png',
    ]
  );
  assert.strictEqual(
    read(websiteDir, 'static', 'demos', 'media', 'scroll-a-list.mp4'),
    'a clip of scroll-a-list'
  );
});

test('the page imports the component and the manifest', () => {
  const {websiteDir, source} = scratch(manifestFixture());

  run(websiteDir, {IDB_DEMOS_DIR: source});
  const page = read(websiteDir, 'docs', 'idb', 'demos.mdx');

  assert.ok(page.includes('id: demos'), page);
  assert.ok(page.includes("from '@site/src/components/DemoTranscript'"), page);
  assert.ok(page.includes("from '@site/src/demos/demos.json'"), page);
  assert.ok(page.includes('<DemoTranscript {...manifest} />'), page);
});

test('publishes the transcript of a demo whose clip could not be cut', () => {
  const manifest = manifestFixture();
  manifest.demos[0].video = null;
  const {websiteDir, source} = scratch(manifest);

  const published = run(websiteDir, {IDB_DEMOS_DIR: source});

  assert.strictEqual(published.demos[0].video, null);
  assert.strictEqual(published.demos[0].poster, '/demos/media/open-a-url.png');
  assert.strictEqual(published.demos[1].video.source, '/demos/media/scroll-a-list.mp4');
  assert.ok(
    !fs.existsSync(path.join(websiteDir, 'static', 'demos', 'media', 'open-a-url.mp4'))
  );
});

test('forgets the media an earlier run published', () => {
  const {websiteDir, source} = scratch(manifestFixture());
  run(websiteDir, {IDB_DEMOS_DIR: source});

  const without = manifestFixture();
  for (const demo of without.demos) {
    demo.video = null;
    demo.poster = null;
  }
  fs.writeFileSync(
    path.join(source, 'demos.json'),
    JSON.stringify(without, null, 2)
  );
  run(websiteDir, {IDB_DEMOS_DIR: source});

  // Every demo still publishes its terminal session, which is written from
  // the run's trace rather than from a recording, so what a run with no clip
  // and no poster leaves behind is the sessions and nothing else.
  assert.deepStrictEqual(
    fs.readdirSync(path.join(websiteDir, 'static', 'demos', 'media')).sort(),
    ['open-a-url.cast', 'scroll-a-list.cast']
  );
});

test('builds an empty page when no run is beside the site', () => {
  const {websiteDir} = scratch(null);

  const published = run(websiteDir, {});

  assert.deepStrictEqual(published, {demos: []});
  assert.ok(read(websiteDir, 'docs', 'idb', 'demos.mdx').includes('id: demos'));
});

test('fails when the demos it was pointed at are not there', () => {
  const {websiteDir, source} = scratch(null);

  assert.throws(
    () => run(websiteDir, {IDB_DEMOS_DIR: source}),
    /holds no demos\.json/
  );
});

test('fails when the manifest it was pointed at is not JSON', () => {
  const {websiteDir, source} = scratch(manifestFixture());
  fs.writeFileSync(path.join(source, 'demos.json'), '{"demos": [');

  assert.throws(
    () => run(websiteDir, {IDB_DEMOS_DIR: source}),
    /demos\.json is not valid JSON/
  );
});

test('fails when the run does not hold the media it names', () => {
  const manifest = manifestFixture();
  manifest.demos[0].poster = 'media/never-taken.png';
  const {websiteDir, source} = scratch(manifest);

  assert.throws(
    () => run(websiteDir, {IDB_DEMOS_DIR: source}),
    /media\/never-taken\.png is named but the run does not hold it/
  );
});

test('fails when a demo publishes no commands', () => {
  const manifest = manifestFixture();
  manifest.demos[0].commands = [];
  const {websiteDir, source} = scratch(manifest);

  assert.throws(
    () => run(websiteDir, {IDB_DEMOS_DIR: source}),
    /publishes no commands/
  );
});

test('fails when a command lost the output it published', () => {
  const manifest = manifestFixture();
  delete manifest.demos[0].commands[0].stdout;
  const {websiteDir, source} = scratch(manifest);

  assert.throws(() => run(websiteDir, {IDB_DEMOS_DIR: source}), /no stdout/);
});

test('fails when a demo does not say which test performed it', () => {
  const manifest = manifestFixture();
  delete manifest.demos[0].test;
  const {websiteDir, source} = scratch(manifest);

  assert.throws(() => run(websiteDir, {IDB_DEMOS_DIR: source}), /has no test/);
});

test('fails when a demo names a clip with nothing to play', () => {
  const manifest = manifestFixture();
  delete manifest.demos[0].video.source;
  const {websiteDir, source} = scratch(manifest);

  assert.throws(
    () => run(websiteDir, {IDB_DEMOS_DIR: source}),
    /open-a-url has a clip with no source/
  );
});

test('plays a terminal session beside each demo', () => {
  const {websiteDir, source} = scratch(manifestFixture());

  const published = run(websiteDir, {IDB_DEMOS_DIR: source});

  assert.deepStrictEqual(
    published.demos.map((demo) => demo.terminal.source),
    ['/demos/media/open-a-url.cast', '/demos/media/scroll-a-list.cast']
  );
  assert.strictEqual(published.demos[0].terminal.type, 'application/x-asciicast');
});

test('plays a terminal session for a demo whose clip could not be cut', () => {
  const manifest = manifestFixture();
  manifest.demos[0].video = null;
  const {websiteDir, source} = scratch(manifest);

  const published = run(websiteDir, {IDB_DEMOS_DIR: source});

  assert.strictEqual(published.demos[0].video, null);
  assert.strictEqual(
    published.demos[0].terminal.source,
    '/demos/media/open-a-url.cast'
  );
  assert.strictEqual(
    read(websiteDir, 'static', 'demos', 'media', 'open-a-url.cast').split('\n')[0],
    '{"version": 2}'
  );
});

test('fails when a demo publishes no terminal session', () => {
  const manifest = manifestFixture();
  delete manifest.demos[0].terminal;
  const {websiteDir, source} = scratch(manifest);

  assert.throws(
    () => run(websiteDir, {IDB_DEMOS_DIR: source}),
    /open-a-url publishes no terminal session/
  );
});

test('fails when a terminal session has nothing to play', () => {
  const manifest = manifestFixture();
  delete manifest.demos[0].terminal.source;
  const {websiteDir, source} = scratch(manifest);

  assert.throws(
    () => run(websiteDir, {IDB_DEMOS_DIR: source}),
    /open-a-url has a terminal session with no source/
  );
});

test('fails when a terminal session lost a number the page reads', () => {
  for (const key of ['columns', 'rows', 'duration']) {
    const manifest = manifestFixture();
    delete manifest.demos[0].terminal[key];
    const {websiteDir, source} = scratch(manifest);

    assert.throws(
      () => run(websiteDir, {IDB_DEMOS_DIR: source}),
      new RegExp(`has a terminal session with no ${key}`),
      key
    );
  }
});

test('refuses a terminal session from outside the run', () => {
  const manifest = manifestFixture();
  manifest.demos[0].terminal.source = '../../elsewhere/session.cast';
  const {websiteDir, source} = scratch(manifest);

  assert.throws(
    () => run(websiteDir, {IDB_DEMOS_DIR: source}),
    /has a terminal session at \.\.\/\.\.\/elsewhere\/session\.cast, outside the run/
  );
});

test('links the test that performed each demo', () => {
  const {websiteDir, source} = scratch(manifestFixture());

  const published = run(websiteDir, {IDB_DEMOS_DIR: source});

  assert.strictEqual(
    published.demos[0].source.url,
    'https://github.com/facebook/idb/blob/' +
      '0123456789abcdef0123456789abcdef01234567/EndToEndTests/test_system.py#L31'
  );
  assert.strictEqual(published.demos[0].source.line, 31);
});

test('publishes a demo whose run recorded no declaration', () => {
  const manifest = manifestFixture();
  manifest.demos[0].source = null;
  const {websiteDir, source} = scratch(manifest);

  const published = run(websiteDir, {IDB_DEMOS_DIR: source});

  assert.strictEqual(published.demos[0].source, null);
});

test('publishes a declaration the run could not pin to a commit', () => {
  const manifest = manifestFixture();
  manifest.demos[0].source = {
    path: 'EndToEndTests/test_system.py',
    line: 31,
    sha: null,
    url: null,
  };
  const {websiteDir, source} = scratch(manifest);

  const published = run(websiteDir, {IDB_DEMOS_DIR: source});

  assert.strictEqual(published.demos[0].source.url, null);
  assert.strictEqual(published.demos[0].source.path, 'EndToEndTests/test_system.py');
});

test('refuses a source link that points anywhere else', () => {
  for (const url of ['javascript:alert(1)', 'https://example.com/idb.py#L1']) {
    const manifest = manifestFixture();
    manifest.demos[0].source.url = url;
    const {websiteDir, source} = scratch(manifest);

    assert.throws(
      () => run(websiteDir, {IDB_DEMOS_DIR: source}),
      /links its source somewhere other than/,
      url
    );
  }
});

test('fails when a demo names a source it cannot link', () => {
  const manifest = manifestFixture();
  delete manifest.demos[0].source.path;
  const {websiteDir, source} = scratch(manifest);

  assert.throws(
    () => run(websiteDir, {IDB_DEMOS_DIR: source}),
    /names a source file it cannot link/
  );
});

test('fails when a command lost a number the page prints', () => {
  for (const key of ['returncode', 'start', 'finished', 'seconds']) {
    const manifest = manifestFixture();
    manifest.demos[0].commands[0][key] = 'not a number';
    const {websiteDir, source} = scratch(manifest);

    assert.throws(
      () => run(websiteDir, {IDB_DEMOS_DIR: source}),
      new RegExp(`has a command with no ${key}`),
      key
    );
  }
});

test('fails when a command has an argument that is not text', () => {
  const manifest = manifestFixture();
  manifest.demos[0].commands[0].argv = ['idb', 'open', 7];
  const {websiteDir, source} = scratch(manifest);

  assert.throws(
    () => run(websiteDir, {IDB_DEMOS_DIR: source}),
    /has a command with no step or argv/
  );
});

test('fails when a command has no argv to show', () => {
  const manifest = manifestFixture();
  manifest.demos[0].commands[0].argv = [];
  const {websiteDir, source} = scratch(manifest);

  assert.throws(
    () => run(websiteDir, {IDB_DEMOS_DIR: source}),
    /has a command with no step or argv/
  );
});

test('fails when output is neither text nor a digest', () => {
  for (const stream of [{}, {bytes: 12}, {bytes: 12, binary: true}]) {
    const manifest = manifestFixture();
    manifest.demos[0].commands[0].stdout = stream;
    const {websiteDir, source} = scratch(manifest);

    assert.throws(
      () => run(websiteDir, {IDB_DEMOS_DIR: source}),
      /has a command with no stdout/,
      JSON.stringify(stream)
    );
  }
});

test('fails when two files of the run would be served as one', () => {
  const manifest = manifestFixture();
  manifest.demos[1].video.source = 'clips/open-a-url.mp4';
  const {websiteDir, source} = scratch(manifest);

  assert.throws(
    () => run(websiteDir, {IDB_DEMOS_DIR: source}),
    /both served as open-a-url\.mp4/
  );
});

test('fails when a clip is missing a dimension the page sets', () => {
  const manifest = manifestFixture();
  delete manifest.demos[0].video.width;
  const {websiteDir, source} = scratch(manifest);

  assert.throws(
    () => run(websiteDir, {IDB_DEMOS_DIR: source}),
    /open-a-url has a clip with no width/
  );
});

test('fails when a clip does not say how long it is', () => {
  const manifest = manifestFixture();
  manifest.demos[0].video.duration = null;
  const {websiteDir, source} = scratch(manifest);

  assert.throws(
    () => run(websiteDir, {IDB_DEMOS_DIR: source}),
    /open-a-url has a clip with no duration/
  );
});

test('fails when a clip is not served as any type', () => {
  const manifest = manifestFixture();
  delete manifest.demos[0].video.type;
  const {websiteDir, source} = scratch(manifest);

  assert.throws(
    () => run(websiteDir, {IDB_DEMOS_DIR: source}),
    /open-a-url has a clip with no type/
  );
});

test('refuses media from outside the run', () => {
  const manifest = manifestFixture();
  manifest.demos[0].video.source = '/etc/passwd';
  manifest.demos[0].poster = '../../elsewhere/poster.png';
  const {websiteDir, source} = scratch(manifest);

  assert.throws(
    () => run(websiteDir, {IDB_DEMOS_DIR: source}),
    /outside the run[\s\S]*outside the run/
  );
});

test('reads a run from nowhere but the directory it is pointed at', () => {
  const {websiteDir, source} = scratch(manifestFixture());
  fs.renameSync(source, path.join(websiteDir, 'demos'));

  const published = run(websiteDir, {});

  assert.deepStrictEqual(published, {demos: []});
});

let failed = 0;
for (const {name, body} of tests) {
  try {
    body();
    console.log(`ok ${name}`);
  } catch (error) {
    failed += 1;
    console.log(`not ok ${name}\n  ${error.message}`);
  }
}
console.log(`${tests.length - failed} passed, ${failed} failed`);
process.exitCode = failed === 0 ? 0 : 1;
