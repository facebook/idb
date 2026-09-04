/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Darwin
@preconcurrency import FBControlCore
import Foundation

protocol FBAXBridgeTransport {
  func send(_ request: FBAXBridgeRequest) async throws -> Data
}

enum FBAXBridgeServiceScope: Sendable, Hashable {
  case shared
  case exclusive
}

/// Owns the lifecycle of a shared or exclusive socket-backed axbridge guest.
actor FBAXBridgePersistentTransport: FBAXBridgeTransport {
  private weak var simulator: FBSimulator?
  private let scope: FBAXBridgeServiceScope
  private var connectionTask: Task<FBAXBridgeConnection, Error>?

  init(simulator: FBSimulator, scope: FBAXBridgeServiceScope) {
    self.simulator = simulator
    self.scope = scope
  }

  func send(_ request: FBAXBridgeRequest) async throws -> Data {
    let requestData = try JSONSerialization.data(withJSONObject: request.payload)
    do {
      return try await roundTrip(requestData)
    } catch {
      guard request.mayRetry else {
        throw error
      }
      return try await roundTrip(requestData)
    }
  }

  private func roundTrip(_ requestData: Data) async throws -> Data {
    let connection = try await connection()
    do {
      let response = try await connection.roundTrip(requestData)
      releaseConnectionIfShared(connection)
      return response
    } catch {
      connectionTask = nil
      throw error
    }
  }

  private func releaseConnectionIfShared(_ connection: FBAXBridgeConnection) {
    if !connection.mayBeHeldBetweenRoundTrips {
      connectionTask = nil
    }
  }

  private func connection() async throws -> FBAXBridgeConnection {
    if let connectionTask {
      return try await connectionTask.value
    }
    let simulator = self.simulator
    let scope = self.scope
    let task = Task { try await Self.establish(simulator: simulator, scope: scope) }
    connectionTask = task
    do {
      return try await task.value
    } catch {
      connectionTask = nil
      throw error
    }
  }

  static let idleTimeoutSeconds = 300

  static func serveArguments(
    socketPath: String,
    scope: FBAXBridgeServiceScope,
    idleTimeoutSeconds: Int = idleTimeoutSeconds
  ) -> [String] {
    var arguments = ["accessibility", "serve", socketPath, "--idle-timeout", "\(idleTimeoutSeconds)"]
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
    simulator: FBSimulator?,
    scope: FBAXBridgeServiceScope
  ) async throws -> FBAXBridgeConnection {
    guard let simulator else {
      throw FBWeakTargetError.simulator
    }
    guard let helperPath = BundledResources.path(forItem: "SimulatorFrameworkBridge") else {
      throw FBAXBridgeError.bridgeUnavailable
    }
    try FBAXBridgeSocket.prepareDirectory()

    if scope == .exclusive {
      let privatePath = FBAXBridgeSocket.path(forConnection: UUID().uuidString)
      return try await spawn(
        simulator: simulator,
        helperPath: helperPath,
        socketPath: privatePath,
        scope: .exclusive,
        ownership: { .privateToThisHost($0) }
      )
    }

    let sharedPath = FBAXBridgeSocket.path(forSimulator: simulator.udid)
    switch await runningBridge(at: sharedPath) {
    case let .adopted(fileDescriptor):
      simulator.logger.log("Adopted the axbridge guest already serving on \(sharedPath)")
      return FBAXBridgeConnection(fileDescriptor: fileDescriptor, ownership: .shared(nil))
    case .absent:
      return try await spawn(
        simulator: simulator,
        helperPath: helperPath,
        socketPath: sharedPath,
        scope: .shared,
        ownership: { .shared($0) }
      )
    case .busy:
      let privatePath = FBAXBridgeSocket.path(forConnection: UUID().uuidString)
      simulator.logger.log(
        "The axbridge guest on \(sharedPath) is serving another client; starting a private one on \(privatePath)"
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
      fileDescriptor = try await FBAXBridgeConnection.connect(path: path, timeout: adoptionTimeout)
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
      let request = try JSONSerialization.data(withJSONObject: FBAXBridgeRequest.ping.payload)
      try FBAXBridgeConnection.writeFrame(fileDescriptor, request)
      _ = try FBAXBridgeConnection.readFrame(fileDescriptor, guest: nil)
    } catch {
      close(fileDescriptor)
      return .busy
    }
    var readTimeout = timeval(tv_sec: FBAXBridgeConnection.receiveTimeoutSeconds, tv_usec: 0)
    setsockopt(fileDescriptor, SOL_SOCKET, SO_RCVTIMEO, &readTimeout, socklen_t(MemoryLayout<timeval>.size))
    return .adopted(fileDescriptor)
  }

  private static func spawn(
    simulator: FBSimulator,
    helperPath: String,
    socketPath: String,
    scope: FBAXBridgeServiceScope,
    ownership: (FBSubprocess<AnyObject, AnyObject, AnyObject>) -> FBAXBridgeGuestOwnership
  ) async throws -> FBAXBridgeConnection {
    let io = FBProcessIO<AnyObject, AnyObject, AnyObject>.outputToDevNull()
    let configuration = FBProcessSpawnConfiguration(
      launchPath: helperPath,
      arguments: serveArguments(socketPath: socketPath, scope: scope),
      environment: [:],
      io: io,
      mode: .default
    )
    let process = try await simulator.launchProcess(configuration)
    do {
      let fileDescriptor = try await FBAXBridgeConnection.connect(path: socketPath, timeout: 10, guest: process)
      return FBAXBridgeConnection(fileDescriptor: fileDescriptor, ownership: ownership(process))
    } catch {
      simulator.logger.log(
        "Could not reach the axbridge guest just spawned on \(socketPath); leaving it to time out"
      )
      throw error
    }
  }
}
