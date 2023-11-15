/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionLib
import FBControlCore
import Foundation
import GRPC
import IDBGRPCSwift
import NIOCore
import NIOPosix
import NIOSSL

struct IDBUnixDomainSocketPathWrongType: Error {}

@objc
final class GRPCSwiftServer: NSObject {

  private struct TLSCertificates {
    let certificates: [NIOSSLCertificateSource]
    let privateKey: NIOSSLPrivateKeySource
  }

  private var server: EventLoopFuture<Server>?
  private let provider: CallHandlerProvider
  private let logger: FBIDBLogger

  private let serverConfig: Server.Configuration
  private let ports: IDBPortsConfiguration

  @objc
  let completed: FBMutableFuture<NSNull>

  @objc
  init(target: FBiOSTarget,
       commandExecutor: FBIDBCommandExecutor,
       reporter: FBEventReporter,
       logger: FBIDBLogger,
       ports: IDBPortsConfiguration) throws {

    let group = MultiThreadedEventLoopGroup(numberOfThreads: 4)
    let tlsCerts = Self.loadCertificates(tlsCertPath: ports.tlsCertPath, logger: logger)

    let interceptors = CompanionServiceInterceptors(logger: logger, reporter: reporter)

    self.provider = CompanionServiceProvider(target: target,
                                             commandExecutor: commandExecutor,
                                             reporter: reporter,
                                             logger: logger,
                                             interceptors: interceptors)

    var serverConfiguration = Server.Configuration.default(target: ports.swiftServerTarget.grpcConnection,
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

    self.completed = FBMutableFuture<NSNull>()
    self.logger = logger

    super.init()
  }

  @objc func start() -> FBMutableFuture<NSDictionary> {
    // Start the server and print its address once it has started.
    let future = FBMutableFuture<NSDictionary>()

    if case .unixDomainSocket(let path) = ports.swiftServerTarget {
      do {
        try cleanupUnixDomainSocket(path: path)
      } catch {
        self.logger.error().log("\(error)")
        future.resolveWithError(error)
        return future
      }
    }

    let server = Server.start(configuration: serverConfig)
    self.server = server

    logger.info().log("Starting swift server on \(ports.swiftServerTarget)")
    if let tlsPath = ports.tlsCertPath, !tlsPath.isEmpty {
      logger.info().log("Starting swift server with TLS path \(tlsPath)")
    }

    server.map(\.channel.localAddress).whenComplete { [weak self, ports] result in
      do {
        let address = try result.get()
        self?.logServerStartup(address: address)
        try future.resolve(withResult: ports.swiftServerTarget.outputDescription(for: address) as NSDictionary)
      } catch {
        self?.logger.error().log("\(error)")
        future.resolveWithError(error)
      }
    }

    server.flatMap(\.onClose).whenCompleteBlocking(onto: .main) { [completed] _ in
      self.logger.info().log("Server closed")
      completed.resolve(withResult: NSNull())
    }

    return future
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
