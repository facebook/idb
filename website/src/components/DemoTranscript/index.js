/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import React, {useCallback, useEffect, useRef, useState} from 'react';
import useBaseUrl from '@docusaurus/useBaseUrl';
import styles from './styles.module.css';

const SAFE_ARGUMENT = /^[A-Za-z0-9_@%+=:,./-]+$/;

// How often the terminal's own clock advances when there is no clip to take
// the time from. Close enough that a command appears when it ran, and slow
// enough that a page of demos is not re-rendering constantly.
const TICK_MILLISECONDS = 100;

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

// One timeline for the demo, whatever is driving it.
//
// A demo with a clip is driven by the clip: the element is the clock and its
// own controls are the transport, and this only reads it. Nothing here writes
// `currentTime` except an explicit seek, so a time update cannot feed back
// into a seek that produces another time update.
//
// A demo whose clip could not be cut has no element to take the time from, so
// the terminal runs its own clock over the session's duration and carries its
// own transport.
function useTimeline(player, duration, driven) {
  const [seconds, setSeconds] = useState(0);
  const [playing, setPlaying] = useState(false);

  // The clock advances the timeline by however long each tick took, rather
  // than from an origin taken when it started: a seek while playing — which
  // is what restarting is — moves the timeline under a clock that is already
  // running, and an origin would drag it back to where the seek began.
  useEffect(() => {
    if (driven || !playing) {
      return undefined;
    }
    let previous = Date.now();
    const tick = setInterval(() => {
      const now = Date.now();
      const elapsed = (now - previous) / 1000;
      previous = now;
      setSeconds((was) => clamp(was + elapsed, duration));
    }, TICK_MILLISECONDS);
    return () => clearInterval(tick);
  }, [driven, playing, duration]);

  // Reaching the end stops the clock rather than leaving it running against a
  // timeline that cannot advance.
  useEffect(() => {
    if (!driven && playing && seconds >= duration) {
      setPlaying(false);
    }
  }, [driven, playing, seconds, duration]);

  const seek = useCallback(
    (to, andPlay) => {
      const at = clamp(to, duration);
      const element = player.current;
      if (element) {
        element.currentTime = at;
        if (andPlay) {
          const started = element.play();
          if (started && typeof started.catch === 'function') {
            started.catch(() => {});
          }
        }
        return;
      }
      setSeconds(at);
      if (andPlay) {
        setPlaying(true);
      }
    },
    [duration, player]
  );

  const toggle = useCallback(() => {
    const element = player.current;
    if (element) {
      if (element.paused) {
        const started = element.play();
        if (started && typeof started.catch === 'function') {
          started.catch(() => {});
        }
      } else {
        element.pause();
      }
      return;
    }
    setPlaying((was) => !was);
  }, [player]);

  const restart = useCallback(() => seek(0, true), [seek]);

  return {seconds, setSeconds, playing, setPlaying, seek, toggle, restart};
}

function Output({label, stream}) {
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
  return (
    <>
      <p className={styles.label}>{label}</p>
      <pre className={styles.output}>
        <code>{stream.text}</code>
      </pre>
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
        <Output label="Output" stream={command.stdout} />
        <Output label="Errors" stream={command.stderr} />
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

function Demo({demo}) {
  const player = useRef(null);
  const video = demo.video;
  const terminal = demo.terminal;
  const duration = video ? video.duration : terminal.duration;
  const source = useBaseUrl(video ? video.source : '/');
  const poster = useBaseUrl(demo.poster || '/');
  const session = useBaseUrl(terminal.source);
  const {seconds, setSeconds, playing, setPlaying, seek, toggle, restart} =
    useTimeline(player, duration, Boolean(video));

  // The clip is the clock when there is one: this reads the element's time
  // and never writes it, so the two cannot drive each other in a loop.
  const onTime = useCallback(
    (event) => {
      const element = event.currentTarget;
      setSeconds(clamp(element.currentTime, duration));
      setPlaying(!element.paused);
    },
    [duration, setPlaying, setSeconds]
  );

  const select = useCallback((start) => seek(start, true), [seek]);
  const current = stepAt(demo.commands, seconds);

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
            player={player}
            onTime={onTime}
          />
        </div>
        <div className={styles.session}>
          {video ? null : (
            <div className={styles.transport}>
              <button type="button" className={styles.play} onClick={toggle}>
                {playing ? 'Pause' : 'Play'}
              </button>
              <button type="button" className={styles.play} onClick={restart}>
                Restart
              </button>
              <span className={styles.clock}>
                {seconds.toFixed(1)}s of {duration.toFixed(1)}s
              </span>
            </div>
          )}
          <ol className={styles.steps}>
            {demo.commands.map((command, index) => (
              <Step
                key={`${demo.slug}-${index}`}
                command={command}
                index={index}
                current={current === index}
                printed={command.finished <= seconds}
                seekable={Boolean(video)}
                onSelect={select}
              />
            ))}
          </ol>
          <p className={styles.empty}>
            <a href={session} download>
              Download this terminal session
            </a>{' '}
            as an asciicast.
          </p>
          <Declaration source={demo.source} />
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
