/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionLib
import CompanionUtilities
import FBControlCore
import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2Posix
import IDBGRPCSwift
import NIOCore
import NIOPosix

struct IDBUnixDomainSocketPathWrongType: Error {}

final class GRPCSwiftServer: @unchecked Sendable {

  private let server: GRPCServer<HTTP2ServerTransport.Posix>
  private let transport: HTTP2ServerTransport.Posix
  private let logger: IDBLogger
  private let ports: IDBPortsConfiguration

  /// How long graceful shutdown is given to drain in-flight RPCs before the server is
  /// closed forcefully. Bounds shutdown so a stuck long-lived RPC (e.g. a log or video
  /// stream) cannot keep the companion alive after a termination signal.
  private static let gracefulShutdownTimeout: Duration = .seconds(5)

  /// The maximum request payload the companion accepts. Installs and pushes stream large
  /// chunks, so this is well above the transport's 4 MiB default.
  private static let maximumReceiveMessageLength = 16_777_216

  private let shutdownLock = NSLock()
  private var didInitiateShutdown = false
  /// The task running `serve()`; cancelling it is the forceful close.
  private var serveTask: Task<Void, any Error>?

  /// Invoked synchronously the instant shutdown begins, before the async drain — used to
  /// release externally-visible registration (e.g. unlink the gRPC socket) so no client
  /// can discover this companion during the graceful-shutdown window that follows.
  private let onShutdownStarted: (@Sendable () -> Void)?

  init(
    target: any FBiOSTarget,
    commandExecutor: IDBCommandExecutor,
    reporter: EventReporter,
    logger: IDBLogger,
    ports: IDBPortsConfiguration,
    idleMonitor: IdleMonitor?,
    onShutdownStarted: (@Sendable () -> Void)? = nil
  ) throws {
    let group = MultiThreadedEventLoopGroup(numberOfThreads: 4)

    let provider = CompanionServiceProvider(
      target: target,
      commandExecutor: commandExecutor,
      reporter: reporter,
      logger: logger,
      idleMonitor: idleMonitor)

    let transportSecurity: HTTP2ServerTransport.Posix.TransportSecurity
    if ports.swiftServerTarget.supportsTLSCert, let pem = Self.loadCertificatePEM(tlsCertPath: ports.tlsCertPath, logger: logger) {
      transportSecurity = .tls(certificateChain: [.bytes(pem, format: .pem)], privateKey: .bytes(pem, format: .pem))
    } else {
      transportSecurity = .plaintext
    }

    let transport = HTTP2ServerTransport.Posix(
      address: ports.swiftServerTarget.socketAddress,
      transportSecurity: transportSecurity,
      config: .defaults { config in
        config.rpc.maxRequestPayloadSize = Self.maximumReceiveMessageLength
      },
      eventLoopGroup: group)

    self.transport = transport
    self.server = GRPCServer(
      transport: transport,
      services: [provider],
      interceptors: CompanionServiceInterceptors.make(logger: logger))
    self.ports = ports
    self.logger = logger
    self.onShutdownStarted = onShutdownStarted
  }

  func start() async throws -> [String: Any] {
    if case .unixDomainSocket(let path) = ports.swiftServerTarget {
      try cleanupUnixDomainSocket(path: path)
    }

    logger.info().log("Starting swift server on \(ports.swiftServerTarget)")
    if let tlsPath = ports.tlsCertPath, !tlsPath.isEmpty {
      logger.info().log("Starting swift server with TLS path \(tlsPath)")
    }

    let server = self.server
    self.serveTask = Task {
      try await server.serve()
    }

    let address = try await transport.listeningAddress
    logServerStartup(address: address)
    return try ports.swiftServerTarget.outputDescription(for: address)
  }

  /// Suspends until the server has stopped serving. If the awaiting task is cancelled
  /// (e.g. on SIGTERM), a graceful shutdown is initiated so `serve()` returns and this
  /// returns: nothing else stops the server, so without this a cancelled wait would hang forever.
  func waitUntilClosed() async throws {
    guard let serveTask else { return }
    try await withTaskCancellationHandler {
      try await serveTask.value
      logger.info().log("Server closed")
    } onCancel: {
      initiateShutdown()
    }
  }

  /// Begins shutting the server down so a pending ``waitUntilClosed()`` returns.
  /// In-flight RPCs are given ``gracefulShutdownTimeout`` to complete while new RPCs and
  /// connections are rejected; if they do not finish in time the server is closed
  /// forcefully. Non-blocking and idempotent.
  func initiateShutdown() {
    shutdownLock.lock()
    let alreadyInitiated = didInitiateShutdown
    didInitiateShutdown = true
    shutdownLock.unlock()
    guard !alreadyInitiated else { return }

    onShutdownStarted?()

    guard let serveTask else { return }
    logger.info().log("Shutting down swift server")
    server.beginGracefulShutdown()
    let logger = self.logger
    Task {
      try? await Task.sleep(for: Self.gracefulShutdownTimeout)
      guard !serveTask.isCancelled else { return }
      logger.info().log("Graceful shutdown timed out; closing swift server forcefully")
      serveTask.cancel()
    }
  }

  private func cleanupUnixDomainSocket(path: String) throws {
    do {
      self.logger.info().log("Cleaning up UDS if exists")
      var sb: stat = stat()
      try withUnsafeMutablePointer(to: &sb) { sbPtr in
        try syscall {
          stat(path, sbPtr)
        }
      }

      if sb.st_mode & S_IFSOCK == S_IFSOCK {
        self.logger.info().log("Existed UDS socket found, unlinking")
        try syscall {
          unlink(path)
        }
        self.logger.info().log("UDS socket cleaned up")
      } else {
        throw IDBUnixDomainSocketPathWrongType()
      }
    } catch let err as IOError {
      // If the filepath did not exist, we consider it cleaned up
      if err.errnoCode == ENOENT {
        return
      }
      throw err
    }
  }

  private func syscall(function: String = #function, _ body: () throws -> Int32) throws {
    while true {
      let res = try body()
      if res == -1 {
        let err = errno
        switch err {
        case EINTR:
          continue
        default:
          throw IOError(errnoCode: err, reason: function)
        }
      }
      return
    }
  }

  private func logServerStartup(address: GRPCNIOTransportCore.SocketAddress) {
    logger.info().log("Swift server started on \(address)")
  }

  private static func loadCertificatePEM(tlsCertPath: String?, logger: IDBLogger) -> [UInt8]? {
    guard let tlsPath = tlsCertPath,
      !tlsPath.isEmpty
    else { return nil }

    let tlsURL = URL(fileURLWithPath: tlsPath)
    do {
      return [UInt8](try Data(contentsOf: tlsURL))
    } catch {
      logger.error().log("Unable to load tls certificate. Error: \(error)")
      fatalError("Unable to load tls certificate. Error: \(error)")
    }
  }
}
