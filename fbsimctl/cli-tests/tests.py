#!/usr/bin/env python3

from util import (
    FBSimctl,
    Simulator,
    WebServer,
    Defaults,
    Fixtures,
    Metal,
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
        methodName,
        fbsimctl_path,
        use_custom_set,
    ):
        super(FBSimctlTestCase, self).__init__(methodName)
        set_path = tempfile.mkdtemp() if use_custom_set else None
        self.methodName = methodName
        self.use_custom_set = use_custom_set
        self.fbsimctl = FBSimctl(fbsimctl_path, set_path)
        self.metal = Metal()
        self.tmpdir = tempfile.mkdtemp()

    def tearDown(self):
        action = 'delete' if self.use_custom_set else 'shutdown'
        self.fbsimctl(['--simulators', action])
        shutil.rmtree(self.tmpdir, ignore_errors=True)

    def __str__(self):
        return '{}: {}'.format(
            self.methodName,
            'Custom Set' if self.use_custom_set else 'Default Set',
        )

    def assertEventSuccesful(self, arguments, event_name):
        return self.assertEventsFromRun(
            arguments=arguments,
            event_name=event_name,
            event_type='ended',
            min_count=1,
            max_count=1,
        )[0]

    def assertEventsFromRun(
        self,
        arguments,
        event_name,
        event_type,
        min_count=1,
        max_count=None,
        timeout=Defaults.TIMEOUT,
    ):
        events = self.fbsimctl.run(arguments, timeout)
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

    def assertListContainsOnly(self, expected_udids, query=[]):
        events = self.fbsimctl.run(query + ['list'])
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

    def assertExtractSimulator(self, json_event):
        sim_json = json_event.get('subject')
        self.assertIsNotNone(
            sim_json,
            'Expected {} to contain a simulator, but it did not'.format(
                json_event,
            )
        )
        return Simulator(sim_json)

    def assertExtractAndKeyDiagnostics(self, json_events):
        return {
            event['subject']['short_name']: event['subject']
            for event
            in json_events
        }

    def assertCreatesSimulator(self, args):
        args = ['create'] + args
        return self.assertExtractSimulator(
            self.assertEventSuccesful(args, 'create')
        )

    def testList(self):
        self.fbsimctl(['list'])

    def testCommandThatDoesNotExist(self):
        with self.assertRaises(Exception):
            self.fbsimctl(['foo'])


class MultipleSimulatorTestCase(FBSimctlTestCase):
    def __init__(
        self,
        methodName,
        fbsimctl_path,

    ):
        super(MultipleSimulatorTestCase, self).__init__(
            methodName=methodName,
            fbsimctl_path=fbsimctl_path,
            use_custom_set=True,
        )

    def testConstructsMissingDefaults(self):
        self.assertEventsFromRun(
            arguments=['create', '--all-missing-defaults'],
            event_name='create',
            event_type='ended',
            timeout=Defaults.LONG_TIMEOUT,
        )


