#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates.
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

from typing import List, Any, Optional, Dict
import asyncio
import json
import logging
import os
import shlex
import shutil
import subprocess
import time
import urllib.request

# Setup the Logger
logging.basicConfig(format='%(message)s')
log = logging.getLogger()
log.setLevel(logging.INFO)

def async_test(f):
    def wrapper(*args, **kwargs):
        coro = asyncio.coroutine(f)
        future = coro(*args, **kwargs)
        loop = asyncio.get_event_loop()
        loop.run_until_complete(future)
    return wrapper


class Defaults:
    TIMEOUT = 120
    LONG_TIMEOUT = 500

    def __init__(self, expected_path):
        self.fbsimctl_path = self.find_fbsimctl_path(expected_path)

    def find_fbsimctl_path(self, expected_path):
        if os.path.exists(expected_path):
            fbsimctl_path = os.path.realpath(expected_path)
            log.info('Using fbsimctl test executable at {}'.format(fbsimctl_path))
            return fbsimctl_path
        else:
            log.info('Using fbsimctl on PATH')
            return 'fbsimctl'


class Events:
    def __init__(
        self,
        events: List[Dict],
    ) -> None:
        self.__events = events

    def extend(
        self,
        events: List[Dict],
    ) -> None:
        self.__events.extend(events)

    def __repr__(self):
        return '\n'.join(
            [str(event) for event in self.__events],
        )

    def matching(
        self,
        event_name: str,
        event_type: str,
    ) -> List[Dict]:
        return [
            event for event in self.__events
            if event['event_name'] == event_name and event['event_type'] == event_type
        ]


class Simulator:
    def __init__(self, json):
        self.__json = json

    def __repr__(self):
        return str(self.__json)

    @property
    def udid(self):
        return self.__json['udid']


class FBSimctlProcess:
    def __init__(
        self,
        arguments: List[str],
        timeout: int,
    ) -> None:
        self.__arguments = arguments
        self.__timeout = timeout
        self.__events = Events([])
        self.__process: Optional[Any] = None

    async def wait_for_event(
        self,
        event_name: str, 
        event_type: str, 
        timeout: Optional[int] = None,
    ) -> None:
        coro = self._wait_for_event(event_name, event_type, self.__process.stdout)
        if timeout is None:
            await coro
        else:
            await asyncio.wait_for(coro, timeout)

    async def start(self) -> 'FBSimctlProcess':
        if self.__process:
            raise Exception(
                'A Process {} has allready started'.format(self.__process),
            )
        self.__process = await self._start_process()
        return self

    async def terminate(self, wait=False):
        await self._terminate_process(wait),

    async def __aenter__(self):
        return await self.start()

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        await self.terminate(wait=True)

    async def _start_process(self):
        log.info('Opening Process with Arguments {0}'.format(
            ' '.join(self.__arguments),
        ))
        create = asyncio.create_subprocess_exec(
            *self.__arguments,
            stdout=asyncio.subprocess.PIPE,
            stderr=None,
        )
        process = await create
        return process

    async def _terminate_process(
        self, 
        wait: bool,
    ) -> None:
        if not self.__process:
            raise Exception(
                'Cannot terminate a process when none has started',
            )
        if self.__process.returncode is not None:
            return
        log.info('Terminating {0}'.format(self.__process))
        self.__process.terminate()
        if not wait:
            log.info('Passing Back to Consumer')
            return
        await self.__process.communicate()
        log.info('Terminated {0}'.format(self.__process))

    async def _wait_for_event(
        self,
        event_name: str,
        event_type: str,
        reader: asyncio.StreamReader,
    ) -> Any:
        matching = self._match_event(
            event_name,
            event_type,
        )
        if matching:
            return matching
        while True:
            data = await reader.readline()
            line = data.decode('utf-8').rstrip()
            if not len(line) and reader.at_eof():
                raise Exception(
                    'Reached end of output waiting for {0}/{1}'.format(
                    event_name,
                    event_type,
                ))
            log.info(line)
            event = json.loads(line)
            matching = self._match_event(
                event_name,
                event_type,
                json.loads(line),
            )
            if matching:
                return matching

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
    def __init__(
        self, 
        executable_path: str, 
        set_path: Optional[str] = None,
    ) -> None:
        self.__executable_path = executable_path
        self.__set_path = set_path

    def __call__(self, arguments):
        return self.run(arguments)

    def _make_arguments(
        self, 
        arguments: List[str] = [],
    ) -> List[str]:
        base_arguments = [self.__executable_path]
        if self.__set_path:
            base_arguments += ['--set', self.__set_path]
        base_arguments.append('--json')
        return base_arguments + arguments

    async def run(
        self, 
        arguments: List[str], 
        timeout: int = Defaults.TIMEOUT,
    ) -> Events:
        arguments = self._make_arguments(arguments)
        log.info('Running Process with Arguments {0}'.format(
            ' '.join(arguments),
        ))
        process = await asyncio.create_subprocess_exec(
            *arguments,
            stdout=subprocess.PIPE,
            stderr=None,
        )
        (stdout, _) = await process.communicate()
        if process.returncode is not 0:
            raise Exception(
                f'Nonzero exit code {process.returncode} {stdout}'
            )
        events = [
            json.loads(line) for line in str(stdout, 'utf-8').splitlines() if len(line)
        ]
        return Events(events)

    def launch(
        self,
        arguments: List[str], 
        timeout: int = Defaults.TIMEOUT,
    ):
        return FBSimctlProcess(
            arguments=self._make_arguments(arguments),
            timeout=timeout,
        )

