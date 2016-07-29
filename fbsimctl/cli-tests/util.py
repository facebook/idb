#!/usr/bin/env python3

import asyncio
import json
import logging
import os
import subprocess
import time

# Setup the Logger
logging.basicConfig(format='%(message)s')
log = logging.getLogger()
log.setLevel(logging.INFO)

DEFAULT_TIMEOUT = 60


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

    def extend(self, events):
        self.__events.extend(events)

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


class FBSimctlProcess:
    def __init__(
        self,
        arguments,
        timeout
    ):
        self.__arguments = arguments
        self.__timeout = timeout
        self.__events = Events([])
        self.__loop = None
        self.__process = None

    def wait_for_event(self, event_name, event_type, timeout=None):
        timeout = timeout if timeout else self.__timeout
        return self.__loop.run_until_complete(
            self._wait_for_event(event_name, event_type, timeout),
        )

    def start(self):
        if self.__process:
            raise Exception(
                'A Process {} has allready started'.format(self.__process),
            )
        self.__process = self.__loop.run_until_complete(
            self._start_process()
        )
        return self

    def terminate(self):
        self.__loop.run_until_complete(
            self._terminate_process(),
        )

    def __enter__(self):
        self.__loop = asyncio.new_event_loop()
        asyncio.set_event_loop(self.__loop)
        return self.start()

    def __exit__(self, exc_type, exc_val, exc_tb):
        self.terminate()
        self.__loop.close()
        self.__loop = None

    @asyncio.coroutine
    def _start_process(self):
        log.info('Opening Process with Arguments {0}'.format(
            self.__arguments,
        ))
        create = asyncio.create_subprocess_exec(
            *self.__arguments,
            stdout=asyncio.subprocess.PIPE,
            stderr=None,
        )
        process = yield from create
        return process

    @asyncio.coroutine
    def _terminate_process(self):
        if not self.__process:
            raise Exception(
                'Cannot termnated a process when none has started',
            )
        if self.__process.returncode is not None:
            return
        log.info('Terminating {0}'.format(self.__process))
        self.__process.terminate()
        yield from self.__process.wait()
        log.info('Terminated {0}'.format(self.__process))

    @asyncio.coroutine
    def _wait_for_event(self, event_name, event_type, timeout):
        matching = self._match_event(
            event_name,
            event_type,
        )
        if matching:
            return matching
        start_time = time.time()
        while time.time() < start_time + timeout:
            data = yield from self.__process.stdout.readline()
            line = data.decode('utf-8').rstrip()
            log.info(line)
            matching = self._match_event(
                event_name,
                event_type,
                json.loads(line),
            )
            if matching:
                return matching
        raise Exception('Timed out waiting for {0}/{1} in {2}'.format(
            event_name,
            event_type,
            events,
        ))

    def _match_event(self, event_name, event_type, json_event=None):
        if json_event:
            self.__events.extend([json_event])
        matching = self.__events.matching(
            event_name,
            event_type,
        )
        if not matching:
            return None
        log.info('{0} matches {1}/{2}'.format(
            matching,
            event_name,
            event_type,
        ))
        return matching


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

    def run(self, arguments, timeout=DEFAULT_TIMEOUT):
        arguments = self._make_arguments(arguments)
        process = subprocess.run(
            arguments,
            stdout=subprocess.PIPE,
            check=True,
            timeout=timeout,
        )
        events = [
            json.loads(line) for line in str(process.stdout, 'utf-8').splitlines()
        ]
        return Events(events)

    def launch(self, arguments, timeout=DEFAULT_TIMEOUT):
        return FBSimctlProcess(
            arguments=self._make_arguments(arguments),
            timeout=timeout,
        )
