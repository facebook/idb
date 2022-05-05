/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import GRPC


//  ┌─────────────────────────────────────────────────────────┐
//  │                                                         │
//  │   There are 3 ways of start companion now. That         │
//  │   represents phases of the endpoint rollout.            │
//  │                                                         │
//  │   1. Use only cpp (full legacy)                         │
//  │                                                         │
//  │   2. Use cpp as main, swift as a sidecar, exposing      │
//  │      both cpp and swift ports and let client decide     │
//  │      where to go. IDB_SWIFT_COMPANION_PORT=<port>       │
//  │                                                         │
//  │               ┌─────┐     ┌───────┐                     │
//  │               │     │     │       │                     │
//  │               │     ├─────►  C++  │                     │
//  │               │  C  │     │       │                     │
//  │               │  l  │     └───▲───┘                     │
//  │               │  i  │         │                         │
//  │               │  e  │         │                         │
//  │               │  n  │     ┌───┴───┐                     │
//  │               │  t  │     │       │                     │
//  │               │     ├─────► Swift │                     │
//  │               │     │     │       │                     │
//  │               └─────┘     └───────┘                     │
//  │                                                         │
//  │                                                         │
//  │   3. Use swift as main, exposing *only* swift endpoint. │
//  │      Cpp is not exposed and used only as fallback.      │
//  │      IDB_USE_SWIFT_AS_DEFAULT=YES. In this mode env     │
//  │      IDB_SWIFT_COMPANION_PORT is ignored                │
//  │                                                         │
//  │        ┌────────┐     ┌───────┐     ┌───────┐           │
//  │        │        │     │       │     │       │           │
//  │        │ Client ├─────► Swift ├─────►  Cpp  │           │
//  │        │        │     │       │     │       │           │
//  │        └────────┘     └───────┘     └───────┘           │
//  │                                                         │
//  └─────────────────────────────────────────────────────────┘
//
// This object is temporary end exists only to support all intermediate phases of the rollout.
// All this logic will simplify a lot (back to what it was before moving to swift) and will be deleted
// simulataneously with cpp revamp.
enum GRPCConnectionTarget: CustomStringConvertible {
  case tcpPort(port: Int, useSwiftAsDefault: Bool)
  case unixDomainSocket(String)

  var grpcConnection: ConnectionTarget {
    switch self {
    case let .tcpPort(port, _):
      return .hostAndPort("localhost", port)

    case let .unixDomainSocket(path):
      return .unixDomainSocket(path)
    }
  }

  var outputDescription: [String: Any] {
    switch self {
    case let .tcpPort(port, useSwiftAsDefault):
      var description = ["grpc_swift_port": port]
      if useSwiftAsDefault {
        description["grpc_port"] = port
      }
      return description

    case let .unixDomainSocket(path):
      return ["grpc_path": path]
    }
  }

  var description: String {
    switch self {
    case let .tcpPort(port, _):
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

    static let swiftPortEnv = "IDB_SWIFT_COMPANION_PORT"
    static let useSwiftAsDefault = "IDB_USE_SWIFT_AS_DEFAULT"
  }

  /// The GRPC Unix Domain Socket Path
  private let grpcDomainSocket: String?

  /// The GRPC TCP Port.
  private let grpcPort: Int

  /// The GRPC TCP Port of swift server.
  @objc let grpcSwiftPort: Int

  /// The debugserver port
  @objc let debugserverPort: Int

  /// The TLS server cert path. If not specified grpcPort will be listening on unencrypted socket
  let tlsCertPath: String?

  private let fallbackCppDomainSocket: String
  @objc let useSwiftAsDefault: Bool

  var swiftServerTarget: GRPCConnectionTarget {
    if useSwiftAsDefault {
      if let grpcDomainSocket = grpcDomainSocket, !grpcDomainSocket.isEmpty {
        return .unixDomainSocket(grpcDomainSocket)
      } else {
        return .tcpPort(port: grpcPort, useSwiftAsDefault: true)
      }
    } else {
      return .tcpPort(port: grpcSwiftPort, useSwiftAsDefault: false)
    }
  }

  var cppServerTarget: GRPCConnectionTarget {
    if useSwiftAsDefault {
      return .unixDomainSocket(fallbackCppDomainSocket)
    } else {
      return .tcpPort(port: grpcPort, useSwiftAsDefault: false)
    }
  }

  /// Objc++ .mm files can not import swift bridged header and use swift objects. We need to keep legacy for compatibility
  @objc var legacyConfigurationObject: FBIDBPortsConfiguration {
    if useSwiftAsDefault {
      return .init(grpcDomainSocket: fallbackCppDomainSocket,
                   grpcPort: 0,
                   debugserverPort: UInt16(debugserverPort),
                   tlsCertPath: tlsCertPath)
    } else {
      return .init(grpcDomainSocket: grpcDomainSocket,
                   grpcPort: UInt16(grpcPort),
                   debugserverPort: UInt16(debugserverPort),
                   tlsCertPath: tlsCertPath)
    }
  }

  /// Construct a ports object.
  @objc init(arguments: UserDefaults) {
    self.debugserverPort = arguments.string(forKey: Key.debugPort).flatMap(Int.init) ?? 10881
    self.grpcPort = arguments.string(forKey: Key.grpcPort).flatMap(Int.init) ?? 10882
    self.grpcSwiftPort = ProcessInfo.processInfo.environment[Key.swiftPortEnv].flatMap(Int.init) ?? 0
    self.grpcDomainSocket = arguments.string(forKey: Key.grpcDomainSock)
    self.tlsCertPath = arguments.string(forKey: Key.tlsCertPath)
    self.useSwiftAsDefault = ProcessInfo.processInfo.environment[Key.useSwiftAsDefault] == "YES"

    self.fallbackCppDomainSocket = "/tmp/idb_companion_\(UUID().uuidString.lowercased())"
  }

}
