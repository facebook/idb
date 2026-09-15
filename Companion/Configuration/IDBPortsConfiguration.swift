/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import GRPCNIOTransportCore

enum GRPCConnectionTarget: CustomStringConvertible {
  enum ExtractionError: Error {
    case failedToExtractAssociatedInfo
  }

  case tcpPort(port: Int)
  case unixDomainSocket(String)

  var socketAddress: SocketAddress {
    switch self {
    case let .tcpPort(port):
      return .ipv6(host: "::", port: port)

    case let .unixDomainSocket(path):
      return .unixDomainSocket(path: path)
    }
  }

  func outputDescription(for socketAddress: SocketAddress) throws -> [String: Any] {
    switch self {
    case .tcpPort:
      guard let port = socketAddress.ipv6?.port ?? socketAddress.ipv4?.port else {
        throw ExtractionError.failedToExtractAssociatedInfo
      }
      return [
        "grpc_swift_port": port,
        "grpc_port": port,
      ]

    case .unixDomainSocket:
      guard let path = socketAddress.unixDomainSocket?.path else {
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

struct IDBPortsConfiguration {

  private enum Key {
    static let debugPort = "-debug-port"
    static let grpcDomainSock = "-grpc-domain-sock"
    static let tlsCertPath = "-tls-cert-path"
    static let grpcPort = "-grpc-port"
  }

  private let grpcDomainSocket: String?

  private let grpcPort: Int

  let debugserverPort: Int

  /// If nil, the TCP port listens unencrypted.
  let tlsCertPath: String?

  var swiftServerTarget: GRPCConnectionTarget {
    if let grpcDomainSocket, !grpcDomainSocket.isEmpty {
      return .unixDomainSocket(grpcDomainSocket)
    } else {
      return .tcpPort(port: grpcPort)
    }
  }

  init(arguments: UserDefaults) {
    self.debugserverPort = arguments.string(forKey: Key.debugPort).flatMap(Int.init) ?? 10881
    self.grpcPort = arguments.string(forKey: Key.grpcPort).flatMap(Int.init) ?? 10882
    self.grpcDomainSocket = arguments.string(forKey: Key.grpcDomainSock)
    self.tlsCertPath = arguments.string(forKey: Key.tlsCertPath)
  }
}
