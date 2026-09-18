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

// Output longer than this is folded behind a disclosure, with an excerpt shown
// in its place: the lines a note pointed at, or failing those the first few.
const FOLD_LINES = 12;
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

// Where the clip and the terminal are side by side, and the terminal scrolls
// within its own column. Matches the stylesheet's breakpoint.
const SIDE_BY_SIDE = '(min-width: 997px)';

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

// A stream as printed, laid out, marked, and folded when it is long: the whole
// of it stays in the document behind a native disclosure, so a reader without
// JavaScript can open it and a search finds it, and what is shown unfolded is
// the part a note pointed at.
function Output({label, stream, marks}) {
  if (!stream || stream.bytes === 0) {
    return (
      <p className={styles.empty}>
        {label}: <em>no output</em>
      </p>
    );
  }
  if (stream.binary) {
    return (
      <p className={styles.empty}>
        {label}: {stream.bytes} bytes that are not text, sha256{' '}
        <code>{stream.sha256}</code>
      </p>
    );
  }
  const lines = laidOut(stream.text).replace(/\n$/, '').split('\n');
  const pointedAt = lines.filter((line) => marks.some((mark) => line.includes(mark)));
  const folded = lines.length > FOLD_LINES;
  const excerpt = (pointedAt.length > 0 ? pointedAt : lines).slice(0, EXCERPT_LINES);
  return (
    <>
      <p className={styles.label}>{label}</p>
      {folded ? (
        <>
          <Lines lines={excerpt} marks={marks} />
          <details className={styles.more}>
            <summary>
              {pointedAt.length > 0
                ? `Show all ${lines.length} lines, not only the ${excerpt.length} a note points at`
                : `Show all ${lines.length} lines`}
            </summary>
            <Lines lines={lines} marks={marks} />
          </details>
        </>
      ) : (
        <Lines lines={lines} marks={marks} />
      )}
      {stream.truncated ? (
        <p className={styles.empty}>
          <em>Output continues past what is shown; {stream.bytes} bytes in all.</em>
        </p>
      ) : null}
    </>
  );
}

// What the test made of a step's output, beside the step: the element it
// found, where, and what that proves. The output below stays what the command
// printed; this is the reading of it that a viewer would otherwise have to do.
function Notes({notes}) {
  if (!notes || notes.length === 0) {
    return null;
  }
  return (
    <aside className={styles.notes} aria-label="What this step showed">
      <p className={styles.notesLabel}>What this showed</p>
      <ul className={styles.noteList}>
        {notes.map((note, index) => (
          <li key={index}>{note.text}</li>
        ))}
      </ul>
    </aside>
  );
}

// Every step is rendered, always: the page is a transcript first, and a
// reader on the server, without JavaScript, or through a screen reader gets
// all of it. What the timeline changes is which step is marked as the one the
// demo is in, and whether the output below it has been printed yet.
function Step({command, index, current, printed, seekable, onSelect}) {
  const reached = useRef(null);
  const marks = (command.notes || []).flatMap((note) => note.marks);
  useEffect(() => {
    if (!current || !reached.current || !reached.current.scrollIntoView) {
      return;
    }
    // Only where the terminal is its own scrolling column. In the one-column
    // layout the nearest scrolling thing is the page, and scrolling that
    // would take the clip the reader is watching off the screen.
    if (!window.matchMedia(SIDE_BY_SIDE).matches) {
      return;
    }
    reached.current.scrollIntoView({block: 'nearest'});
  }, [current]);

  return (
    <li
      ref={reached}
      className={current ? styles.stepCurrent : styles.step}
      aria-current={current ? 'step' : undefined}>
      <div className={styles.stepHeader}>
        <h3 className={styles.stepName}>{command.step}</h3>
        {seekable ? (
          <button
            type="button"
            className={styles.play}
            // A demo is a list of these buttons, so the visible label alone
            // would name every one of them identically to anyone navigating
            // by control rather than reading the heading beside it.
            aria-label={`Play this step: ${command.step}`}
            onClick={() => onSelect(command.start)}>
            Play this step
          </button>
        ) : null}
      </div>
      <pre className={styles.command}>
        <code>
          <span className={styles.prompt}>$ </span>
          {commandLine(command.argv)}
        </code>
      </pre>
      <Notes notes={command.notes} />
      <div className={printed ? undefined : styles.pending}>
        <Output label="Output" stream={command.stdout} marks={marks} />
        <Output label="Errors" stream={command.stderr} marks={marks} />
        <p className={styles.exit}>
          Exited {command.returncode} after {command.seconds.toFixed(2)} seconds.
        </p>
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
        <figcaption>{demo.title}, recorded while the test ran.</figcaption>
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

// Where the test that performed this demo is declared, pinned to the commit
// the run tested rather than to a branch, which would be whatever that file
// becomes later. A run that did not record a declaration shows none.
function Declaration({source}) {
  if (!source) {
    return null;
  }
  const where = `${source.path}:${source.line}`;
  return (
    <p className={styles.empty}>
      Performed by{' '}
      {source.url ? (
        <a href={source.url}>
          <code>{where}</code>
        </a>
      ) : (
        <code>{where}</code>
      )}
    </p>
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

  // A step, from either side at once, so neither has to notice the other.
  const select = useCallback(
    (at) => {
      const player = terminal.current;
      if (player) {
        player.seek(at);
        started(player);
        track(at);
      }
      const screen = clip.current;
      if (screen) {
        screen.currentTime = clamp(at, duration);
        started(screen);
        return;
      }
      setSeconds(clamp(at, duration));
    },
    [clip, terminal, duration, track]
  );

  return {seconds, transport, watch, select};
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
  const {seconds, transport, watch, select} = useSynchronised(
    clip,
    terminal,
    duration
  );

  const onReady = useCallback((player) => {
    terminal.current = player;
    setReady(Boolean(player));
  }, []);

  // Without a clip and without the terminal there is no clock, and no step
  // the demo can be said to be in. Every step then reads as finished, which
  // is what it is: this is a transcript of a run that already happened.
  const clocked = Boolean(video) || ready;
  const current = clocked ? stepAt(demo.commands, seconds) : -1;

  return (
    <section className={styles.demo} aria-labelledby={`${demo.slug}-title`}>
      <h2 id={`${demo.slug}-title`}>{demo.title}</h2>
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
          <div className={styles.scroller}>
            <ol className={styles.steps}>
              {demo.commands.map((command, index) => (
                <Step
                  key={`${demo.slug}-${index}`}
                  command={command}
                  index={index}
                  current={current === index}
                  printed={!clocked || command.finished <= seconds}
                  seekable={clocked}
                  onSelect={select}
                />
              ))}
            </ol>
            <p className={styles.empty}>
              The terminal above is an{' '}
              <a href={session} download>
                asciicast
              </a>
              , recorded as the test ran.
            </p>
            <Declaration source={demo.source} />
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
