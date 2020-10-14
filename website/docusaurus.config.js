/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

module.exports = {
  title: 'idb',
  tagline: 'iOS Development Bridge',
  favicon: 'img/favicon.png',
  url: 'https://fbidb.io',
  baseUrl: '/',
  organizationName: 'facebook',
  projectName: 'idb',
  themeConfig: {
    navbar: {
      title: 'idb',
      items: [
        { to: 'docs/overview', label: 'Getting Started', position: 'right' },
        { to: 'docs/installation', label: 'Docs', position: 'right' },
        { href: 'https://github.com/facebook/idb', label: 'GitHub', position: 'right' },
      ],
    },
    footer: {
      style: 'dark',
      logo: {
        alt: 'idb',
        src: 'img/oss_logo.png',
        href: 'https://opensource.facebook.com/',
      },
      copyright: `Copyright © ${new Date().getFullYear()} Facebook, Inc.`,
      links: [
        {
          title: 'Social',
          items: [
            {
              label: 'Twitter',
              to: 'https://twitter.com/fbOpenSource'
            },
          ]
        },
        {
          title: 'Contribute',
          items: [
            {
              label: 'Github',
              to: 'https://github.com/facebook/idb'
            },
          ]
        }
      ],
    },
  },
  presets: [
    [
      '@docusaurus/preset-classic',
      {
        docs: {
          path: './docs',
          sidebarPath: require.resolve('./sidebars.js'),
        },
      },
    ],
  ],
  scripts: ['https://buttons.github.io/buttons.js'],
};
