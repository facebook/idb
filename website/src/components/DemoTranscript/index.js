/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import React, {useCallback, useRef, useState} from 'react';
import useBaseUrl from '@docusaurus/useBaseUrl';
import styles from './styles.module.css';

const SAFE_ARGUMENT = /^[A-Za-z0-9_@%+=:,./-]+$/;

function quote(argument) {
  return SAFE_ARGUMENT.test(argument)
    ? argument
    : `'${argument.replace(/'/g, `'\\''`)}'`;
}

function commandLine(argv) {
  return argv.map(quote).join(' ');
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

function Step({command, index, video, selected, onSelect}) {
  return (
    <li className={selected ? styles.stepSelected : styles.step}>
      <div className={styles.stepHeader}>
        <h3 className={styles.stepName}>{command.step}</h3>
        {video ? (
          <button
            type="button"
            className={styles.play}
            // A demo is a list of these buttons, so the visible label alone
            // would name every one of them identically to anyone navigating
            // by control rather than reading the heading beside it.
            aria-label={`Play this step: ${command.step}`}
            aria-current={selected ? 'true' : undefined}
            onClick={() => onSelect(index, command.start)}>
            Play this step
          </button>
        ) : null}
      </div>
      <pre className={styles.command}>
        <code>{commandLine(command.argv)}</code>
      </pre>
      <Output label="Output" stream={command.stdout} />
      <Output label="Errors" stream={command.stderr} />
      <p className={styles.exit}>
        Exited {command.returncode} after {command.seconds.toFixed(2)} seconds.
      </p>
    </li>
  );
}

// What the demo looked like: the recording when there is one, and otherwise
// the screenshot the test ended on, so a run the recorder produced nothing for
// still shows the simulator rather than only the commands.
function Screen({demo, video, source, poster, player}) {
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
          height={video.height}>
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
        {demo.title}, as the test left the screen. This run has no recording.
      </figcaption>
    </figure>
  );
}

function Demo({demo, video}) {
  const player = useRef(null);
  const [selected, setSelected] = useState(null);
  // The whole suite is one recording, so a demo is a fragment of it rather
  // than a file of its own; the fragment is what a reader without JavaScript
  // gets, and seeking is what they get with it.
  const fragment = `#t=${demo.start},${demo.end}`;
  const source = useBaseUrl(video ? `${video.source}${fragment}` : '/');
  const poster = useBaseUrl(demo.poster || '/');

  const select = useCallback((index, start) => {
    setSelected(index);
    const element = player.current;
    if (!element) {
      return;
    }
    element.currentTime = start;
    const started = element.play();
    if (started && typeof started.catch === 'function') {
      started.catch(() => {});
    }
  }, []);

  return (
    <section className={styles.demo} aria-labelledby={`${demo.slug}-title`}>
      <h2 id={`${demo.slug}-title`}>{demo.title}</h2>
      <p>{demo.summary}</p>
      <Screen
        demo={demo}
        video={video}
        source={source}
        poster={poster}
        player={player}
      />
      <ol className={styles.steps}>
        {demo.commands.map((command, index) => (
          <Step
            key={`${demo.slug}-${index}`}
            command={command}
            index={index}
            video={video}
            selected={selected === index}
            onSelect={select}
          />
        ))}
      </ol>
      <p className={styles.provenance}>
        Performed by <code>{demo.test}</code>.
      </p>
    </section>
  );
}

export default function DemoTranscript({video, demos}) {
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
        <Demo key={demo.slug} demo={demo} video={video} />
      ))}
    </>
  );
}
