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

  private struct TLSCertificates {
    let certificates: [NIOSSLCertificateSource]
    let privateKey: NIOSSLPrivateKeySource
  }

  private var server: EventLoopFuture<Server>?
  private let provider: CallHandlerProvider
  private let logger: FBIDBLogger

  private let serverConfig: Server.Configuration
  private let ports: FBIDBPortsConfiguration

  @objc
  let completed : FBMutableFuture<NSNull>

  @objc
  init(target: FBiOSTarget,
       commandExecutor: FBIDBCommandExecutor,
       reporter: FBEventReporter,
       logger: FBIDBLogger,
       ports: FBIDBPortsConfiguration) throws {

    let group = MultiThreadedEventLoopGroup(numberOfThreads: 4)
    let tlsCerts = Self.loadCertificates(portConfiguration: ports, logger: logger)

    let clientToCppServer = Self.internalCppClient(portConfiguration: ports, certificates: tlsCerts, group: group)
    let interceptors = CompanionServiceInterceptors()

    self.provider = CompanionServiceProvider(target: target,
                                             commandExecutor: commandExecutor,
                                             reporter: reporter,
                                             logger: logger,
                                             internalCppClient: clientToCppServer,
                                             interceptors: interceptors)

    var serverConfiguration = Server.Configuration.default(target: Self.bindTarget(portConfiguration: ports),
                                                           eventLoopGroup: group,
                                                           serviceProviders: [provider])

    serverConfiguration.tlsConfiguration = tlsCerts.map {
      GRPCTLSConfiguration.makeServerConfigurationBackedByNIOSSL(certificateChain: $0.certificates, privateKey: $0.privateKey)
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

    let server = Server.start(configuration: serverConfig)
    self.server = server

    logger.info().log("Starting swift server on port \(ports.grpcSwiftPort)")
    let tslPath = ports.tlsCertPath as String
    if !tslPath.isEmpty {
      logger.info().log("Starting swift server with TLS path \(ports.tlsCertPath)")
    }

    server.map(\.channel.localAddress).whenSuccess { [weak self, ports] address in
      self?.logServerStartup(address: address)
      future.resolve(withResult: ["grpc_swift_port": Int(ports.grpcSwiftPort)])
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

  private static func loadCertificates(portConfiguration: FBIDBPortsConfiguration, logger: FBIDBLogger) -> TLSCertificates? {
    let tlsPath = portConfiguration.tlsCertPath as String
    guard !tlsPath.isEmpty else { return nil }
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

    private static func internalCppClient(portConfiguration: FBIDBPortsConfiguration, certificates: TLSCertificates?, group: MultiThreadedEventLoopGroup) -> Idb_CompanionServiceAsyncClientProtocol {
        var config = ClientConnection.Configuration.default(target: .host("localhost", port: Int(portConfiguration.grpcPort)), eventLoopGroup: group)
        config.tlsConfiguration = certificates.map {
          var nioConf = TLSConfiguration.makeClientConfiguration()
          nioConf.certificateChain = $0.certificates
          nioConf.privateKey = $0.privateKey
          nioConf.certificateVerification = .none
          return GRPCTLSConfiguration.makeClientConfigurationBackedByNIOSSL(configuration:nioConf)
        }
        let connection = ClientConnection(configuration: config)

        return Idb_CompanionServiceAsyncClient(channel: connection)
    }

}