class Metal:
    def __init__(self):
        self.__supports_metal_exit_code = subprocess.call(
            ['./supports_metal.swift'], 
            stdout=subprocess.DEVNULL, 
            stderr=subprocess.DEVNULL,
        )

    def is_supported(self):
        return self.__supports_metal_exit_code == 0

class WebServer:

    def __init__(
        self,
        port: int,
        fbsimctl: FBSimctl,
    ) -> None:
        self.__port = port
        self.__fbsimctl = fbsimctl
        self.__process: Optional[FBSimctlProcess] = None

    async def __aenter__(self):
        arguments = [
            '--simulators', 'listen', '--http', str(self.__port),
        ]
        self.__process = await self.__fbsimctl.launch(arguments).__aenter__()
        await self.__process.wait_for_event('listen', 'started')
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        await self.__process.__aexit__(exc_type, exc_val, exc_tb)
        self.__process = None

    def get(
        self, 
        path: str,
    ) -> Dict:
        request = urllib.request.Request(
            url=self._make_url(path),
            method='GET',
        )
        return self._perform_request(request)

    def get_binary(
        self, 
        path: str,
    ) -> bytes:
        request = urllib.request.Request(
            url=self._make_url(path),
            method='GET',
        )
        return self._perform_request_binary(request)

    def post(
        self,
        path: str,
        payload: Dict,
    ) -> Dict:
        data = json.dumps(payload).encode('utf-8')
        request = urllib.request.Request(
            url=self._make_url(path),
            data=data,
            method='POST',
            headers={'content-type': 'application/json'},
        )
        return self._perform_request(request)

    def post_binary(
        self,
        path: str,
        file: Any, 
        length: int,
    ) -> Dict:
        request = urllib.request.Request(
            self._make_url(path),
            file,
            method='POST',
            headers={'content-length': str(length)},
        )
        return self._perform_request(request)

    def _make_url(
        self, 
        path: str,
    ) -> str:
        return 'http://localhost:{}/{}'.format(
            self.__port,
            path,
        )

    def _perform_request(
        self, 
        request: urllib.request.Request,
    ) -> Dict:
        with urllib.request.urlopen(request) as f:
            response = f.read().decode('utf-8')
            return json.loads(response)

    def _perform_request_binary(
        self,
        request: urllib.request.Request,
    ) -> bytes:
        with urllib.request.urlopen(request) as f:
            return f.read()


class Fixtures:
    VIDEO = os.path.realpath(
        os.path.join(
            __file__,
            '../../../FBSimulatorControlTests/Fixtures/video0.mp4',
        ),
    )

    APP_PATH = os.path.realpath(
        os.path.join(
            __file__,
            '../../../Fixtures/Binaries/TableSearch.app'
        )
    )

    APP_BUNDLE_ID = 'com.example.apple-samplecode.TableSearch'


def make_ipa(dest_dir, app):
    payload = os.path.join(dest_dir, 'Payload')
    os.mkdir(payload)
    shutil.copytree(
        app,
        os.path.join(payload, os.path.basename(app))
    )
    zipfile = shutil.make_archive('app', 'zip', root_dir=payload)
    ipafile = '{}.ipa'.format(zipfile)
    shutil.move(zipfile, ipafile)
    return ipafile
