#!/usr/bin/env python3

from util import (FBSimctl, Simulator, find_fbsimctl_path)
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
        max_count=None
    ):
        events = self.fbsimctl.run(arguments)
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

    def assertListContainsOnly(self, expected_udids):
        events = self.fbsimctl.run(['list'])
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


class FBSimctlSimulatorTestCase(FBSimctlTestCase):
    def __init__(
        self,
        methodName,
        fbsimctl_path,
        use_custom_set,
        device_type,
    ):
        super(FBSimctlSimulatorTestCase, self).__init__(
            methodName=methodName,
            fbsimctl_path=fbsimctl_path,
            use_custom_set=use_custom_set,
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


def build_suite(fbsimctl_path, device_types):
    # Run all the tests in the base test case against custom & default set
    base_methods = set(unittest.defaultTestLoader.getTestCaseNames(FBSimctlTestCase))
    suite = unittest.TestSuite()
    for methodName in base_methods:
        suite.addTests([
            FBSimctlTestCase(
                methodName=methodName,
                fbsimctl_path=fbsimctl_path,
                use_custom_set=False,
            ),
            FBSimctlTestCase(
                methodName=methodName,
                fbsimctl_path=fbsimctl_path,
                use_custom_set=True,
            ),
        ])
    # Only run per-Simulator-Type tests against a custom set
    custom_set_methods = set(unittest.defaultTestLoader.getTestCaseNames(FBSimctlSimulatorTestCase)) - base_methods
    for method_name in custom_set_methods:
        for device_type in device_types:
            suite.addTest(
                FBSimctlSimulatorTestCase(
                    methodName=method_name,
                    fbsimctl_path=fbsimctl_path,
                    use_custom_set=True,
                    device_type=device_type,
                ),
            )
    return suite


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.description = 'fbsimctl e2e test runner'
    parser.add_argument(
        '--fbsimctl-path',
        default='executable-under-test/fbsimctl',
        help='The location of the fbsimctl executable',
    )
    arguments = parser.parse_args()

    suite = build_suite(
        fbsimctl_path=find_fbsimctl_path(arguments.fbsimctl_path),
        device_types=['iPhone 6', 'iPad Air 2'],
    )
    runner = unittest.TextTestRunner(
        verbosity=2,
        failfast=True,
    )
    runner.run(suite)
