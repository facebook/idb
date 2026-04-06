// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

@preconcurrency import FBControlCore
import Foundation

private let connectionReadSizeLimit: size_t = 1024

private class FBDeviceDebugServer_TwistedPairFiles: NSObject {
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
    super.init()
  }

  func start() -> FBFuture<NSNull>? {
    guard #available(macOS 10.15, *) else {
      return nil
    }

    let logger = self.logger
    let socket = self.socket
    let socketReadHandle = FileHandle(fileDescriptor: socket)
    nonisolated(unsafe) let connection = self.connection
    let socketReadCompleted = FBMutableFuture<NSNull>()
    let connectionReadCompleted = FBMutableFuture<NSNull>()

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
          if data.count == 0 {
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

    let socketFuture = unsafeBitCast(socketReadCompleted, to: FBFuture<NSNull>.self)
    let connectionFuture = unsafeBitCast(connectionReadCompleted, to: FBFuture<NSNull>.self)
    let raceFuture = FBFuture<NSNull>(race: [socketFuture, connectionFuture])
      .onQueue(
        connectionToSocketQueue,
        doOnResolved: { _ in
          logger.log("Closing socket file descriptor \(socket)")
          close(socket)
        }
      )
      .mapReplace(NSNull())
    return unsafeBitCast(raceFuture, to: FBFuture<NSNull>.self)
  }
}

@objc(FBDeviceDebugServer)
public class FBDeviceDebugServer: NSObject, FBSocketServerDelegate, FBDebugServer {
  private let serviceConnection: FBAMDServiceConnection
  private lazy var tcpServer: FBSocketServer = FBSocketServer(onPort: self.port, delegate: self)
  private let port: in_port_t
  private let logger: any FBControlCoreLogger
  private var teardown: FBMutableFuture<NSNull>?
  private var twistedPair: FBDeviceDebugServer_TwistedPairFiles?

  // MARK: - FBDebugServer

  @objc public let lldbBootstrapCommands: [String]

  // MARK: - FBSocketServerDelegate

  @objc public let queue: DispatchQueue

  // MARK: - Initializers

  /// Factory method: creates and starts a debug server from a future-wrapped service connection.
  @objc public static func debugServer(
    forServiceConnection service: FBFutureContext<FBAMDServiceConnection>,
    port: in_port_t,
    lldbBootstrapCommands: [String],
    queue: DispatchQueue,
    logger: (any FBControlCoreLogger)?
  ) -> FBFuture<AnyObject> {
    return service.onQueue(
      queue,
      push: { (serviceConnection: AnyObject) -> FBFutureContext<AnyObject> in
        let connection = serviceConnection as! FBAMDServiceConnection
        let server = FBDeviceDebugServer(
          serviceConnection: connection,
          port: port,
          lldbBootstrapCommands: lldbBootstrapCommands,
          queue: queue,
          logger: logger
        )
        return server.startListening() as! FBFutureContext<AnyObject>
      }
    ).onQueue(
      queue,
      enter: { (result: AnyObject, teardownFuture: FBMutableFuture<NSNull>) -> AnyObject in
        let server = result as! FBDeviceDebugServer
        server.teardown = teardownFuture
        return server
      })
  }

  init(
    serviceConnection: FBAMDServiceConnection,
    port: in_port_t,
    lldbBootstrapCommands: [String],
    queue: DispatchQueue,
    logger: (any FBControlCoreLogger)?
  ) {
    self.serviceConnection = serviceConnection
    self.port = port
    self.lldbBootstrapCommands = lldbBootstrapCommands
    self.queue = queue
    self.logger = logger ?? FBControlCoreGlobalConfiguration.defaultLogger
    super.init()
  }

  // MARK: - FBSocketServerDelegate

  @objc public func socketServer(
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
    let pair = FBDeviceDebugServer_TwistedPairFiles(
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
    teardown?.resolve(from: unsafeBitCast(completed, to: FBFuture<AnyObject>.self))
    self.twistedPair = pair
  }

  // MARK: - FBiOSTargetOperation

  @objc public var completed: FBFuture<NSNull> {
    if let teardown = teardown {
      return unsafeBitCast(teardown, to: FBFuture<NSNull>.self)
    }
    return unsafeBitCast(FBMutableFuture<NSNull>(), to: FBFuture<NSNull>.self)
  }

  // MARK: - Private Methods

  private func startListening() -> FBFutureContext<FBDeviceDebugServer> {
    return tcpServer.startListeningContext()
      .onQueue(
        queue,
        pend: { [self] (_: AnyObject) -> FBFuture<AnyObject> in
          self.logger.log("TCP Server now running, bootstrap commands for lldb are \(self.lldbBootstrapCommands.joined(separator: "\n"))")
          return FBFuture<AnyObject>(result: self)
        }) as! FBFutureContext<FBDeviceDebugServer>
  }
}
