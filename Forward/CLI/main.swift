/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

// patternlint-disable avoid-print-to-prevent-production-overhead

import CompanionDiscovery
import Darwin
import Foundation

@main
struct IdbForward {
  static func main() async {
    let allArguments = Array(CommandLine.arguments.dropFirst())

    // Pull `--udid <value>` and `--idb-companion-binary <value>` out of the
    // argument list. The latter overrides the default system-installed companion
    // binary that CompanionDiscovery launches (mirrors idb-repl's flag).
    var udid: String?
    var companionBinary: String?
    var remainingArguments: [String] = []
    var iterator = allArguments.makeIterator()
    while let argument = iterator.next() {
      if argument == "--udid" {
        udid = iterator.next()
      } else if argument == "--idb-companion-binary" {
        companionBinary = iterator.next()
      } else {
        remainingArguments.append(argument)
      }
    }

    print("Remaining arguments: \(remainingArguments)")

    // Discover the companion to use, starting one if needed. A companion we start
    // should not outlive its use, so it exits after 5 minutes without activity.
    // With no udid, use the single running companion (or start one for the only
    // available simulator).
    let idleShutdownTime: TimeInterval = 5 * 60
    let manager = CompanionManager(version: .v2, companionPath: companionBinary)
    let companion: CompanionInfo
    do {
      if let udid {
        companion = try await manager.companionInfo(forUDID: udid, idleShutdownTime: idleShutdownTime)
      } else {
        companion = try await manager.defaultCompanion(idleShutdownTime: idleShutdownTime)
      }
    } catch {
      print("Error: \(error)")
      exit(1)
    }

    printCompanion(companion)

    // Forward the remaining arguments to the companion as a `cli` JSON-RPC
    // request: the companion runs them through idb2's ArgumentParser.
    switch companion.address {
    case let .domainSocket(path):
      do {
        try sendCLICommand(remainingArguments, toSocketPath: path)
        print("Forwarded cli command to companion: \(remainingArguments)")
      } catch {
        print("Error: \(error)")
        exit(1)
      }
    case let .tcp(host, port):
      print("Error: forwarding to TCP companions is not supported yet (\(host):\(port))")
      exit(1)
    }
  }

  /// Prints the discovered companion's details to stdout.
  private static func printCompanion(_ companion: CompanionInfo) {
    print("Companion:")
    print("  udid: \(companion.udid)")
    print("  isLocal: \(companion.isLocal)")
    print("  pid: \(companion.pid.map(String.init) ?? "none")")
    switch companion.address {
    case let .tcp(host, port):
      print("  address: tcp \(host):\(port)")
    case let .domainSocket(path):
      print("  address: unix \(path)")
    }
  }

  enum ForwardError: Error, CustomStringConvertible {
    case encodeFailed
    case connectFailed(path: String, code: Int32)
    case writeFailed

    var description: String {
      switch self {
      case .encodeFailed:
        return "Failed to encode the JSON-RPC request"
      case let .connectFailed(path, code):
        return "Failed to connect to the companion socket at \(path) (errno \(code))"
      case .writeFailed:
        return "Failed to write the command to the companion socket"
      }
    }
  }

  /// Encodes `arguments` as a `cli` JSON-RPC request and writes it, newline
  /// terminated, to the companion listening on `path`.
  private static func sendCLICommand(_ arguments: [String], toSocketPath path: String) throws {
    let request: [String: Any] = [
      "jsonrpc": "2.0",
      "method": "cli",
      "params": arguments,
      "id": 1,
    ]
    guard var data = try? JSONSerialization.data(withJSONObject: request) else {
      throw ForwardError.encodeFailed
    }
    data.append(0x0A) // newline frames the message for the server

    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else {
      throw ForwardError.connectFailed(path: path, code: errno)
    }
    defer { close(fd) }

    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let capacity = MemoryLayout.size(ofValue: addr.sun_path)
    guard path.utf8.count < capacity else {
      throw ForwardError.connectFailed(path: path, code: ENAMETOOLONG)
    }
    withUnsafeMutablePointer(to: &addr.sun_path) { rawPointer in
      rawPointer.withMemoryRebound(to: CChar.self, capacity: capacity) { destination in
        _ = strncpy(destination, path, capacity - 1)
      }
    }
    let length = socklen_t(MemoryLayout<sockaddr_un>.size)
    let connected = withUnsafePointer(to: &addr) { addrPointer in
      addrPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
        Darwin.connect(fd, sockaddrPointer, length)
      }
    }
    guard connected == 0 else {
      throw ForwardError.connectFailed(path: path, code: errno)
    }

    try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
      guard let base = raw.baseAddress else { return }
      var written = 0
      while written < raw.count {
        let n = Darwin.write(fd, base + written, raw.count - written)
        guard n > 0 else {
          throw ForwardError.writeFailed
        }
        written += n
      }
    }

    // Keep the connection open and read until the companion closes it: that close
    // is the companion's acknowledgement that it received the request, so the
    // command is reliably delivered before this process exits.
    var byte: UInt8 = 0
    while Darwin.read(fd, &byte, 1) > 0 {}
  }
}
