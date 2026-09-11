/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency import FBControlCore
import Foundation

private let connectionReadSizeLimit: size_t = 1024

private class DeviceDebugServer_TwistedPairFiles {
  let socket: Int32
  let connection: FBAMDServiceConnection
  let logger: any FBControlCoreLogger
  let socketToConnectionQueue: DispatchQueue
  let connectionToSocketQueue: DispatchQueue

  init(
    socket: Int32,
    connection: FBAMDServiceConnection,
    logger: any FBControlCoreLogger
  ) {
    self.socket = socket
    self.connection = connection
    self.logger = logger
    self.socketToConnectionQueue = DispatchQueue(label: "com.facebook.fbdevicecontrol.debugserver.socket_to_connection")
    self.connectionToSocketQueue = DispatchQueue(label: "com.facebook.fbdevicecontrol.debugserver.connection_to_socket")
  }

  func start() -> FBFuture<NSNull>? {
    // FBMutableFuture is a thread-safe ObjC type that isn't Sendable.
    let logger = self.logger
    let socket = self.socket
    let socketReadHandle = FileHandle(fileDescriptor: socket)
    nonisolated(unsafe) let connection = self.connection
    nonisolated(unsafe) let socketReadCompleted = FBMutableFuture<NSNull>()
    nonisolated(unsafe) let connectionReadCompleted = FBMutableFuture<NSNull>()

    socketToConnectionQueue.async {
      while socketReadCompleted.state == .running && connectionReadCompleted.state == .running {
        let data = socketReadHandle.availableData
        if data.isEmpty {
          logger.log("Socket read reached end of file")
          break
        }
        do {
          try connection.send(data as Data)
        } catch {
          logger.log("Sending data to remote debugserver failed: \(error)")
          break
        }
      }
      logger.log("Exiting socket \(socket) read loop")
      socketReadCompleted.resolve(withResult: NSNull())
    }

    connectionToSocketQueue.async {
      while socketReadCompleted.state == .running && connectionReadCompleted.state == .running {
        do {
          let data = try connection.receiveUp(to: connectionReadSizeLimit)
          if data.isEmpty {
            logger.log("debugserver read ended")
            break
          }
          data.withUnsafeBytes { bufferPointer in
            guard let baseAddress = bufferPointer.baseAddress else { return }
            var totalWritten = 0
            while totalWritten < data.count {
              let written = Darwin.write(socket, baseAddress.advanced(by: totalWritten), data.count - totalWritten)
              if written <= 0 {
                logger.log("Socket write failed")
                return
              }
              totalWritten += written
            }
          }
        } catch {
          logger.log("debugserver read ended: \(error)")
          break
        }
      }
      logger.log("Exiting connection \(connection) read loop")
      connectionReadCompleted.resolve(withResult: NSNull())
    }

    let combinedFuture = FBFuture<AnyObject>.combine([
      socketReadCompleted,
      connectionReadCompleted,
    ])
    .onQueue(
      connectionToSocketQueue,
      doOnResolved: { _ in
        logger.log("Closing socket file descriptor \(socket)")
        close(socket)
      }
    )
    return combinedFuture.retyped(FBFuture<NSNull>.self)
  }
}

public final class DeviceDebugServer: NSObject, FBSocketServerDelegate, DebugServer {
  private let serviceConnection: FBAMDServiceConnection
  private lazy var tcpServer: FBSocketServer = FBSocketServer(onPort: self.port, delegate: self)
  private let port: in_port_t
  private let logger: any FBControlCoreLogger
  private let teardown: FBMutableFuture<NSNull>
  private var twistedPair: DeviceDebugServer_TwistedPairFiles?

  public let lldbBootstrapCommands: [String]

  public let queue: DispatchQueue

  // MARK: - Initializers

