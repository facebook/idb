/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
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
        alt: 'Meta Open Source',
        src: 'img/meta_open_source_logo_negative.svg',
        href: 'https://opensource.fb.com/',
        width: 300,
        height: 64,
      },
      copyright: `Copyright © ${new Date().getFullYear()} Meta Platforms, Inc.`,
      links: [
        {
          title: 'Social',
          items: [
            {
              label: 'Threads',
              href: 'https://www.threads.com/@metaopensource'
            },
            {
              label: 'Discord',
              href: 'https://discord.gg/SF26Yqw'
            }
          ]
        },
        {
          title: 'Contribute',
          items: [
            {
              label: 'Github',
              href: 'https://github.com/facebook/idb'
            },
          ]
        },
        {
          title: 'Legal',
          // Please do not remove the privacy and terms, it's a legal requirement.
          items: [
            {
              label: 'Privacy',
              href: 'https://opensource.fb.com/legal/privacy/',
              target: '_blank',
              rel: 'noreferrer noopener',
            },
            {
              label: 'Terms',
              href: 'https://opensource.fb.com/legal/terms/',
              target: '_blank',
              rel: 'noreferrer noopener',
            },
          ],
        },
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
};
