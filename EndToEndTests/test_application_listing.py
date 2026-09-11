# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

"""Read-only inventory of installed applications."""

from __future__ import annotations

from .harness import IdbEndToEndTestCase


class ApplicationListingTests(IdbEndToEndTestCase):
    async def test_list_apps_reports_system_applications(self) -> None:
        apps = await self.installed_apps()

        self.assertIn("com.apple.mobilesafari", apps)
        for row in apps.values():
            self.assertIn("name", row)
            self.assertIn("install_type", row)
            self.assertIn("process_state", row)