class WebserverSimulatorTestCase(FBSimctlTestCase):
    def __init__(
        self,
        methodName,
        fbsimctl_path,
        port,
    ):
        super(WebserverSimulatorTestCase, self).__init__(
            methodName=methodName,
            fbsimctl_path=fbsimctl_path,
            use_custom_set=True,
        )
        self.port = port

    def extractSimulatorSubjects(self, response):
        self.assertEqual(response['status'], 'success')
        return [
            Simulator(event['subject']).get_udid()
            for event
            in response['subject']
        ]

    @contextlib.contextmanager
    def launchWebserver(self):
        arguments = [
            '--simulators', 'listen', '--http', str(self.port),
        ]
        with self.fbsimctl.launch(arguments) as process:
            process.wait_for_event('listen', 'started')
            yield WebServer(self.port)

    def testInstallsUserApplication(self):
        simulator = self.assertCreatesSimulator(['iPhone 6'])
        self.assertEventSuccesful([simulator.get_udid(), 'boot'], 'boot')
        ipafile = make_ipa(self.tmpdir, Fixtures.APP_PATH)
        with self.launchWebserver() as webserver, open(ipafile, 'rb') as ipa:
            response = webserver.post_binary(
                '{}/install'.format(simulator.get_udid()),
                ipa,
                os.path.getsize(ipafile),
            )
            self.assertEqual(response.get('status'), 'success')
        events = self.fbsimctl.run([simulator.get_udid(), 'list_apps'])
        event = events.matching('list_apps', 'discrete')[0]
        bundle_ids = [entry.get('bundle_id') for entry in event.get('subject')]
        return self.assertIn(Fixtures.APP_BUNDLE_ID, bundle_ids)

    def testDiagnosticSearch(self):
        with self.launchWebserver() as webserver:
            response = webserver.post('diagnose', {'type': 'all'})
            self.assertEqual(response['status'], 'success')

    def testGetCoreSimulatorLog(self):
        iphone6 = self.assertCreatesSimulator(['iPhone 6'])
        with self.launchWebserver() as webserver:
            response = webserver.get(
                iphone6.get_udid() + '/diagnose/coresimulator',
            )
            self.assertEqual(response['status'], 'success')
            event = response['subject'][0]
            self.assertEqual(event['event_name'], 'diagnostic')
            self.assertEqual(event['event_type'], 'discrete')
            diagnostic = event['subject']
            self.assertEqual(diagnostic['short_name'], 'coresimulator')
            self.assertIsNotNone(diagnostic.get('contents'))

    def testListSimulators(self):
        iphone6 = self.assertCreatesSimulator(['iPhone 6'])
        iphone6s = self.assertCreatesSimulator(['iPhone 6s'])
        with self.launchWebserver() as webserver:
            actual = self.extractSimulatorSubjects(
                webserver.get('list'),
            )
            expected = [
                iphone6.get_udid(),
                iphone6s.get_udid(),
            ]
            self.assertEqual(expected.sort(), actual.sort())
            actual = self.extractSimulatorSubjects(
                webserver.get(iphone6.get_udid() + '/list'),
            )
            expected = [iphone6.get_udid()]

    def testUploadsVideo(self):
        simulator = self.assertCreatesSimulator(['iPhone 6'])
        self.assertEventSuccesful([simulator.get_udid(), 'boot'], 'boot')
        with open(Fixtures.VIDEO, 'rb') as f, self.launchWebserver() as webserver:
            data = base64.b64encode(f.read()).decode()
            webserver.post(simulator.get_udid() + '/upload', {
                'short_name': 'video',
                'file_type': 'mp4',
                'data': data,
            })
        self.assertEventSuccesful([simulator.get_udid(), 'shutdown'], 'shutdown')

    def testScreenshot(self):
        if self.metal.is_supported() is False:
            log.info('Metal not supported, skipping testScreenshot')
            return
        simulator = self.assertCreatesSimulator(['iPhone 6'])
        self.assertEventSuccesful([simulator.get_udid(), 'boot'], 'boot')
        with self.launchWebserver() as webserver:
            webserver.get_binary(simulator.get_udid() + '/screenshot.png')
            webserver.get_binary(simulator.get_udid() + '/screenshot.jpeg')


