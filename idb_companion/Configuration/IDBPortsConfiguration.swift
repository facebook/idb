/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@objc final class IDBPortsConfiguration: NSObject {

  private enum Key {
    static let debugPort = "-debug-port"
    static let grpcDomainSock = "-grpc-domain-sock"
    static let tlsCertPath = "-tls-cert-path"
    static let grpcPort = "-grpc-port"

    static let swiftPortEnv = "IDB_SWIFT_COMPANION_PORT"
  }

  /// The GRPC Unix Domain Socket Path
  let grpcDomainSocket: String?

  /// The GRPC TCP Port.
  let grpcPort: Int

  /// The GRPC TCP Port of swift server.
  @objc let grpcSwiftPort: Int

  /// The debugserver port
  @objc let debugserverPort: Int

  /// The TLS server cert path. If not specified grpcPort will be listening on unencrypted socket
  let tlsCertPath: String?

  /// Objc++ .mm files can not import swift bridged header and use swift objects. We need to keep legacy for compatibility
  @objc var legacyConfigurationObject: FBIDBPortsConfiguration {
    return .init(grpcDomainSocket: grpcDomainSocket,
                 grpcPort: UInt16(grpcPort),
                 debugserverPort: UInt16(debugserverPort),
                 tlsCertPath: tlsCertPath)
  }

  /// Construct a ports object.
  @objc init(arguments: UserDefaults) {
    self.debugserverPort = arguments.string(forKey: Key.debugPort).flatMap(Int.init) ?? 10881
    self.grpcPort = arguments.string(forKey: Key.grpcPort).flatMap(Int.init) ?? 10882
    self.grpcSwiftPort = ProcessInfo.processInfo.environment[Key.swiftPortEnv].flatMap(Int.init) ?? 0
    self.grpcDomainSocket = arguments.string(forKey: Key.grpcDomainSock)
    self.tlsCertPath = arguments.string(forKey: Key.tlsCertPath)
  }

}
