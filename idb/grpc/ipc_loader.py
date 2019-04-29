#!/usr/bin/env python3
# Copyright (c) Facebook, Inc. and its affiliates. All Rights Reserved.

import asyncio
import importlib.util
import inspect
import pkgutil
from functools import partial, wraps
from inspect import signature
from types import ModuleType
from typing import (
    Any,
    Awaitable,
    Callable,
    Dict,
    List,
    NamedTuple,
    Optional,
    Tuple,
    Type,
    TypeVar,
)

from grpclib.exceptions import GRPCError, ProtocolError, StreamTerminatedError
from idb.common.boot_manager import BootManager
from idb.grpc.types import CompanionClient
from idb.manager.companion import CompanionManager
from idb.grpc.stream import Stream
from idb.common.logging import log_call
from idb.common.types import IdbException, LoggingMetadata
from idb.grpc.idb_grpc import CompanionServiceStub


"""
This module is responsible for getting client and daemon calls from a set of modules
then providing them as functions that can be annotated into client & daemon classes.

It does this by introspecting all modules within the idb.ipc module
and then traversing them to find the relevant implementations.

This is all vended to consumers as a Tuple[call_name, implementation] that can
then be installed using setattr.

For client calls:
- The name of the module is used as the name of the method.
- The function in the module is called 'client'.
- Modules can also provide extra properties to be attached to the client, for
  the purpose of command aliasing. This can be done by setting CLIENT_PROPERTIES
  to a list of functions

For daemon calls:
- The name of the module is used as the name of the method.
- The function in the module is called 'daemon'
"""

BASE_PACKAGE = "idb.ipc"


class DaemonContext(NamedTuple):
    companion_manager: CompanionManager
    boot_manager: BootManager


CompanionProvider = Callable[[Optional[str]], Awaitable[CompanionClient]]
DaemonContextProvider = Callable[[], Awaitable[DaemonContext]]
DaemonProvider = Callable[[], Awaitable[CompanionClient]]
_T = TypeVar("_T")
_U = TypeVar("_U")


CLIENT_METADATA: LoggingMetadata = {"component": "client", "rpc_protocol": "grpc"}
DAEMON_METADATA: LoggingMetadata = {"component": "daemon", "rpc_protocol": "grpc"}


class MetadataStubInjector(CompanionServiceStub):
    def __init__(self, stub: CompanionServiceStub, metadata: Dict[str, str]) -> None:
        self._stub = stub
        self._metadata = metadata

    def __getattr__(self, name: str) -> Any:  # pyre-ignore
        if not hasattr(self._stub, name):
            return getattr(super(), name)

        call = getattr(self._stub, name)
        metadata = self._metadata

        class StubTrampoline:
            def open(self, *args: Any, **kwargs: Any) -> Any:  # pyre-ignore
                return call.open(*args, **kwargs, metadata=metadata)

            def __call__(self, *args: Any, **kwargs: Any) -> Any:  # pyre-ignore
                return call(*args, **kwargs, metadata=metadata)

        return StubTrampoline()


def _trampoline_client(
    daemon_provider: DaemonProvider, call: Callable, name: str
) -> Callable:
    async def _make_client() -> CompanionClient:
        client = await daemon_provider()
        return CompanionClient(
            stub=MetadataStubInjector(
                stub=client.stub, metadata={"udid": client.udid} if client.udid else {}
            ),
            is_local=client.is_local,
            udid=client.udid,
            logger=client.logger.getChild(name),
        )

    @log_call(name=name, metadata=CLIENT_METADATA)
    @wraps(call)
    async def _tramp(*args: Any, **kwargs: Any) -> Any:  # pyre-ignore
        try:
            client = await _make_client()
            return await call(client, *args, **kwargs)
        except GRPCError as e:
            raise IdbException(e.message) from e  # noqa B306
        except (ProtocolError, StreamTerminatedError) as e:
            raise IdbException(e.args) from e

    @log_call(name=name, metadata=CLIENT_METADATA)
    @wraps(call)
    async def _tramp_gen(*args: Any, **kwargs: Any) -> Any:  # pyre-ignore
        try:
            client = await _make_client()
            async for item in call(client, *args, **kwargs):
                yield item
        except GRPCError as e:
            raise IdbException(e.message) from e  # noqa B306
        except (ProtocolError, StreamTerminatedError) as e:
            raise IdbException(e.args) from e

    if inspect.isasyncgenfunction(call):
        return _tramp_gen
    else:
        return _tramp