class SingleSimulatorTestCase(FBSimctlTestCase):
    def __init__(
        self,
        methodName,
        fbsimctl_path,
        device_type,
    ):
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

    def testCreateThenDelete(self):
        self.assertListContainsOnly([])
        simulator = self.assertCreatesSimulator([self.device_type])
        self.assertListContainsOnly([simulator.get_udid()])
        self.assertEventSuccesful([simulator.get_udid(), 'delete'], 'delete')
        self.assertListContainsOnly([])

    def testBootsViaSimulatorApp(self):
        simulator = self.assertCreatesSimulator([self.device_type])
        self.assertEventSuccesful([simulator.get_udid(), 'boot'], 'boot')
        self.assertEventSuccesful([simulator.get_udid(), 'shutdown'], 'shutdown')

    def testBootsDirectly(self):
        if self.metal.is_supported() is False:
            log.info('Metal not supported, skipping testBootsDirectly')
            return
        simulator = self.assertCreatesSimulator([self.device_type])
        self.assertEventSuccesful([simulator.get_udid(), 'boot', '--direct-launch'], 'boot')
        self.assertEventSuccesful([simulator.get_udid(), 'shutdown'], 'shutdown')

    def testShutdownBootedSimulatorBeforeErasing(self):
        simulator = self.assertCreatesSimulator([self.device_type])
        self.assertEventSuccesful([simulator.get_udid(), 'boot'], 'boot')
        self.assertListContainsOnly([simulator.get_udid()], ['--state=booted'])
        self.assertEventSuccesful([simulator.get_udid(), 'erase'], 'erase')
        self.assertListContainsOnly([simulator.get_udid()], ['--state=shutdown'])

    def testLaunchesSystemApplication(self):
        simulator = self.assertCreatesSimulator([self.device_type])
        self.assertEventSuccesful([simulator.get_udid(), 'boot'], 'boot')
        self.assertEventSuccesful([simulator.get_udid(), 'launch', 'com.apple.Preferences'], 'launch')
        self.assertEventsFromRun([simulator.get_udid(), 'service_info', 'com.apple.Preferences'], 'service_info', 'discrete')
        return (simulator, 'com.apple.Preferences')

    def testLaunchesThenTerminatesSystemApplication(self):
        (simulator, bundle_id) = self.testLaunchesSystemApplication()
        self.assertEventSuccesful([simulator.get_udid(), 'terminate', bundle_id], 'terminate')

    def testUploadsVideo(self):
        simulator = self.assertCreatesSimulator([self.device_type])
        self.assertEventSuccesful([simulator.get_udid(), 'boot'], 'boot')
        self.assertEventSuccesful([simulator.get_udid(), 'upload', Fixtures.VIDEO], 'upload')
        self.assertEventSuccesful([simulator.get_udid(), 'shutdown'], 'shutdown')

    def assertInstallsUserApplication(self, udid, path, bundle_id):
        self.assertEventSuccesful([udid, 'boot'], 'boot')
        self.assertEventSuccesful([udid, 'install', path], 'install')
        events = self.fbsimctl.run([udid, 'list_apps'])
        event = events.matching('list_apps', 'discrete')[0]
        bundle_ids = [entry.get('bundle_id') for entry in event.get('subject')]
        return self.assertIn(bundle_id, bundle_ids)

    def testInstallsUserApplication(self):
        simulator = self.assertCreatesSimulator([self.device_type])
        self.assertInstallsUserApplication(
            simulator.get_udid(),
            Fixtures.APP_PATH,
            Fixtures.APP_BUNDLE_ID,
        )
        self.assertEventSuccesful([simulator.get_udid(), 'shutdown'], 'shutdown')

    def testInstallsIPA(self):
        ipafile = make_ipa(self.tmpdir, Fixtures.APP_PATH)
        simulator = self.assertCreatesSimulator([self.device_type])
        self.assertInstallsUserApplication(
            simulator.get_udid(),
            ipafile,
            Fixtures.APP_BUNDLE_ID,
        )
        self.assertEventSuccesful([simulator.get_udid(), 'shutdown'], 'shutdown')

    def testRecordsVideo(self):
        if self.metal.is_supported() is False:
            log.info('Metal not supported, skipping testRecordsVideo')
            return
        (simulator, _) = self.testLaunchesSystemApplication()
        arguments = [
            simulator.get_udid(),
            'record', 'start',
            '--', 'listen',
            '--', 'record', 'stop',
        ]
        # Launch the process, terminate and confirm teardown is successful
        with self.fbsimctl.launch(arguments) as process:
            process.wait_for_event('listen', 'started')
            process.terminate()
            process.wait_for_event('listen', 'ended')
        # Get the diagnostics
        diagnose_events = self.assertExtractAndKeyDiagnostics(
            self.assertEventsFromRun(
                [simulator.get_udid(), 'diagnose'],
                'diagnostic',
                'discrete',
            ),
        )
        # Confirm the video exists
        video_path = diagnose_events['video']['location']
        self.assertTrue(
            os.path.exists(video_path),
            'Video at path {} should exist'.format(video_path),
        )


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
    parser = argparse.ArgumentParser()
    parser.description = 'fbsimctl e2e test runner'
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
    arguments = parser.parse_args()
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
        failfast=True,
    )
    result = runner.run(suite_builder.build())
    parser.exit(
        status=0 if result.wasSuccessful() else 1,
    )
