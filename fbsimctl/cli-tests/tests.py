#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

from typing import Any, List, Dict, Tuple
from util import (
    FBSimctl,
    Simulator,
    WebServer,
    Defaults,
    Fixtures,
    Metal,
    async_test,
    log,
    make_ipa,
)
import argparse
import base64
import contextlib
import os
import shutil
import tempfile
import unittest


class FBSimctlTestCase(unittest.TestCase):
    def __init__(
        self,
        methodName: str,
        fbsimctl_path: str,
        use_custom_set: bool,
    ) -> None:
        super(FBSimctlTestCase, self).__init__(methodName)
        set_path = tempfile.mkdtemp() if use_custom_set else None
        self.methodName = methodName
        self.use_custom_set = use_custom_set
        self.fbsimctl = FBSimctl(fbsimctl_path, set_path)
        self.metal = Metal()
        self.tmpdir = tempfile.mkdtemp()

    @async_test
    async def tearDown(self) -> None:
        action = 'delete' if self.use_custom_set else 'shutdown'
        await self.fbsimctl(['--simulators', action])
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def __str__(self) ->  str:
        return '{}: {}'.format(
            self.methodName,
            'Custom Set' if self.use_custom_set else 'Default Set',
        )

    async def assertEventSuccesful(
        self,
        arguments: List[str],
        event_name: str,
    ) -> Dict:
        events = await self.assertEventsFromRun(
            arguments=arguments,
            event_name=event_name,
            event_type='ended',
            min_count=1,
            max_count=1,
        )
        return events[0]

    async def assertEventsFromRun(
        self,
        arguments: List[str],
        event_name: str,
        event_type: str,
        min_count: int = 1,
        max_count: int = None,
        timeout: int = Defaults.TIMEOUT,
    ) -> List[Dict]:
        events = await self.fbsimctl.run(arguments, timeout)
        matching_events = events.matching(event_name, event_type)
        match_count = len(matching_events)
        if min_count is not None:
            self.assertGreaterEqual(
                match_count,
                min_count,
                'Expected at least {} {} {} event, but there were {}. Other events: \b {}'.format(
                    str(min_count),
                    event_name,
                    event_type,
                    str(match_count),
                    events
                )
            )
        if max_count is not None:
            self.assertLessEqual(
                match_count,
                max_count,
                'Expected no more than {} {} {} event, but there were {}. Other events: \b {}'.format(
                    str(max_count),
                    event_name,
                    event_type,
                    str(match_count),
                    events
                )
            )
        return matching_events

    async def assertListContainsOnly(
        self, 
        expected_udids: List[str], 
        query: List[str] = [],
    ) -> List[Dict]:
        events = await self.fbsimctl.run(query + ['list'])
        list_events = events.matching('list', 'discrete')
        list_udids = [
            event.get('subject').get('udid') for event in list_events
        ]
        remainder = set(expected_udids) - set(list_udids)
        self.assertEqual(
            len(remainder),
            0,
            'Expected list command to contain {}, but it was missing'.format(
                remainder
            )
        )
        additional = set(list_udids) - set(expected_udids)
        self.assertEqual(
            len(additional),
            0,
            'Expected list command only contain {}, but it had additional {}'.format(
                expected_udids,
                additional,
            )
        )
        return list_events
    
    async def assertCreatesSimulator(
        self,
        args: List[str],
    ) -> Simulator:
        args = ['create'] + args
        event = await self.assertEventSuccesful(args, 'create')
        return self.assertExtractSimulator(event)

    def assertExtractSimulator(
        self, 
        json_event: Dict[str, Any],
    ) -> Simulator:
        sim_json = json_event.get('subject')
        self.assertIsNotNone(
            sim_json,
            'Expected {} to contain a simulator, but it did not'.format(
                json_event,
            )
        )
        return Simulator(sim_json)

    def assertExtractAndKeyDiagnostics(
        self,
        json_events: List[Dict],
    ) -> Dict:
        return {
            event['subject']['short_name']: event['subject']
            for event
            in json_events
        }

    @async_test
    async def testList(self):
        await self.fbsimctl(['list'])

    @async_test
    async def testCommandThatDoesNotExist(self):
        with self.assertRaises(Exception):
            await self.fbsimctl(['foo'])


class MultipleSimulatorTestCase(FBSimctlTestCase):
    def __init__(
        self,
        methodName: str,
        fbsimctl_path: str,
    ) -> None:
        super(MultipleSimulatorTestCase, self).__init__(
            methodName=methodName,
            fbsimctl_path=fbsimctl_path,
            use_custom_set=True,
        )

    @async_test
    async def testConstructsMissingDefaults(self):
        await self.assertEventsFromRun(
            arguments=['create', '--all-missing-defaults'],
            event_name='create',
            event_type='ended',
            timeout=Defaults.LONG_TIMEOUT,
        )


