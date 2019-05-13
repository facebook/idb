/**
 * Copyright (c) 2017-present, Facebook, Inc.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

// See https://docusaurus.io/docs/site-config for all the possible
// site configuration options.

const siteConfig = {
  title: 'idb', // Title for your website.
  tagline: 'iOS Development Bridge',
  url: 'https://fbidb.io',
  baseUrl: '/',
  projectName: 'idb',
  organizationName: 'facebook',
  headerLinks: [
    { doc: 'overview', label: 'Getting Started' },
    { doc: 'installation', label: 'Docs' },
    { href: 'https://github.com/facebook/idb', label: 'GitHub' },
  ],

  favicon: 'img/idb_Logo_Color.png',
  colors: {
    primaryColor: '#181452',
    secondaryColor: '#fd1b43',
  },
  copyright: `Copyright © ${new Date().getFullYear()} Facebook, Inc. and its affiliates`,

  highlight: {
    theme: 'default',
  },

  scripts: ['https://buttons.github.io/buttons.js'],

  onPageNav: 'separate',
  cleanUrl: true,

  ogImage: 'img/idb_Logo_Color.png',
  twitterImage: 'img/idb_Logo_Color.png',
};

module.exports = siteConfig;