  /// Starts a debug server that proxies `serviceConnection` to whichever client connects on `port`.
  ///
  /// The server owns the connection: it is held open across the separate requests that start,
  /// query and stop the server, and handed back to `FBAMDevice.invalidateServiceConnection` when
  /// the server is cancelled or its client disconnects. A server that fails to start hands the
  /// connection back before throwing.
  public static func debugServer(
    forServiceConnection serviceConnection: FBAMDServiceConnection,
    port: in_port_t,
    lldbBootstrapCommands: [String],
    queue: DispatchQueue,
    logger: any FBControlCoreLogger
  ) async throws -> DeviceDebugServer {
    let server = DeviceDebugServer(
      serviceConnection: serviceConnection,
      port: port,
      lldbBootstrapCommands: lldbBootstrapCommands,
      queue: queue,
      logger: logger
    )
    do {
      try await server.startListening()
    } catch {
      FBAMDevice.invalidateServiceConnection(serviceConnection, service: serviceConnection.name, logger: logger)
      throw error
    }
    return server
  }

  init(
    serviceConnection: FBAMDServiceConnection,
    port: in_port_t,
    lldbBootstrapCommands: [String],
    queue: DispatchQueue,
    logger: any FBControlCoreLogger
  ) {
    self.serviceConnection = serviceConnection
    self.port = port
    self.lldbBootstrapCommands = lldbBootstrapCommands
    self.queue = queue
    self.logger = logger
    self.teardown = FBMutableFuture<NSNull>(name: "Debug server for \(serviceConnection.name)")
    super.init()
  }

  // MARK: - FBSocketServerDelegate

  public func socketServer(
    _ server: FBSocketServer,
    clientConnected address: in6_addr,
    fileDescriptor: Int32
  ) {
    if twistedPair != nil {
      logger.log("Rejecting connection, we have an existing pair")
      if let data = "$NEUnspecified#00".data(using: .ascii) {
        data.withUnsafeBytes { bufferPointer in
          guard let baseAddress = bufferPointer.baseAddress else { return }
          _ = Darwin.write(fileDescriptor, baseAddress, data.count)
        }
      }
      close(fileDescriptor)
      return
    }
    logger.log("Client connected, connecting all file handles")
    let pair = DeviceDebugServer_TwistedPairFiles(
      socket: fileDescriptor,
      connection: serviceConnection,
      logger: logger
    )
    guard let completed = pair.start() else {
      logger.log("Failed to start connection")
      return
    }
    completed.onQueue(
      queue,
      doOnResolved: { [weak self] _ in
        self?.logger.log("Client Disconnected")
        self?.twistedPair = nil
      })
    teardown.resolve(from: completed.retyped(FBFuture<AnyObject>.self))
    self.twistedPair = pair
  }

  // MARK: - DebugServer

  public func cancel() async throws {
    try await bridgeFBFutureVoid(self.completed.cancel())
  }

  private var completed: FBFuture<NSNull> {
    convertFBMutableFuture(teardown)
  }

  private func startListening() async throws {
    try await bridgeFBFutureVoid(tcpServer.startListening())
    logger.log("TCP Server now running, bootstrap commands for lldb are \(lldbBootstrapCommands.joined(separator: "\n"))")
    let tcpServer = self.tcpServer
    let connection = serviceConnection
    let logger = self.logger
    // Both endings arrive on the same future: the client disconnecting resolves it, `cancel()`
    // cancels it, and only one of the two can win.
    teardown.onQueue(
      queue,
      respondToCancellation: {
        Self.stop(tcpServer: tcpServer, connection: connection, logger: logger)
        return FBFuture<NSNull>.empty()
      })
    teardown.onQueue(
      queue,
      doOnResolved: { _ in
        Self.stop(tcpServer: tcpServer, connection: connection, logger: logger)
      })
  }

  /// Innermost first: the socket a client would reach the connection through goes before the
  /// connection itself.
  private static func stop(
    tcpServer: FBSocketServer,
    connection: FBAMDServiceConnection,
    logger: any FBControlCoreLogger
  ) {
    tcpServer.stopListening()
    FBAMDevice.invalidateServiceConnection(connection, service: connection.name, logger: logger)
  }
}
