/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
@preconcurrency import XPC

/// A simulator's CoreDevice features, reached one request at a time.
///
/// Owns what every request shares: the device identifier, the installed CoreDevice version (read
/// once), the queue the sessions run on, and how a transport to a service is built. Features
/// describe their action, service, `Encodable` input and `Decodable` output, and nothing else.
/// Memoized per `Simulator` through its command cache.
///
// SAFETY: The version and capability caches are guarded by the lock; everything else is immutable.
// patternlint-disable-next-line unchecked-sendable
final class SimulatorCoreDeviceClient: @unchecked Sendable {
  typealias TransportFactory = @Sendable (_ service: String, _ queue: DispatchQueue) throws -> any SimulatorCoreDeviceTransport
  typealias VersionSource = @Sendable () throws -> CoreDeviceVersion

  private let deviceID: String
  private let queue = DispatchQueue(label: "com.facebook.FBSimulatorControl.coredevice")
  private let makeTransport: TransportFactory
  private let readVersion: VersionSource
  private let lock = NSLock()
  private var cachedVersion: CoreDeviceVersion?
  private var cachedMotionCapabilities: MotionCapabilities?

  convenience init(simulator: Simulator) {
    self.init(
      deviceID: simulator.udid,
      transport: { service, queue in try SimulatorCoreDeviceXPCTransport(simulator: simulator, service: service, queue: queue) },
      version: CoreDeviceVersion.installed)
  }

  init(deviceID: String, transport: @escaping TransportFactory, version: @escaping VersionSource) {
    self.deviceID = deviceID
    self.makeTransport = transport
    self.readVersion = version
  }

  /// The installed CoreDevice version. A host without it fails every request the same way, so a
  /// failure is not cached.
  func version() throws -> CoreDeviceVersion {
    lock.lock()
    defer { lock.unlock() }
    if let cachedVersion { return cachedVersion }
    let version = try readVersion()
    cachedVersion = version
    return version
  }

  /// The motion capabilities the simulator advertises, queried once: they are a property of the
  /// runtime and device type, fixed for the simulator's lifetime. Only an answered query is kept.
  /// A runtime that cannot answer is asked again, since a simulator that is not yet booted cannot
  /// answer either.
  func motionCapabilities() async throws -> MotionCapabilities {
    if let cached = rememberedMotionCapabilities() { return cached }
    let capabilities = try await perform(
      action: MotionCapabilities.action, service: MotionCapabilities.service, input: CoreDeviceEmptyInput(), as: MotionCapabilities.self)
    remember(capabilities)
    return capabilities
  }

  private func rememberedMotionCapabilities() -> MotionCapabilities? {
    lock.lock()
    defer { lock.unlock() }
    return cachedMotionCapabilities
  }

  private func remember(_ capabilities: MotionCapabilities) {
    lock.lock()
    defer { lock.unlock() }
    cachedMotionCapabilities = capabilities
  }

  // MARK: - CoreDevice actions

  /// One action, one reply, with the output decoded by the caller.
  func perform<Input: Encodable, Response: Sendable>(
    action: String, service: String, input: Input,
    decode: @escaping @Sendable (xpc_object_t) throws -> Response
  ) async throws -> Response {
    // The request is built before any connection is opened, so a host without CoreDevice fails
    // without touching the simulator.
    let request = try request(action: action, input: input)
    return try await session(for: service).read(request, decode: decode)
  }

  /// One action, one reply, with the output decoded into `Output`.
  func perform<Input: Encodable, Output: Decodable & Sendable>(
    action: String, service: String, input: Input, as type: Output.Type
  ) async throws -> Output {
    try await perform(action: action, service: service, input: input) { reply in
      try CoreDeviceReply.decode(type, from: reply)
    }
  }

  /// `perform`, for a feature the caller can do without: nil when the runtime, the CoreDevice
  /// installation or the toolchain cannot provide it at all.
  func performIfSupported<Input: Encodable, Response: Sendable>(
    action: String, service: String, input: Input,
    decode: @escaping @Sendable (xpc_object_t) throws -> Response
  ) async throws -> Response? {
    do {
      return try await perform(action: action, service: service, input: input, decode: decode)
    } catch SimulatorCoreDeviceError.unsupported {
      return nil
    }
  }

  /// One action whose provider pushes events; see `CoreDeviceSession.stream`.
  func stream<Input: Encodable, Response: Sendable>(
    action: String, service: String, input: Input,
    sample: @escaping @Sendable (xpc_object_t) throws -> Response?
  ) async throws -> Response {
    let request = try request(action: action, input: input)
    return try await session(for: service).stream(request, sample: sample)
  }

  // MARK: - Plain messages

  /// One message to a service that speaks its own envelope rather than the CoreDevice action
  /// envelope (the `dtuhidd`-style orientation and universal HID services), and its one reply.
  func send<Response: Sendable>(
    service: String, message: xpc_object_t,
    decode: @escaping @Sendable (xpc_object_t) throws -> Response
  ) async throws -> Response {
    try await session(for: service).read(message, decode: decode)
  }

  // MARK: - Plumbing

  private func request<Input: Encodable>(action: String, input: Input) throws -> xpc_object_t {
    try CoreDeviceRequest(action: action, deviceID: deviceID, version: version(), input: input).encoded()
  }

  private func session<Response: Sendable>(for service: String) throws -> CoreDeviceSession<Response> {
    CoreDeviceSession(transport: try makeTransport(service, queue), queue: queue)
  }
}
