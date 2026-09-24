/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Darwin
@preconcurrency import FBControlCore
import Foundation
import SimulatorFrameworkBridgeProtocol

protocol AXBridgeTransport {
  func send(_ request: AXBridgeRequest) async throws -> Data
}

enum BridgeServiceScope: Sendable, Hashable {
  case shared
  case exclusive
}

protocol BridgeConnection: Sendable {
  var mayBeHeldBetweenRoundTrips: Bool { get }
  func roundTrip(_ requestData: Data) async throws -> Data
}

/// Owns the lifecycle of a shared or exclusive SimulatorFrameworkBridge guest.
actor SimulatorFrameworkBridgePersistentTransport: AXBridgeTransport {
  private let establishConnection: @Sendable () async throws -> any BridgeConnection
  private var connectionTask: Task<any BridgeConnection, Error>?
  private var connectionGeneration = UUID()

  init(simulator: Simulator, scope: BridgeServiceScope) {
    establishConnection = { [weak simulator] in try await Self.establish(simulator: simulator, scope: scope) }
  }

  init(establish: @escaping @Sendable () async throws -> any BridgeConnection) {
    establishConnection = establish
  }

  func send(_ request: AXBridgeRequest) async throws -> Data {
    try await send(BridgeRequest(command: request.command)).accessibilityData()
  }

  func send(_ request: BridgeRequest) async throws -> BridgeResult {
    do {
      return try await roundTrip(request)
    } catch {
      guard request.command.mayRetry else { throw error }
      return try await roundTrip(request)
    }
  }

  private func roundTrip(_ request: BridgeRequest) async throws -> BridgeResult {
    let lease = try await connection()
    do {
      let response = try BridgeResponse.decode(await lease.connection.roundTrip(request.encoded()), for: request)
      if request.command == .shutdown || !lease.connection.mayBeHeldBetweenRoundTrips { invalidate(lease.generation) }
      return response.result
    } catch {
      invalidate(lease.generation)
      throw error
    }
  }

  private func invalidate(_ generation: UUID) {
    if connectionGeneration == generation { connectionTask = nil }
  }

  private func connection() async throws -> (generation: UUID, connection: any BridgeConnection) {
    if let connectionTask {
      let generation = connectionGeneration
      return (generation, try await connectionTask.value)
    }
    let generation = UUID()
    connectionGeneration = generation
    let establish = establishConnection
    let task = Task { try await establish() }
    connectionTask = task
    do {
      return (generation, try await task.value)
    } catch {
      invalidate(generation)
      throw error
    }
  }

  static let idleTimeoutSeconds = 300

  static func serveArguments(
    socketPath: String,
    scope: BridgeServiceScope,
    idleTimeoutSeconds: Int = idleTimeoutSeconds
  ) -> [String] {
    var arguments = ["serve", socketPath, "--idle-timeout", "\(idleTimeoutSeconds)"]
    if scope == .exclusive {
      arguments += ["--exit-on-disconnect", "1"]
    }
    return arguments
  }

  static let adoptionTimeout: TimeInterval = 0.25

  private enum RunningBridge {
    case adopted(Int32)
    case absent
    case busy
  }

  private static func establish(
    simulator: Simulator?,
    scope: BridgeServiceScope
  ) async throws -> SimulatorFrameworkBridgeConnection {
    guard let simulator else {
      throw WeakTargetError.simulator
    }
    guard let helperPath = simulator.frameworkBridgePath else {
      throw AXBridgeError.bridgeUnavailable
    }
    try SimulatorFrameworkBridgeSocket.prepareDirectory()

    if scope == .exclusive {
      let privatePath = SimulatorFrameworkBridgeSocket.path(forConnection: UUID().uuidString)
      return try await spawn(
        simulator: simulator,
        helperPath: helperPath,
        socketPath: privatePath,
        scope: .exclusive,
        ownership: { .privateToThisHost($0) }
      )
    }

    let sharedPath = SimulatorFrameworkBridgeSocket.path(forSimulator: simulator.udid)
    switch await runningBridge(at: sharedPath) {
    case let .adopted(fileDescriptor):
      simulator.logger.log("Adopted the SimulatorFrameworkBridge guest already serving on \(sharedPath)")
      return SimulatorFrameworkBridgeConnection(fileDescriptor: fileDescriptor, ownership: .shared(nil))
    case .absent:
      return try await spawn(
        simulator: simulator,
        helperPath: helperPath,
        socketPath: sharedPath,
        scope: .shared,
        ownership: { .shared($0) }
      )
    case .busy:
      let privatePath = SimulatorFrameworkBridgeSocket.path(forConnection: UUID().uuidString)
      simulator.logger.log(
        "The SimulatorFrameworkBridge guest on \(sharedPath) is serving another client; starting a private one on \(privatePath)"
      )
      return try await spawn(
        simulator: simulator,
        helperPath: helperPath,
        socketPath: privatePath,
        scope: .exclusive,
        ownership: { .privateToThisHost($0) }
      )
    }
  }

  private static func runningBridge(at path: String) async -> RunningBridge {
    guard FileManager.default.fileExists(atPath: path) else {
      return .absent
    }
    let fileDescriptor: Int32
    do {
      fileDescriptor = try await SimulatorFrameworkBridgeConnection.connect(path: path, timeout: adoptionTimeout)
    } catch {
      return .absent
    }
    return await withCheckedContinuation { continuation in
      DispatchQueue.global().async {
        continuation.resume(returning: probe(fileDescriptor: fileDescriptor))
      }
    }
  }

  /// Converts a deadline without rounding a positive sub-second value down to an all-zero `timeval`,
  /// which the kernel interprets as no deadline.
  static func receiveWindow(_ timeout: TimeInterval) -> timeval {
    let whole = timeout.rounded(.down)
    return timeval(tv_sec: Int(whole), tv_usec: Int32((timeout - whole) * 1_000_000))
  }

  private static func probe(fileDescriptor: Int32) -> RunningBridge {
    // A successful connect only means the listen backlog accepted us. The guest serves one connection
    // at a time, so a round trip is the only way to distinguish an adoptable guest from a busy one.
    var window = receiveWindow(adoptionTimeout)
    setsockopt(fileDescriptor, SOL_SOCKET, SO_RCVTIMEO, &window, socklen_t(MemoryLayout<timeval>.size))
    do {
      let request = BridgeRequest(command: .ping)
      try SimulatorFrameworkBridgeConnection.writeFrame(fileDescriptor, request.encoded())
      let response = try BridgeResponse.decode(SimulatorFrameworkBridgeConnection.readFrame(fileDescriptor, guest: nil), for: request)
      guard response.result.exitCode == 0 else { throw AXBridgeError.guestFailure("bridge handshake failed") }
    } catch {
      close(fileDescriptor)
      return .busy
    }
    var readTimeout = timeval(tv_sec: SimulatorFrameworkBridgeConnection.receiveTimeoutSeconds, tv_usec: 0)
    setsockopt(fileDescriptor, SOL_SOCKET, SO_RCVTIMEO, &readTimeout, socklen_t(MemoryLayout<timeval>.size))
    return .adopted(fileDescriptor)
  }

  private static func spawn(
    simulator: Simulator,
    helperPath: String,
    socketPath: String,
    scope: BridgeServiceScope,
    ownership: (FBSubprocess<AnyObject, AnyObject, AnyObject>) -> BridgeGuestOwnership
  ) async throws -> SimulatorFrameworkBridgeConnection {
    let io = FBProcessIO<AnyObject, AnyObject, AnyObject>.outputToDevNull()
    let configuration = ProcessSpawnConfiguration(
      launchPath: helperPath,
      arguments: serveArguments(socketPath: socketPath, scope: scope),
      environment: [:],
      io: io,
      mode: .default
    )
    let process = try await simulator.spawn(configuration)
    do {
      let fileDescriptor = try await SimulatorFrameworkBridgeConnection.connect(path: socketPath, timeout: 10, guest: process, scope: scope)
      return SimulatorFrameworkBridgeConnection(fileDescriptor: fileDescriptor, ownership: ownership(process))
    } catch {
      simulator.logger.log("Could not reach the SimulatorFrameworkBridge guest just spawned on \(socketPath): \(error)")
      throw error
    }
  }
}
