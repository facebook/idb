/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import React from 'react';
import classnames from 'classnames';
import Layout from '@theme/Layout';
import Link from '@docusaurus/Link';
import useDocusaurusContext from '@docusaurus/useDocusaurusContext';
import useBaseUrl from '@docusaurus/useBaseUrl';
import styles from './styles.module.css';

function HomeSplash(props) {
  return (
    <header className={classnames('hero', styles.heroBanner)}>
      <div className="container">
        <div className="row">
          <div className="col col--4"></div>
          <div className="col col--4">
            <h1 className="hero__title">idb</h1>
            <p className="hero__subtitle">{props.tagline}</p>
            <Link
              className="button button--lg button--outline button--primary"
              to={useBaseUrl('docs/overview')}
            >
              GETTING STARTED
            </Link>
          </div>
          <div className="col col--4"><img className={styles.itemImage} src="img/idb_icon.svg" alt="API" /></div>
        </div>
      </div>
    </header>
  );
}

const DemoVideo = props => (
  <main>
    <section className={classnames('hero', styles.items)}>
      <div className="container">
        <video playsInline loop muted controls>
          <source src="idb_demo.mov" type="video/mp4" />
        </video>
      </div>
    </section>
  </main>

);

function Index() {
  const context = useDocusaurusContext();
  const { siteConfig = {} } = context;

  return (
    <Layout
      title={siteConfig.title}
      description={siteConfig.tagline}
    >
      <HomeSplash tagline={siteConfig.tagline} />
      <DemoVideo />
    </Layout>
  );
}

export default Index;
