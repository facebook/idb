/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import DTXConnectionServices
import Darwin
import FBControlCore
import Foundation

/// The DTX exported object for the remote-automation channel. The exported interface is empty — the
/// daemon never calls back — so this only needs to conform; it never receives a message. Holding it
/// apart from `FBRemoteAutomationConnection` keeps that type's stored state immutable.
private final class FBRemoteAutomationExportedClient: NSObject, XCTDRemoteAutomationClient {}

/// A thread-safe flag tracking whether the DTX connection has reported a disconnect. Held apart from
/// the connection so the disconnect handler can be constructed before the connection exists, without
/// a weak self-reference.
private final class FBRemoteAutomationDisconnectState {
  private let lock = NSLock()
  private var value = false

  var isDisconnected: Bool {
    lock.lock()
    defer { lock.unlock() }
    return value
  }

  func markDisconnected() {
    lock.lock()
    value = true
    lock.unlock()
  }
}

/// Raised while establishing the remote-automation socket, before the DTX connection is built.
private enum FBRemoteAutomationSocketError: Error, CustomStringConvertible {
  case failure(String)

  var description: String {
    switch self {
    case let .failure(message):
      return message
    }
  }
}

/// Owns a resumed DTX connection to the guest `testmanagerd` remote-automation channel.
///
/// The channel is unauthenticated and session-less on the simulator: this connects an AF_UNIX
/// socket, wraps it in Apple's DTX transport/connection, installs the one-shot return-value
/// allow-list before resuming, and vends the typed remote proxy. Everything above the wire — the
/// handshake, deadlines, cancellation, and typed wrappers — lives in
/// `DTXRemoteInvoker`/`FBRemoteAutomationSession`, which message the proxy directly and bridge each
/// `FBRemoteAutomationReceipt` to a continuation.
///
/// `DTXConnectionServices` is linked, so the DTX types are named and messaged directly. The
/// runtime-loaded `XCTest` payload classes are not — those are built and returned as opaque handles
/// by `FBRemoteAutomationRuntime`, keeping their unlinkable `_OBJC_CLASS_$_` symbols out of Swift.
public final class FBRemoteAutomationConnection {

  /// The typed remote-automation proxy. Messaging a `_XCTD_*` selector on it packages the call as a
  /// DTX invocation and returns a receipt whose `handleCompletion:` fires when the remote responds.
  public let remoteProxy: any XCTDRemoteAutomationServer

  private let logger: FBControlCoreLogger?
  private let connection: DTXConnection
  private let proxyChannel: DTXProxyChannel
  private let exportedClient: FBRemoteAutomationExportedClient
  private let disconnectState: FBRemoteAutomationDisconnectState

  /// `true` once the underlying DTX connection has reported a disconnect.
  public var disconnected: Bool {
    disconnectState.isDisconnected
  }

  /// Connects to a remote-automation socket, wraps it in DTX, installs the allow-list, and resumes.
  ///
  /// - Parameters:
  ///   - socketPath: the path to the AF_UNIX socket vended by the guest daemon.
  ///   - queue: the queue used for DTX callbacks and the exported object.
  ///   - logger: an optional logger.
  /// - Throws: if the socket cannot be reached or the runtime DTX classes are unavailable.
  public init(socketPath: String, queue: DispatchQueue, logger: FBControlCoreLogger?) throws {
    let disconnectState = FBRemoteAutomationDisconnectState()
    let socketHandle = try Self.connectSocket(toPath: socketPath, logger: logger)
    let connection = try FBRemoteAutomationRuntime.connection(
      forSocketHandle: socketHandle,
      transportDisconnect: {
        logger?.log("remote-automation DTX transport reported socket disconnect")
      },
      connectionDisconnect: {
        logger?.log("remote-automation DTX connection disconnected")
        disconnectState.markDisconnected()
      }
    )
    let exportedClient = FBRemoteAutomationExportedClient()
    let proxyChannel = try FBRemoteAutomationRuntime.proxyChannel(
      for: connection,
      exportedObject: exportedClient,
      queue: queue
    )

    self.logger = logger
    self.disconnectState = disconnectState
    self.connection = connection
    self.proxyChannel = proxyChannel
    self.exportedClient = exportedClient
    self.remoteProxy = FBRemoteAutomationRuntime.remoteProxy(for: proxyChannel)

    logger?.log("Resuming remote-automation DTX connection")
    connection.resume()
  }

  /// Suspends and cancels the underlying DTX connection. Idempotent.
  public func teardown() {
    logger?.log("Ending remote-automation DTX connection")
    connection.suspend()
    connection.cancel()
  }

  private static func connectSocket(toPath path: String, logger: FBControlCoreLogger?) throws -> Int32 {
    guard FileManager.default.fileExists(atPath: path) else {
      throw FBRemoteAutomationSocketError.failure("Remote-automation socket does not exist at \(path)")
    }
    let socketHandle = socket(AF_UNIX, SOCK_STREAM, 0)
    guard socketHandle >= 0 else {
      throw FBRemoteAutomationSocketError.failure("Failed to create socket for \(path): \(String(cString: strerror(errno)))")
    }
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let pathCapacity = MemoryLayout.size(ofValue: address.sun_path)
    withUnsafeMutablePointer(to: &address.sun_path) { sunPath in
      sunPath.withMemoryRebound(to: CChar.self, capacity: pathCapacity) { destination in
        _ = strncpy(destination, path, pathCapacity - 1)
      }
    }
    let connected = withUnsafePointer(to: &address) { addressPointer in
      addressPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
        connect(socketHandle, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
    guard connected == 0 else {
      let message = "Failed to connect to remote-automation socket \(path): \(String(cString: strerror(errno)))"
      close(socketHandle)
      throw FBRemoteAutomationSocketError.failure(message)
    }
    logger?.log("Connected to remote-automation socket \(path) (fd \(socketHandle))")
    return socketHandle
  }
}
