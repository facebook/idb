/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import GRPC
import NIO

enum GRPCConnectionTarget: CustomStringConvertible {
  enum ExtractionError: Error {
    case socketAddressIsEmpty
    case failedToExtractAssociatedInfo
  }

  case tcpPort(port: Int)
  case unixDomainSocket(String)

  var grpcConnection: ConnectionTarget {
    switch self {
    case let .tcpPort(port):
      return .hostAndPort("::", port)

    case let .unixDomainSocket(path):
      return .unixDomainSocket(path)
    }
  }

  func outputDescription(for socketAddress: SocketAddress?) throws -> [String: Any] {
    guard let socketAddress else {
      throw ExtractionError.socketAddressIsEmpty
    }
    switch self {
    case .tcpPort:
      guard let port = socketAddress.port else {
        throw ExtractionError.failedToExtractAssociatedInfo
      }
      return ["grpc_swift_port": port,
              "grpc_port": port]

    case .unixDomainSocket:
      guard let path = socketAddress.pathname else {
        throw ExtractionError.failedToExtractAssociatedInfo
      }
      return ["grpc_path": path]
    }
  }

  var description: String {
    switch self {
    case let .tcpPort(port):
      return "tcp port \(port)"
    case let .unixDomainSocket(path):
      return "unix socket \(path)"
    }
  }

  var supportsTLSCert: Bool {
    switch self {
    case .unixDomainSocket:
      return false
    case .tcpPort:
      return true
    }
  }
}

@objc final class IDBPortsConfiguration: NSObject {

  private enum Key {
    static let debugPort = "-debug-port"
    static let grpcDomainSock = "-grpc-domain-sock"
    static let tlsCertPath = "-tls-cert-path"
    static let grpcPort = "-grpc-port"
  }

  /// The GRPC Unix Domain Socket Path
  private let grpcDomainSocket: String?

  /// The GRPC TCP Port.
  private let grpcPort: Int

  /// The debugserver port
  @objc let debugserverPort: Int

  /// The TLS server cert path. If not specified grpcPort will be listening on unencrypted socket
  let tlsCertPath: String?

  var swiftServerTarget: GRPCConnectionTarget {
    if let grpcDomainSocket, !grpcDomainSocket.isEmpty {
      return .unixDomainSocket(grpcDomainSocket)
    } else {
      return .tcpPort(port: grpcPort)
    }
  }

  /// Construct a ports object.
  @objc init(arguments: UserDefaults) {
    self.debugserverPort = arguments.string(forKey: Key.debugPort).flatMap(Int.init) ?? 10881
    self.grpcPort = arguments.string(forKey: Key.grpcPort).flatMap(Int.init) ?? 10882
    self.grpcDomainSocket = arguments.string(forKey: Key.grpcDomainSock)
    self.tlsCertPath = arguments.string(forKey: Key.tlsCertPath)
  }
}
