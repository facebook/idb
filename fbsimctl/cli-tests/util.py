#!/usr/bin/env python3

import json
import logging
import os
import subprocess

# Setup the Logger
logging.basicConfig(format='%(message)s')
log = logging.getLogger()
log.setLevel(logging.INFO)

DEFAULT_TIMEOUT = 100


def find_fbsimctl_path(expected_path):
    if os.path.exists(expected_path):
        fbsimctl_path = os.path.realpath(expected_path)
        log.info('Using fbsimctl test executable at {}'.format(fbsimctl_path))
        return fbsimctl_path
    else:
        log.info('Using fbsimctl on PATH')
        return 'fbsimctl'


class Events:
    def __init__(self, events):
        self.__events = events

    def __repr__(self):
        return '\n'.join(
            [str(event) for event in self.__events],
        )

    def matching(self, event_name, event_type):
        return [
            event for event in self.__events
            if event['event_name'] == event_name and event['event_type'] == event_type
        ]


class Simulator:
    def __init__(self, json):
        self.__json = json

    def __repr__(self):
        return str(self.__json)

    def get_udid(self):
        return self.__json['udid']


class FBSimctl:
    def __init__(self, executable_path, set_path=None):
        self.__executable_path = executable_path
        self.__set_path = set_path

    def __call__(self, arguments):
        return self.run(arguments)

    def _make_arguments(self, arguments=[]):
        base_arguments = [self.__executable_path]
        if self.__set_path:
            base_arguments += ['--set', self.__set_path]
        base_arguments.append('--json')
        return base_arguments + arguments

    def _make_process(self, arguments=[]):
        return subprocess.Popen(
            arguments,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            shell=False,
        )

    def run(self, arguments, timeout=DEFAULT_TIMEOUT):
        arguments = self._make_arguments(arguments)
        with self._make_process(arguments) as process:
            process.wait(timeout=DEFAULT_TIMEOUT)
            events = []
            if process.returncode != 0:
                raise Exception(
                    '{0} resulted in a non-zero return code {1} {2}'.format(
                        arguments,
                        process.returncode,
                        events,
                    )
                )
            with io.TextIOWrapper(process.stdout, encoding='utf-8') as text:
                for line in text:
                    events += [json.loads(line)]
            return Events(
                events
            )
