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
@preconcurrency import GRPC
import IDBGRPCSwift
import NIOCore
import NIOPosix
import NIOSSL

struct IDBUnixDomainSocketPathWrongType: Error {}

@objc
final class GRPCSwiftServer: NSObject, @unchecked Sendable {

  private struct TLSCertificates {
    let certificates: [NIOSSLCertificateSource]
    let privateKey: NIOSSLPrivateKeySource
  }

  private var server: EventLoopFuture<Server>?
  private let provider: CallHandlerProvider
  private let logger: FBIDBLogger

  private let serverConfig: Server.Configuration
  private let ports: IDBPortsConfiguration

  /// How long graceful shutdown is given to drain in-flight RPCs before the server is
  /// closed forcefully. Bounds shutdown so a stuck long-lived RPC (e.g. a log or video
  /// stream) cannot keep the companion alive after a termination signal.
  private static let gracefulShutdownTimeout: TimeAmount = .seconds(5)

  private let shutdownLock = NSLock()
  private var didInitiateShutdown = false

  /// Invoked synchronously the instant shutdown begins, before the async drain — used to
  /// release externally-visible registration (e.g. unlink the gRPC socket) so no client
  /// can discover this companion during the graceful-shutdown window that follows.
  private let onShutdownStarted: (@Sendable () -> Void)?

  init(
    target: FBiOSTarget,
    commandExecutor: FBIDBCommandExecutor,
    reporter: FBEventReporter,
    logger: FBIDBLogger,
    ports: IDBPortsConfiguration,
    idleMonitor: IdleMonitor?,
    onShutdownStarted: (@Sendable () -> Void)? = nil
  ) throws {

    let group = MultiThreadedEventLoopGroup(numberOfThreads: 4)
    let tlsCerts = Self.loadCertificates(tlsCertPath: ports.tlsCertPath, logger: logger)

    let interceptors = CompanionServiceInterceptors(logger: logger)

    self.provider = CompanionServiceProvider(
      target: target,
      commandExecutor: commandExecutor,
      reporter: reporter,
      logger: logger,
      interceptors: interceptors,
      idleMonitor: idleMonitor)

    var serverConfiguration = Server.Configuration.default(
      target: ports.swiftServerTarget.grpcConnection,
      eventLoopGroup: group,
      serviceProviders: [provider])
    serverConfiguration.maximumReceiveMessageLength = 16777216

    if ports.swiftServerTarget.supportsTLSCert {
      serverConfiguration.tlsConfiguration = tlsCerts.map {
        GRPCTLSConfiguration.makeServerConfigurationBackedByNIOSSL(certificateChain: $0.certificates, privateKey: $0.privateKey)
      }
    }

    serverConfiguration.errorDelegate = GRPCSwiftServerErrorDelegate()
    self.serverConfig = serverConfiguration
    self.ports = ports

    self.logger = logger
    self.onShutdownStarted = onShutdownStarted

    super.init()
  }

  func start() async throws -> [String: Any] {
    if case .unixDomainSocket(let path) = ports.swiftServerTarget {
      try cleanupUnixDomainSocket(path: path)
    }

    let server = Server.start(configuration: serverConfig)
    self.server = server

    logger.info().log("Starting swift server on \(ports.swiftServerTarget)")
    if let tlsPath = ports.tlsCertPath, !tlsPath.isEmpty {
      logger.info().log("Starting swift server with TLS path \(tlsPath)")
    }

    let runningServer = try await server.get()
    let address = runningServer.channel.localAddress
    logServerStartup(address: address)
    return try ports.swiftServerTarget.outputDescription(for: address)
  }

  /// Suspends until the server's channel closes. If the awaiting task is cancelled
  /// (e.g. on SIGTERM), a graceful shutdown is initiated so the channel closes and this
  /// returns: NIO's `EventLoopFuture.get()` does not observe task cancellation and
  /// nothing else closes the server, so without this a cancelled wait would hang forever.
  func waitUntilClosed() async throws {
    guard let server = self.server else { return }
    try await withTaskCancellationHandler {
      try await server.flatMap(\.onClose).get()
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

    // Release externally-visible registration the instant shutdown begins, so no client can
    // discover this companion during the graceful-shutdown drain that follows.
    onShutdownStarted?()

    guard let server = self.server else { return }
    logger.info().log("Shutting down swift server")
    server.whenSuccess { [logger] server in
      let forceClose = server.channel.eventLoop.scheduleTask(in: Self.gracefulShutdownTimeout) {
        logger.info().log("Graceful shutdown timed out; closing swift server forcefully")
        server.close(promise: nil)
      }
      server.onClose.whenComplete { _ in forceClose.cancel() }
      server.initiateGracefulShutdown(promise: nil)
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

      // Only unlink the existing file if it is a socket
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

  private func logServerStartup(address: SocketAddress?) {
    let message = "Swift server started on "
    if let address {
      logger.info().log(message + address.description)
    } else {
      logger.error().log(message + " unknown address")
    }
  }

  private static func loadCertificates(tlsCertPath: String?, logger: FBIDBLogger) -> TLSCertificates? {
    guard let tlsPath = tlsCertPath,
      !tlsPath.isEmpty
    else { return nil }

    let tlsURL = URL(fileURLWithPath: tlsPath)
    do {
      let rawCert = try Data(contentsOf: tlsURL)

      let certificate = try NIOSSLCertificateSource.certificate(.init(bytes: [UInt8](rawCert), format: .pem))
      let privateKey = try NIOSSLPrivateKeySource.privateKey(.init(bytes: [UInt8](rawCert), format: .pem))

      return TLSCertificates(
        certificates: [certificate],
        privateKey: privateKey
      )
    } catch {
      logger.error().log("Unable to load tls certificate. Error: \(error)")
      fatalError("Unable to load tls certificate. Error: \(error)")
    }
  }
}