class WebserverSimulatorTestCase(FBSimctlTestCase):
    def __init__(
        self,
        methodName: str,
        fbsimctl_path: str,
        port: int,
    ) -> None:
        super(WebserverSimulatorTestCase, self).__init__(
            methodName=methodName,
            fbsimctl_path=fbsimctl_path,
            use_custom_set=True,
        )
        self.port = port

    def extractSimulatorSubjects(
        self, 
        response,
    ) -> List[Simulator]:
        self.assertEqual(response['status'], 'success')
        return [
            Simulator(event['subject']).udid
            for event
            in response['subject']
        ]

    def launchWebserver(self):
        return WebServer(self.port, self.fbsimctl)

    @async_test
    async def testInstallsUserApplication(self):
        simulator = await self.assertCreatesSimulator(['iPhone 6'])
        await self.assertEventSuccesful([simulator.udid, 'boot'], 'boot')
        ipafile = make_ipa(self.tmpdir, Fixtures.APP_PATH)
        async with self.launchWebserver() as webserver:
            with open(ipafile, 'rb') as ipa:
                response = webserver.post_binary(
                    '{}/install'.format(simulator.udid),
                    ipa,
                    os.path.getsize(ipafile),
                )
                self.assertEqual(response.get('status'), 'success')
        events = await self.fbsimctl.run([simulator.udid, 'list_apps'])
        event = events.matching('list_apps', 'discrete')[0]
        bundle_ids = [
            entry.get('bundle').get('bundle_id')
            for entry
            in event.get('subject')
        ]
        return self.assertIn(Fixtures.APP_BUNDLE_ID, bundle_ids)

    @async_test
    async def testDiagnosticSearch(self):
        async with self.launchWebserver() as webserver:
            response = webserver.post('diagnose', {'type': 'all'})
            self.assertEqual(response['status'], 'success')

    @async_test
    async def testGetCoreSimulatorLog(self):
        iphone6 = await self.assertCreatesSimulator(['iPhone 6'])
        async with self.launchWebserver() as webserver:
            response = webserver.get(
                iphone6.udid + '/diagnose/coresimulator',
            )
            self.assertEqual(response['status'], 'success')
            event = response['subject'][0]
            self.assertEqual(event['event_name'], 'diagnostic')
            self.assertEqual(event['event_type'], 'discrete')
            diagnostic = event['subject']
            self.assertEqual(diagnostic['short_name'], 'coresimulator')
            self.assertIsNotNone(diagnostic.get('contents'))

    @async_test
    async def testListSimulators(self):
        iphone6 = await self.assertCreatesSimulator(['iPhone 6'])
        iphone6s = await self.assertCreatesSimulator(['iPhone 6s'])
        async with self.launchWebserver() as webserver:
            actual = self.extractSimulatorSubjects(
                webserver.get('list'),
            )
            expected = [
                iphone6.udid,
                iphone6s.udid,
            ]
            self.assertEqual(expected.sort(), actual.sort())
            actual = self.extractSimulatorSubjects(
                webserver.get(iphone6.udid + '/list'),
            )
            expected = [iphone6.udid]

    @async_test
    async def testUploadsVideo(self):
        simulator = await self.assertCreatesSimulator(['iPhone 6'])
        await self.assertEventSuccesful([simulator.udid, 'boot'], 'boot')
        async with self.launchWebserver() as webserver:
            with open(Fixtures.VIDEO, 'rb') as f:
                data = base64.b64encode(f.read()).decode()
                webserver.post(simulator.udid + '/upload', {
                    'short_name': 'video',
                    'file_type': 'mp4',
                    'data': data,
                })
        await self.assertEventSuccesful([simulator.udid, 'shutdown'], 'shutdown')

    @async_test
    async def testScreenshot(self):
        if self.metal.is_supported() is False:
            log.info('Metal not supported, skipping testScreenshot')
            return
        simulator = await self.assertCreatesSimulator(['iPhone 6'])
        await self.assertEventSuccesful([simulator.udid, 'boot'], 'boot')
        async with self.launchWebserver() as webserver:
            webserver.get_binary(simulator.udid + '/screenshot.png')
            webserver.get_binary(simulator.udid + '/screenshot.jpeg')


