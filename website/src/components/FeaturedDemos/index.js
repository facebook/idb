/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import React from 'react';
import Link from '@docusaurus/Link';
import DemoTranscript from '@site/src/components/DemoTranscript';

// A run publishes all of its demos or none, so a build with demos that lacks
// one named here has lost it to a rename, and fails rather than quietly
// featuring fewer. A build with no demos features none.
export default function FeaturedDemos({demos, slugs}) {
  if (!demos || demos.length === 0) {
    return null;
  }
  const featured = slugs.map((slug) => {
    const demo = demos.find((candidate) => candidate.slug === slug);
    if (demo === undefined) {
      throw new Error(`The home page features ${slug}, which this build did not publish`);
    }
    return demo;
  });
  return (
    <>
      <h2 id="demos">See it drive a simulator</h2>
      <p>
        Each of these is an end-to-end test, published from a run against a
        real simulator. <Link to="/idb/demos">The demos page</Link> has every
        one.
      </p>
      <DemoTranscript demos={featured} />
    </>
  );
}
