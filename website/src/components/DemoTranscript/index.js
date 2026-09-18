/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import React, {useCallback, useEffect, useRef, useState} from 'react';
import useBaseUrl from '@docusaurus/useBaseUrl';
import 'asciinema-player/dist/bundle/asciinema-player.css';
import styles from './styles.module.css';

const SAFE_ARGUMENT = /^[A-Za-z0-9_@%+=:,./-]+$/;

// At most this many of the lines a note points at are shown beside the note.
// The rest of the output is a disclosure away.
const EXCERPT_LINES = 8;

// How far the terminal and the clip may drift apart before the terminal is
// pulled back to the clip. Small enough that a command still appears while
// the screen is doing it, wide enough that a playing terminal is not seeked
// on every reading.
const DRIFT_SECONDS = 0.5;

// The terminal reports no event for being scrubbed, so its clock is read
// instead. A jump larger than this between two readings is someone dragging
// its scrubber rather than it playing.
const GESTURE_SECONDS = 0.4;

// How often that clock is read.
const POLL_MILLISECONDS = 100;

function quote(argument) {
  return SAFE_ARGUMENT.test(argument)
    ? argument
    : `'${argument.replace(/'/g, `'\\''`)}'`;
}

function commandLine(argv) {
  return argv.map(quote).join(' ');
}

// Both players return a promise from play() that rejects when the browser
// declines to start, which is not a failure worth reporting anywhere.
function started(what) {
  const playing = what.play();
  if (playing && typeof playing.catch === 'function') {
    playing.catch(() => {});
  }
}

function clamp(seconds, duration) {
  if (!Number.isFinite(seconds) || seconds < 0) {
    return 0;
  }
  return seconds > duration ? duration : seconds;
}

// The step the demo is in at a moment of its timeline: the last one that had
// begun by then. Before the first command there is none, which is what the
// page renders on the server and without JavaScript.
function stepAt(commands, seconds) {
  let found = -1;
  for (let index = 0; index < commands.length; index += 1) {
    if (commands[index].start <= seconds) {
      found = index;
    }
  }
  return found;
}

// Output that is JSON reads better laid out than on the one line a command
// prints it on. Anything else, and anything cut off before it closed, is shown
// as it was printed.
function laidOut(text) {
  const trimmed = text.trim();
  if (!trimmed.startsWith('{') && !trimmed.startsWith('[')) {
    return text;
  }
  try {
    return `${JSON.stringify(JSON.parse(trimmed), null, 2)}\n`;
  } catch (error) {
    return text;
  }
}

function escaped(mark) {
  return mark.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

// One line of output, with the pieces a note named wrapped so a reader can
// find them.
function Marked({line, marks}) {
  if (marks.length === 0 || !marks.some((mark) => line.includes(mark))) {
    return line;
  }
  const pattern = new RegExp(`(${marks.map(escaped).join('|')})`, 'g');
  return line
    .split(pattern)
    .map((part, index) =>
      marks.includes(part) ? (
        <mark key={index} className={styles.highlight}>
          {part}
        </mark>
      ) : (
        part
      )
    );
}

function Lines({lines, marks}) {
  return (
    <pre className={styles.output}>
      <code>
        {lines.map((line, index) => (
          <React.Fragment key={index}>
            <Marked line={line} marks={marks} />
            {'\n'}
          </React.Fragment>
        ))}
      </code>
    </pre>
  );
}

// A stream as lines, or nothing when there is nothing to show. Output that is
// JSON is laid out; a stream that is not text has no lines to give.
function textOf(stream) {
  if (!stream || stream.bytes === 0 || stream.binary) {
    return null;
  }
  return laidOut(stream.text).replace(/\n$/, '').split('\n');
}

// What a step ran and what came back.
//
// The terminal beside this has already played all of it — the command line
// included — so showing it again in full would say everything twice. What
// stays on the page is the handful of lines a note is pointing at, which is
// the evidence for what the note claims. The command and the rest of the
// output sit behind one disclosure, so they are still in the document for a
// reader without JavaScript and for a search, and the summary carries how the
// command ended rather than spending a row on it.
function Printed({command, marks}) {
  const exit = `Exited ${command.returncode} after ${command.seconds.toFixed(2)}s`;
  const line = (
    <pre className={styles.command}>
      <code>
        <span className={styles.prompt}>$ </span>
        {commandLine(command.argv)}
      </code>
    </pre>
  );

  const binary = [command.stdout, command.stderr].find(
    (stream) => stream && stream.binary
  );
  if (binary) {
    return (
      <details className={styles.more}>
        <summary>
          {exit}, printing {binary.bytes} bytes that are not text, sha256{' '}
          <code>{binary.sha256}</code>; show the command
        </summary>
        {line}
      </details>
    );
  }

  const printed = textOf(command.stdout) || [];
  const errors = textOf(command.stderr) || [];
  const pointedAt = printed.filter((one) =>
    marks.some((mark) => one.includes(mark))
  );
  const excerpt = pointedAt.slice(0, EXCERPT_LINES);
  // A short output can be entirely the lines a note points at, and then the
  // disclosure has only the command left to show.
  const whole = excerpt.length === printed.length && errors.length === 0;
  const nothing = printed.length === 0 && errors.length === 0;

  return (
    <>
      {excerpt.length > 0 ? <Lines lines={excerpt} marks={marks} /> : null}
      <details className={styles.more}>
        <summary>
          {exit}
          {nothing ? ', printing nothing' : ''}; show the command
          {whole
            ? ''
            : ` and all ${printed.length + errors.length} lines it printed`}
        </summary>
        {line}
        {whole ? null : (
          <>
            {printed.length > 0 ? <Lines lines={printed} marks={marks} /> : null}
            {errors.length > 0 ? (
              <>
                <p className={styles.label}>Errors</p>
                <Lines lines={errors} marks={marks} />
              </>
            ) : null}
          </>
        )}
        {command.stdout && command.stdout.truncated ? (
          <p className={styles.exit}>
            Output continues past what is shown; {command.stdout.bytes} bytes in
            all.
          </p>
        ) : null}
      </details>
    </>
  );
}

// What the test made of a step's output. This is the one thing on the page
// that the terminal beside it cannot show, so it is the step's body rather
// than an annotation on it.
function Notes({notes}) {
  if (!notes || notes.length === 0) {
    return null;
  }
  return (
    <div className={styles.notes}>
      {notes.map((note, index) => (
        <p key={index} className={styles.note}>
          {note.text}
        </p>
      ))}
    </div>
  );
}

// Every step is in the document, always: the page is a transcript first, and
// a reader on the server or without JavaScript gets all of them as a list.
// Once there is a clock, the steps are stacked one on top of another and the
// one the demo is in is the one shown, so the narration changes with the clip
// rather than running on past it.
//
// There is no button to play a step from here. The terminal's scrubber carries
// a marker per step, which is the same affordance in the place a reader is
// already looking for it.
function Step({command, index, total, showing, printed}) {
  const marks = (command.notes || []).flatMap((note) => note.marks);
  return (
    <li
      className={styles.step}
      data-showing={showing ? 'true' : 'false'}
      aria-current={showing ? 'step' : undefined}>
      <div className={styles.stepHeader}>
        <span className={styles.count}>
          {index + 1} of {total}
        </span>
        <h3 className={styles.stepName}>{command.step}</h3>
      </div>
      <Notes notes={command.notes} />
      <div className={printed ? undefined : styles.pending}>
        <Printed command={command} marks={marks} />
      </div>
    </li>
  );
}

// What the demo looked like: its clip when there is one, and otherwise the
// screenshot the test ended on, so a demo the recorder produced nothing for
// still shows the simulator rather than only the commands.
function Screen({demo, video, source, poster, player, onTime}) {
  if (video) {
    return (
      <figure className={styles.figure}>
        <video
          ref={player}
          className={styles.video}
          controls
          playsInline
          preload="metadata"
          poster={demo.poster ? poster : undefined}
          width={video.width}
          height={video.height}
          onTimeUpdate={onTime}
          onSeeked={onTime}
          onPlay={onTime}
          onPause={onTime}
          onEnded={onTime}>
          <source src={source} type={video.type} />
        </video>
      </figure>
    );
  }
  if (!demo.poster) {
    return null;
  }
  return (
    <figure className={styles.figure}>
      <img
        className={styles.still}
        src={poster}
        alt={`${demo.title}, as the test left the screen`}
      />
      <figcaption>
        {demo.title}, as the test left the screen. This demo has no recording.
      </figcaption>
    </figure>
  );
}

// The demo's name, linked to the test that performed it. The link is pinned to
// the commit the run tested rather than to a branch, which would be whatever
// that file becomes later. A run that recorded no declaration, or one with no
// link for it, is named without one.
function Name({demo}) {
  const source = demo.source;
  if (!source || !source.url) {
    return demo.title;
  }
  return (
    <a href={source.url} title={`Performed by ${source.path}:${source.line}`}>
      {demo.title}
    </a>
  );
}

// The terminal, the clip, and the step the two of them are in.
//
// The clip is the timeline of record when there is one. The terminal follows
// it, and a gesture made on the terminal — dragging its scrubber, clicking a
// step's marker, pressing its play button — is turned into the same gesture on
// the clip, which then propagates back. Only one of them is ever written to as
// a consequence of the other having moved, so neither can drive the other in a
// loop. A demo whose clip could not be cut has no clip to defer to, and the
// terminal is the timeline itself.
function useSynchronised(clip, terminal, duration) {
  const [seconds, setSeconds] = useState(0);
  const playing = useRef(false);
  // What the terminal's clock read when it was last looked at, and when. The
  // next reading is measured against where playing alone would have carried
  // it from here.
  const read = useRef({at: 0, seconds: 0});

  const track = useCallback((at) => {
    read.current = {at: Date.now(), seconds: at};
  }, []);

  useEffect(() => {
    const tick = setInterval(() => {
      const player = terminal.current;
      if (!player) {
        return;
      }
      const at = player.getCurrentTime();
      const screen = clip.current;
      if (!screen) {
        setSeconds(clamp(at, duration));
        track(at);
        return;
      }
      const elapsed = playing.current ? (Date.now() - read.current.at) / 1000 : 0;
      if (Math.abs(at - (read.current.seconds + elapsed)) > GESTURE_SECONDS) {
        screen.currentTime = clamp(at, duration);
        track(at);
        return;
      }
      if (Math.abs(at - screen.currentTime) > DRIFT_SECONDS) {
        player.seek(screen.currentTime);
        track(screen.currentTime);
        return;
      }
      track(at);
    }, POLL_MILLISECONDS);
    return () => clearInterval(tick);
  }, [clip, terminal, duration, track]);

  // The terminal's transport, mirrored onto the clip. Asking a player to do
  // what it is already doing is not an event, so these settle rather than
  // bouncing between the two.
  const transport = useCallback(
    (isPlaying) => {
      playing.current = isPlaying;
      const screen = clip.current;
      if (!screen || screen.paused !== isPlaying) {
        return;
      }
      if (isPlaying) {
        started(screen);
      } else {
        screen.pause();
      }
    },
    [clip]
  );

  // And the clip's transport, mirrored onto the terminal. Its time is only
  // read here; the interval above is what carries it to the terminal.
  const watch = useCallback(
    (event) => {
      const screen = event.currentTarget;
      setSeconds(clamp(screen.currentTime, duration));
      const player = terminal.current;
      if (!player || screen.paused === !playing.current) {
        return;
      }
      if (screen.paused) {
        player.pause();
      } else {
        started(player);
      }
    },
    [duration, terminal]
  );

  return {seconds, transport, watch};
}

// The recorded terminal, played in the page rather than downloaded to be
// played elsewhere. Its scrubber carries a marker per step, so the steps are
// on the timeline and can be jumped between from it.
//
// It is built in an effect and so never on the server: the transcript below
// is what a reader without JavaScript gets, and it is the whole of the demo
// in text. Nothing readable depends on this loading.
function Terminal({source, onReady, onTransport}) {
  const box = useRef(null);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    let player = null;
    let gone = false;
    import('asciinema-player')
      .then((asciinema) => {
        if (gone || !box.current) {
          return;
        }
        player = asciinema.create(source, box.current, {
          fit: 'width',
          terminalFontSize: 'small',
          // A marker is where a step begins, not somewhere to stop: the clip
          // beside it keeps running either way.
          pauseOnMarkers: false,
          controls: true,
          preload: true,
          poster: 'npt:0:0',
        });
        player.addEventListener('play', () => onTransport(true));
        player.addEventListener('playing', () => onTransport(true));
        player.addEventListener('pause', () => onTransport(false));
        player.addEventListener('ended', () => onTransport(false));
        onReady(player);
      })
      .catch(() => setFailed(true));
    return () => {
      gone = true;
      onReady(null);
      if (player) {
        player.dispose();
      }
    };
  }, [source, onReady, onTransport]);

  return (
    <div className={styles.terminal}>
      <div ref={box} />
      {failed ? (
        <p className={styles.empty}>
          The terminal could not be played here.{' '}
          <a href={source} download>
            Download it as an asciicast
          </a>{' '}
          to play it locally.
        </p>
      ) : null}
    </div>
  );
}

function Demo({demo}) {
  const clip = useRef(null);
  const terminal = useRef(null);
  const [ready, setReady] = useState(false);
  const video = demo.video;
  const duration = video ? video.duration : demo.terminal.duration;
  const source = useBaseUrl(video ? video.source : '/');
  const poster = useBaseUrl(demo.poster || '/');
  const session = useBaseUrl(demo.terminal.source);
  const {seconds, transport, watch} = useSynchronised(
    clip,
    terminal,
    duration
  );

  const onReady = useCallback((player) => {
    terminal.current = player;
    setReady(Boolean(player));
  }, []);

  // Nothing is a clock until the page is live in a browser. Rendered on the
  // server the demo is its full list of steps, which is what a reader without
  // JavaScript keeps.
  const [live, setLive] = useState(false);
  useEffect(() => setLive(true), []);

  // Without a clip and without the terminal there is no clock, and no step
  // the demo can be said to be in. Every step then reads as finished, which
  // is what it is: this is a transcript of a run that already happened.
  const clocked = live && (Boolean(video) || ready);
  const reached = stepAt(demo.commands, seconds);
  // Before the first command there is no step to be in, so the first one
  // stands in for it rather than leaving the narration blank.
  const current = reached < 0 ? 0 : reached;

  return (
    <section className={styles.demo} aria-labelledby={`${demo.slug}-title`}>
      <h2 id={`${demo.slug}-title`}>
        <Name demo={demo} />
      </h2>
      <p>{demo.summary}</p>
      <div className={styles.stage}>
        <div className={styles.screen}>
          <Screen
            demo={demo}
            video={video}
            source={source}
            poster={poster}
            player={clip}
            onTime={watch}
          />
        </div>
        <div className={styles.session}>
          <Terminal
            source={session}
            onReady={onReady}
            onTransport={transport}
          />
          <div className={styles.narration}>
            <ol className={clocked ? styles.phases : styles.steps}>
              {demo.commands.map((command, index) => (
                <Step
                  key={`${demo.slug}-${index}`}
                  command={command}
                  index={index}
                  total={demo.commands.length}
                  showing={!clocked || current === index}
                  printed={!clocked || command.finished <= seconds}
                />
              ))}
            </ol>
          </div>
        </div>
      </div>
    </section>
  );
}

export default function DemoTranscript({demos}) {
  if (!demos || demos.length === 0) {
    return (
      <p className={styles.empty}>
        This build has no demos. They are published from an end-to-end run in
        which every documented test passed.
      </p>
    );
  }
  return (
    <>
      {demos.map((demo) => (
        <Demo key={demo.slug} demo={demo} />
      ))}
    </>
  );
}
