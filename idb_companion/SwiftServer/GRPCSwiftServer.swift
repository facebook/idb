/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import GRPC
import NIOCore
import NIOSSL
import NIOPosix
import FBControlCore
import IDBGRPCSwift

@objc
final class GRPCSwiftServer : NSObject {

  private var server: EventLoopFuture<Server>?
  private let provider: CallHandlerProvider
  private let logger: FBIDBLogger
  
  private let serverConfig: Server.Configuration

  @objc
  let completed : FBMutableFuture<NSNull>

  @objc
  init(target: FBiOSTarget, reporter: FBEventReporter, logger: FBIDBLogger, ports: FBIDBPortsConfiguration) throws {
    let group = MultiThreadedEventLoopGroup(numberOfThreads: 4)

    let config = ClientConnection.Configuration.default(target: .host("localhost", port: Int(ports.grpcPort)), eventLoopGroup: group)
    let connection = ClientConnection(configuration: config)

    let clientToCppServer = Idb_CompanionServiceAsyncClient(channel: connection)
    let interceptors = CompanionServiceInterceptors()

    self.provider = CompanionServiceProvider(target: target,
                                             reporter: reporter,
                                             logger: logger,
                                             internalCppClient: clientToCppServer,
                                             interceptors: interceptors)

    var serverConfiguration = Server.Configuration.default(target: Self.bindTarget(portConfiguration: ports),
                                                           eventLoopGroup: group,
                                                           serviceProviders: [provider])
    serverConfiguration.tlsConfiguration = Self.tlsConfiguration(portConfiguration: ports, logger: logger)
    serverConfiguration.errorDelegate = GRPCSwiftServerErrorDelegate()
    self.serverConfig = serverConfiguration
    
    self.completed = FBMutableFuture<NSNull>()
    self.logger = logger

    super.init()
  }

  @objc func start() -> FBMutableFuture<NSNull> {
    // Start the server and print its address once it has started.
    let future = FBMutableFuture<NSNull>()
    
    let server = Server.start(configuration: serverConfig)
    self.server = server
    
    logger.info().log("Starting swift server")
    server.map(\.channel.localAddress).whenSuccess { [weak self] address in
      self?.logServerStartup(address: address)
      future.resolve(withResult: NSNull())
    }
    
    server.flatMap(\.onClose).whenCompleteBlocking(onto: .main) { [completed] _ in
      completed.resolve(withResult: NSNull())
    }

    return future
  }

  private func logServerStartup(address: SocketAddress?) {
    let message = "Swift server started on "
    if let address = address {
      logger.info().log(message + address.description)
    } else {
      logger.error().log(message + " unknown address")
    }
  }

  private static func bindTarget(portConfiguration: FBIDBPortsConfiguration) -> BindTarget {
    return .host("localhost", port: Int(portConfiguration.grpcSwiftPort))
  }

  private static func tlsConfiguration(portConfiguration: FBIDBPortsConfiguration, logger: FBIDBLogger) -> GRPCTLSConfiguration? {
    let tlsPath = portConfiguration.tlsCertPath as String
    guard !tlsPath.isEmpty else { return nil }
    guard let tlsURL = URL(string: tlsPath) else {
      logger.error().log("Unable to parse tls-cert-path \(tlsPath)")
      fatalError("Unable to parse tls-cert-path \(tlsPath)")
    }
    do {
      let rawCert = try Data(contentsOf: tlsURL)

      let certificate = try NIOSSLCertificateSource.certificate(.init(bytes: [UInt8](rawCert), format: .pem))
      let privateKey = try NIOSSLPrivateKeySource.privateKey(.init(bytes: [UInt8](rawCert), format: .pem))

      return GRPCTLSConfiguration.makeServerConfigurationBackedByNIOSSL(certificateChain: [certificate], privateKey: privateKey)

    } catch {
      logger.error().log("Unable to create tls configuration. Error: \(error)")
      fatalError("Unable to create tls configuration. Error: \(error)")
    }

  }

}
