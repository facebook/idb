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

function manifestFixture(overrides) {
  return {
    video: {
      source: 'media/idb-e2e-fixture.mp4',
      type: 'video/mp4',
      width: 590,
      height: 1278,
      duration: 37.5,
    },
    demos: [
      {
        slug: SLUG,
        title: 'Open a URL on a simulator',
        summary: 'Hand a URL to the simulator and let it pick the app.',
        test: TEST,
        start: 6.0,
        end: 13.0,
        poster: 'media/open-a-url.png',
        commands: [
          {
            step: 'Open a URL on the simulator',
            argv: ['idb', 'open', 'https://example.com'],
            returncode: 0,
            start: 10.58,
            seconds: 0.42,
            stdout: {bytes: 0, text: '', truncated: false},
            stderr: {bytes: 0, text: '', truncated: false},
          },
        ],
      },
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
    fs.writeFileSync(path.join(source, 'media', 'idb-e2e-fixture.mp4'), 'a recording');
    fs.writeFileSync(path.join(source, 'media', 'open-a-url.png'), 'a screenshot');
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

  assert.strictEqual(published.demos.length, 1);
  assert.strictEqual(published.demos[0].slug, SLUG);
  assert.deepStrictEqual(
    JSON.parse(read(websiteDir, 'src', 'demos', 'demos.json')),
    published
  );
});

test('rewrites media paths to what the site serves', () => {
  const {websiteDir, source} = scratch(manifestFixture());

  const published = run(websiteDir, {IDB_DEMOS_DIR: source});

  assert.strictEqual(published.video.source, '/demos/media/idb-e2e-fixture.mp4');
  assert.strictEqual(published.demos[0].poster, '/demos/media/open-a-url.png');
});

test('serves the recording and the posters as static files', () => {
  const {websiteDir, source} = scratch(manifestFixture());

  run(websiteDir, {IDB_DEMOS_DIR: source});

  assert.strictEqual(
    read(websiteDir, 'static', 'demos', 'media', 'idb-e2e-fixture.mp4'),
    'a recording'
  );
  assert.strictEqual(
    read(websiteDir, 'static', 'demos', 'media', 'open-a-url.png'),
    'a screenshot'
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

test('publishes the transcript when the run recorded no video', () => {
  const {websiteDir, source} = scratch(manifestFixture({video: null}));

  const published = run(websiteDir, {IDB_DEMOS_DIR: source});

  assert.strictEqual(published.video, null);
  assert.strictEqual(published.demos.length, 1);
});

test('forgets the media an earlier run published', () => {
  const {websiteDir, source} = scratch(manifestFixture());
  run(websiteDir, {IDB_DEMOS_DIR: source});

  const without = manifestFixture({video: null});
  without.demos[0].poster = null;
  fs.writeFileSync(
    path.join(source, 'demos.json'),
    JSON.stringify(without, null, 2)
  );
  run(websiteDir, {IDB_DEMOS_DIR: source});

  assert.ok(!fs.existsSync(path.join(websiteDir, 'static', 'demos', 'media')));
});

test('builds an empty page when no run is beside the site', () => {
  const {websiteDir} = scratch(null);

  const published = run(websiteDir, {});

  assert.deepStrictEqual(published, {video: null, demos: []});
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

test('fails when a demo has no offsets to seek to', () => {
  const manifest = manifestFixture();
  delete manifest.demos[0].start;
  manifest.demos[0].end = null;
  const {websiteDir, source} = scratch(manifest);

  assert.throws(
    () => run(websiteDir, {IDB_DEMOS_DIR: source}),
    /has no start[\s\S]*has no end/
  );
});

test('fails when a command lost a number the page prints', () => {
  for (const key of ['returncode', 'start', 'seconds']) {
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
  manifest.demos[0].poster = 'shots/idb-e2e-fixture.mp4';
  const {websiteDir, source} = scratch(manifest);

  assert.throws(
    () => run(websiteDir, {IDB_DEMOS_DIR: source}),
    /both served as idb-e2e-fixture\.mp4/
  );
});

test('fails when the recording is missing a dimension the page sets', () => {
  const manifest = manifestFixture();
  delete manifest.video.width;
  const {websiteDir, source} = scratch(manifest);

  assert.throws(
    () => run(websiteDir, {IDB_DEMOS_DIR: source}),
    /the recording has no width/
  );
});

test('fails when the recording is not served as any type', () => {
  const manifest = manifestFixture();
  delete manifest.video.type;
  const {websiteDir, source} = scratch(manifest);

  assert.throws(
    () => run(websiteDir, {IDB_DEMOS_DIR: source}),
    /the recording has no type/
  );
});

test('refuses media from outside the run', () => {
  const manifest = manifestFixture();
  manifest.video.source = '/etc/passwd';
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

  assert.deepStrictEqual(published, {video: null, demos: []});
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
