from util import (FBSimctl, Simulator, EXECUTABLE_PATH)
import unittest
import tempfile

class FBSimctlTestCase(unittest.TestCase):
    def setUp(self):
        self.fbsimctl = FBSimctl(EXECUTABLE_PATH, self.provideSetPath())

    def provideSetPath(self):
        return None

    def assertEventSuccesful(self, arguments, event_name):
        events = self.fbsimctl.run(arguments)
        matching_events = events.matching(event_name, 'ended')
        match_count = len(matching_events)
        self.assertNotEqual(
            0,
            match_count,
            'Expected one successful {} event, but there were none. Other events: \b {}'.format(
                event_name,
                events
            )
        )
        self.assertLess(
            match_count,
            2,
            'Expected one successful {} event, but there were {}. Matching events: \b {}'.format(
                event_name,
                str(match_count),
                matching_events,
            )
        )
        return matching_events[0]

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


class TestDefaultDeviceSet(FBSimctlTestCase):
    def testList(self):
        self.fbsimctl(['list'])

    def testCommandThatDoesNotExist(self):
        with self.assertRaises(Exception):
            self.fbsimctl(['foo'])


class TestCustomDeviceSet(FBSimctlTestCase):
    def provideSetPath(self):
        return tempfile.mkdtemp()

    def testCreateDeleteiPhone6(self):
        self.assertListContainsOnly([])
        simulator = self.assertExtractSimulator(
            self.assertEventSuccesful(['create', 'iPhone 6'], 'create')
        )
        self.assertListContainsOnly([simulator.get_udid()])
        self.assertEventSuccesful([simulator.get_udid(), 'delete'], 'delete')
        self.assertListContainsOnly([])