class SingleSimulatorTestCase(FBSimctlTestCase):
    def __init__(
        self,
        methodName: str,
        fbsimctl_path: str,
        device_type: str,
    ) -> None:
        super(SingleSimulatorTestCase, self).__init__(
            methodName=methodName,
            fbsimctl_path=fbsimctl_path,
            use_custom_set=True,
        )
        self.device_type = device_type

    def __str__(self):
        return '{}: {}'.format(
            self.device_type,
            super().__str__()
        )

    async def assertLaunchesSystemApplication(self) -> Tuple[Simulator, str]:
        simulator = await self.assertCreatesSimulator([self.device_type])
        await self.assertEventSuccesful([simulator.udid, 'boot'], 'boot')
        await self.assertEventSuccesful([simulator.udid, 'launch', 'com.apple.Preferences'], 'launch')
        await self.assertEventsFromRun([simulator.udid, 'service_info', 'com.apple.Preferences'], 'service_info', 'discrete')
        return (simulator, 'com.apple.Preferences')

    async def assertInstallsUserApplication(self, udid, path, bundle_id):
        await self.assertEventSuccesful([udid, 'boot'], 'boot')
        await self.assertEventSuccesful([udid, 'install', path], 'install')
        events = await self.fbsimctl.run([udid, 'list_apps'])
        event = events.matching('list_apps', 'discrete')[0]
        bundle_ids = [
            entry.get('bundle').get('bundle_id')
            for entry
            in event.get('subject')
        ]
        return self.assertIn(bundle_id, bundle_ids)

    @async_test
    async def testCreateThenDelete(self):
        await self.assertListContainsOnly([])
        simulator = await self.assertCreatesSimulator([self.device_type])
        await self.assertListContainsOnly([simulator.udid])
        await self.assertEventSuccesful([simulator.udid, 'delete'], 'delete')
        await self.assertListContainsOnly([])

    @async_test
    async def testBootsViaSimulatorApp(self):
        simulator = await self.assertCreatesSimulator([self.device_type])
        await self.assertEventSuccesful([simulator.udid, 'boot'], 'boot')
        await self.assertEventSuccesful([simulator.udid, 'shutdown'], 'shutdown')

    @async_test
    async def testShutdownBootedSimulatorBeforeErasing(self):
        simulator = await self.assertCreatesSimulator([self.device_type])
        await self.assertEventSuccesful([simulator.udid, 'boot'], 'boot')
        await self.assertListContainsOnly([simulator.udid], ['--state=booted'])
        await self.assertEventSuccesful([simulator.udid, 'erase'], 'erase')
        await self.assertListContainsOnly([simulator.udid], ['--state=shutdown'])

    @async_test
    async def testLaunchesSystemApplication(self):
        await self.assertLaunchesSystemApplication()

    @async_test
    async def testLaunchesThenTerminatesSystemApplication(self):
        (simulator, bundle_id) = await self.assertLaunchesSystemApplication()
        await self.assertEventSuccesful([simulator.udid, 'terminate', bundle_id], 'terminate')

    @async_test
    async def testUploadsVideo(self):
        simulator = await self.assertCreatesSimulator([self.device_type])
        await self.assertEventSuccesful([simulator.udid, 'boot'], 'boot')
        await self.assertEventSuccesful([simulator.udid, 'upload', Fixtures.VIDEO], 'upload')
        await self.assertEventSuccesful([simulator.udid, 'shutdown'], 'shutdown')

    @async_test
    async def testInstallsUserApplication(self):
        simulator = await self.assertCreatesSimulator([self.device_type])
        await self.assertInstallsUserApplication(
            simulator.udid,
            Fixtures.APP_PATH,
            Fixtures.APP_BUNDLE_ID,
        )
        await self.assertEventSuccesful([simulator.udid, 'shutdown'], 'shutdown')

    @async_test
    async def testInstallsIPA(self):
        ipafile = make_ipa(self.tmpdir, Fixtures.APP_PATH)
        simulator = await self.assertCreatesSimulator([self.device_type])
        await self.assertInstallsUserApplication(
            simulator.udid,
            ipafile,
            Fixtures.APP_BUNDLE_ID,
        )
        await self.assertEventSuccesful([simulator.udid, 'shutdown'], 'shutdown')

    @async_test
    async def testRecordsVideo(self):
        if self.metal.is_supported() is False:
            log.info('Metal not supported, skipping testRecordsVideo')
            return
        (simulator, _) = await self.assertLaunchesSystemApplication()
        arguments = [
            simulator.udid,
            'record', 'start',
            '--', 'listen',
            '--', 'record', 'stop',
        ]
        # Launch the process, terminate and confirm teardown is successful
        async with self.fbsimctl.launch(arguments) as process:
            await process.wait_for_event('listen', 'started')
            await process.terminate()
            await process.wait_for_event('listen', 'ended')
        # Get the diagnostics
        events = await self.assertEventsFromRun(
            [simulator.udid, 'diagnose'],
            'diagnostic',
            'discrete',
        )
        diagnose_events = self.assertExtractAndKeyDiagnostics(events)
        # Confirm the video exists
        video_path = diagnose_events['video']['location']
        self.assertTrue(
            os.path.exists(video_path),
            'Video at path {} should exist'.format(video_path),
        )

    @async_test
    async def testDiagnosticPaths(self):
        simulator = await self.assertCreatesSimulator([self.device_type])
        events = await self.fbsimctl.run([simulator.udid, 'diagnose', '--path'])
        diagnostic_names = [
            event['subject']['short_name']
            for event
            in events.matching('diagnostic', 'discrete')
        ]
        self.assertIn('coresimulator', diagnostic_names)