def _default_daemon(
    name: str,
) -> Callable[[CompanionClient, Stream[_T, _U]], Awaitable[None]]:
    async def _pipe_to_companion(
        in_stream: Stream[_T, _U],
        out_stream: Stream[_U, _T],
        started_future: asyncio.Future,
    ) -> None:
        async for message in in_stream:
            await out_stream.send_message(message)
            if not started_future.done():
                started_future.set_result(None)
        await out_stream.end()

    async def _pipe_to_client(
        in_stream: Stream[_U, _T],
        out_stream: Stream[_T, _U],
        started_future: asyncio.Future,
    ) -> None:
        await started_future
        async for message in in_stream:
            await out_stream.send_message(message)

    async def _default_daemon_imp(
        client: CompanionClient, stream: Stream[_T, _U]
    ) -> None:
        method = getattr(client.stub, name)
        async with method.open() as out_stream:
            started_future = asyncio.Future()
            await asyncio.gather(
                _pipe_to_companion(stream, out_stream, started_future),
                _pipe_to_client(out_stream, stream, started_future),
            )

    return _default_daemon_imp


def _trampoline_daemon(
    companion_provider: CompanionProvider,
    context_provider: DaemonContextProvider,
    call: Callable,
    name: str,
) -> Callable:
    @log_call(name=name, metadata=DAEMON_METADATA, translate_exceptions=True)
    @wraps(call)
    async def _tramp(stream: Stream[_T, _U], *args: Any, **kwargs: Any) -> None:
        partial_call = call
        if _takes_client(call):
            client = await companion_provider(stream.metadata.get("udid"))
            logger = client.logger.getChild(name)
            companion_client = CompanionClient(
                stub=client.stub,
                is_local=client.is_local,
                udid=client.udid,
                logger=logger,
                is_companion_available=client.is_companion_available,
            )
            partial_call = partial(partial_call, client=companion_client)
        if _takes_context(call):
            context = await context_provider()
            partial_call = partial(partial_call, context=context)

        if _takes_stream(call):
            await partial_call(stream=stream)
        else:
            request = await stream.recv_message()
            response = await partial_call(request=request)
            await stream.send_message(response)

    return _tramp


def _takes_stream(method: Callable) -> bool:
    return _has_parameter(method=method, name="stream", parameter_type=Stream)


def _takes_client(method: Callable) -> bool:
    return _has_parameter(method=method, name="client", parameter_type=CompanionClient)


def _takes_context(method: Callable) -> bool:
    return _has_parameter(method=method, name="context", parameter_type=DaemonContext)


def _has_parameter(
    method: Callable, name: str, parameter_type: Optional[Type[_T]] = None
) -> bool:
    parameters = list(signature(method).parameters.items())
    return any(
        (
            parameter_name == name
            and (
                parameter_type is None
                or is_subclass(parameter.annotation, parameter_type)
            )
            for parameter_name, parameter in parameters
        )
    )


def is_subclass(obj: Type[_T], target_type: Type[_U]) -> bool:
    obj = getattr(obj, "__origin__", obj) or obj
    target_type = getattr(target_type, "__origin__", target_type) or target_type
    return issubclass(obj, target_type)


def _get_rpc_modules(base_package: str = BASE_PACKAGE) -> List[ModuleType]:
    package = importlib.util.find_spec(base_package)
    if package is None:
        return []
    return [
        importlib.import_module(f"{base_package}.{name}")
        for (_, name, ispkg) in pkgutil.iter_modules(package.submodule_search_locations)
        if not ispkg
    ]


def _get_module_name(module: ModuleType) -> str:
    return module.__name__.split(".")[-1]


def client_calls(daemon_provider: DaemonProvider) -> List[Tuple[str, Callable]]:
    return [
        (
            name,
            _trampoline_client(daemon_provider=daemon_provider, call=call, name=name),
        )
        for (name, call) in _client_implementations()
    ]


def _client_implementations() -> List[Tuple[str, Callable]]:
    properties = []
    for module in _get_rpc_modules():
        if hasattr(module, "client"):
            properties.append((_get_module_name(module), module.client))  # pyre-ignore
        for extra_property in getattr(module, "CLIENT_PROPERTIES", []):
            properties.append((extra_property.__name__, extra_property))
    return properties


def daemon_calls(
    companion_provider: CompanionProvider, context_provider: DaemonContextProvider
) -> List[Tuple[str, Callable]]:
    return [
        (
            name,
            _trampoline_daemon(
                companion_provider=companion_provider,
                context_provider=context_provider,
                call=call,
                name=name,
            ),
        )
        for (name, call) in _daemon_implementations()
    ]


def _daemon_implementations() -> List[Tuple[str, Callable]]:
    functions = []
    for module in _get_rpc_modules():
        module_name = _get_module_name(module)
        call = getattr(module, "daemon", _default_daemon(module_name))
        functions.append((module_name, call))
    return functions
