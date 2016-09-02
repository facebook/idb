#!/usr/bin/env python3

from util import (FBSimctl, Simulator, WebServer, find_fbsimctl_path, DEFAULT_TIMEOUT, LONG_TIMEOUT)
import argparse
import os
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

    def tearDown(self):
        action = 'delete' if self.use_custom_set else 'shutdown'
        self.fbsimctl(['--simulators', action])

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
        timeout=DEFAULT_TIMEOUT,
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
            timeout=LONG_TIMEOUT,
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
        self.webserver = WebServer(port)

    def testRemotelyRecords(self):
        arguments = [
            'listen', '--http', str(self.port),
        ]
        # Launch the process, terminate and confirm teardown is successful
        with self.fbsimctl.launch(arguments) as process:
            process.wait_for_event('listen', 'started')
            response = self.webserver.request('diagnose', {'type': 'all'})
            self.assertEqual(response['status'], 'success')


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
        return (simulator, 'com.apple.Preferences')

    def testLaunchesThenTerminatesSystemApplication(self):
        (simulator, bundle_id) = self.testLaunchesSystemApplication()
        self.assertEventSuccesful([simulator.get_udid(), 'terminate', bundle_id], 'terminate')

    def testRecordsVideo(self):
        simulator = self.assertCreatesSimulator([self.device_type])
        arguments = [
            simulator.get_udid(), 'boot', '--direct-launch',
            '--', 'record', 'start',
            '--', 'listen',
            '--', 'shutdown',
        ]
        # Launch the process, terminate and confirm teardown is successful
        with self.fbsimctl.launch(arguments) as process:
            process.wait_for_event('listen', 'started')
            process.terminate()
            process.wait_for_event('listen', 'ended')
            process.wait_for_event('shutdown', 'ended')
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
    def __init__(self, fbsimctl_path, name_filter=None, device_types=['iPhone 6', 'iPad Air 2']):
        self.fbsimctl_path = fbsimctl_path
        self.device_types = device_types
        self.name_filter = name_filter
        self.loader = unittest.defaultTestLoader

    def _filter_methods(self, methods):
        if not self.name_filter:
            return methods
        return [method for method in methods if self.name_filter.lower() in method.lower()]

    def _get_base_methods(self):
        return self._filter_methods(
            self.loader.getTestCaseNames(FBSimctlTestCase)
        )

    def _get_webserver_methods(self):
        return self._filter_methods(
            set(self.loader.getTestCaseNames(WebserverSimulatorTestCase)) - set(self._get_base_methods()),
        )

    def _get_single_simulator_methods(self):
        return self._filter_methods(
            set(self.loader.getTestCaseNames(SingleSimulatorTestCase)) - set(self._get_base_methods()),
        )

    def _get_multiple_simulator_methods(self):
        return self._filter_methods(
            set(self.loader.getTestCaseNames(MultipleSimulatorTestCase)) - set(self._get_base_methods()),
        )

    def build(self):
        # Run all the tests in the base test case against custom & default set
        suite = unittest.TestSuite()
        suite.addTests([
            FBSimctlTestCase(
                methodName=method_name,
                fbsimctl_path=self.fbsimctl_path,
                use_custom_set=use_custom_set,
            )
            for method_name in self._get_base_methods()
            for use_custom_set in [True, False]
        ])
        # Only run per-Simulator-Type tests against a custom set.
        suite.addTests([
            SingleSimulatorTestCase(
                methodName=method_name,
                fbsimctl_path=self.fbsimctl_path,
                device_type=device_type,
            )
            for method_name in self._get_single_simulator_methods()
            for device_type in self.device_types
        ])
        # Only run per-Webserver-Type tests against a custom set.
        suite.addTests([
            WebserverSimulatorTestCase(
                methodName=method_name,
                fbsimctl_path=self.fbsimctl_path,
                port=8090,
            )
            for method_name in self._get_webserver_methods()
        ])
        # Only run multiple-Simulator tests against a custom set.
        suite.addTests([
            MultipleSimulatorTestCase(
                methodName=method_name,
                fbsimctl_path=self.fbsimctl_path,
            )
            for method_name
            in self._get_multiple_simulator_methods()
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
    arguments = parser.parse_args()

    suite_builder = SuiteBuilder(
        fbsimctl_path=find_fbsimctl_path(arguments.fbsimctl_path),
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