class SuiteBuilder:
    def __init__(self, fbsimctl_path, device_types, name_filter=None):
        self.fbsimctl_path = fbsimctl_path
        self.device_types = device_types
        self.name_filter = name_filter
        self.loader = unittest.defaultTestLoader

    def _filter_methods(self, cls, methods):
        log.info('All Tests for {} {}'.format(
            cls.__name__,
            methods,
        ))
        if not self.name_filter:
            return methods
        filtered = [method for method in methods if self.name_filter.lower() in method.lower()]
        log.info('Filtered Tests for {}'.format(
            cls.__name__,
            filtered,
        ))
        return filtered

    def _get_base_methods(self):
        return self._filter_methods(
            FBSimctlTestCase,
            self.loader.getTestCaseNames(FBSimctlTestCase)
        )

    def _get_extended_methods(self, cls, base_methods):
        return self._filter_methods(
            cls,
            set(self.loader.getTestCaseNames(cls)) - set(base_methods),
        )

    def build(self):
        # Run all the tests in the base test case against custom & default set
        suite = unittest.TestSuite()
        base_methods = self._get_base_methods()
        suite.addTests([
            FBSimctlTestCase(
                methodName=method_name,
                fbsimctl_path=self.fbsimctl_path,
                use_custom_set=use_custom_set,
            )
            for method_name in base_methods
            for use_custom_set in [True, False]
        ])
        # Only run per-Simulator-Type tests against a custom set.
        suite.addTests([
            SingleSimulatorTestCase(
                methodName=method_name,
                fbsimctl_path=self.fbsimctl_path,
                device_type=device_type,
            )
            for method_name in self._get_extended_methods(SingleSimulatorTestCase, base_methods)
            for device_type in self.device_types
        ])
        # Only run per-Webserver-Type tests against a custom set.
        suite.addTests([
            WebserverSimulatorTestCase(
                methodName=method_name,
                fbsimctl_path=self.fbsimctl_path,
                port=8090,
            )
            for method_name in self._get_extended_methods(WebserverSimulatorTestCase, base_methods)
        ])
        # Only run multiple-Simulator tests against a custom set.
        suite.addTests([
            MultipleSimulatorTestCase(
                methodName=method_name,
                fbsimctl_path=self.fbsimctl_path,
            )
            for method_name
            in self._get_extended_methods(MultipleSimulatorTestCase, base_methods)
        ])
        return suite


if __name__ == '__main__':
    parser = argparse.ArgumentParser(
        description='fbsimctl e2e test runner',
    )
    parser.add_argument(
        '--fail-fast',
        action='store_true',
        help='Whether to fail fast',
    )
    parser.add_argument(
        '--fbsimctl-path',
        default='executable-under-test/bin/fbsimctl',
        help='The location of the fbsimctl executable',
    )
    parser.add_argument(
        '--name-filter',
        default=None,
        help='A substring to match tests against, will only run matching tests',
    )
    parser.add_argument(
        '--device-type',
        action='append',
        help='The iOS Device Type to run tests against. Multiple may be given.',
        default=[],
    )
    arguments: Any = parser.parse_args()
    arguments.device_type = list(set(arguments.device_type))
    if not len(arguments.device_type):
        arguments.device_type = ['iPhone 6']
    defaults = Defaults(arguments.fbsimctl_path)

    suite_builder = SuiteBuilder(
        fbsimctl_path=defaults.fbsimctl_path,
        device_types=arguments.device_type,
        name_filter=arguments.name_filter,
    )
    runner = unittest.TextTestRunner(
        verbosity=2,
        failfast=arguments.fail_fast,
    )
    result = runner.run(suite_builder.build())
    parser.exit(
        status=0 if result.wasSuccessful() else 1,
    )
