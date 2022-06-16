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
  private let ports: IDBPortsConfiguration

  @objc
  let completed : FBMutableFuture<NSNull>

  @objc
  init(target: FBiOSTarget,
       commandExecutor: FBIDBCommandExecutor,
       reporter: FBEventReporter,
       logger: FBIDBLogger,
       ports: IDBPortsConfiguration) throws {

    let group = MultiThreadedEventLoopGroup(numberOfThreads: 4)
    let tlsCerts = Self.loadCertificates(tlsCertPath: ports.tlsCertPath, logger: logger)

    let clientToCppServer = Self.internalCppClient(portConfiguration: ports, certificates: tlsCerts, group: group)
    let interceptors = CompanionServiceInterceptors(logger: logger, reporter: reporter, killswitch: IDBConfiguration.idbKillswitch)

    self.provider = CompanionServiceProvider(target: target,
                                             commandExecutor: commandExecutor,
                                             reporter: reporter,
                                             logger: logger,
                                             internalCppClient: clientToCppServer,
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

    let server = Server.start(configuration: serverConfig)
    self.server = server

    logger.info().log("Starting swift server on \(ports.swiftServerTarget)")
    if let tlsPath = ports.tlsCertPath, !tlsPath.isEmpty {
      logger.info().log("Starting swift server with TLS path \(tlsPath)")
    }

    server.map(\.channel.localAddress).whenSuccess { [weak self, ports] address in
      do {
        self?.logServerStartup(address: address)
        try future.resolve(withResult: ports.swiftServerTarget.outputDescription(for: address) as NSDictionary)
      } catch {
        future.resolveWithError(error)
      }
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

  private static func internalCppClient(portConfiguration: IDBPortsConfiguration, certificates: TLSCertificates?, group: MultiThreadedEventLoopGroup) -> Idb_CompanionServiceAsyncClientProtocol {
    var config = ClientConnection.Configuration.default(target: portConfiguration.cppServerTarget.grpcConnection, eventLoopGroup: group)

    if portConfiguration.cppServerTarget.supportsTLSCert {
      config.tlsConfiguration = certificates.map {
        var nioConf = TLSConfiguration.makeClientConfiguration()
        nioConf.certificateChain = $0.certificates
        nioConf.privateKey = $0.privateKey
        nioConf.certificateVerification = .none
        return GRPCTLSConfiguration.makeClientConfigurationBackedByNIOSSL(configuration:nioConf)
      }
    }

    // Potentially we could have very large files. To improve speed we removing max capacity
    // and set max frame size to maximum
    config.maximumReceiveMessageLength = Int.max
    config.httpMaxFrameSize = 16_777_215

    let connection = ClientConnection(configuration: config)

    return Idb_CompanionServiceAsyncClient(channel: connection)
  }

}
