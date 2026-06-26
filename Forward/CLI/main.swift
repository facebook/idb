/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

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

    logStderr("Remaining arguments: \(remainingArguments)")

    // Discover the companion to use, starting one if needed. A companion we start
    // should not outlive its use, so it exits after 5 minutes without activity.
    // With no udid, use the single running companion (or start one for the only
    // available simulator).
    let idleShutdownTime = 5 * 60
    let manager = CompanionManager(version: .v2, companionPath: companionBinary)
    let companion: CompanionInfo
    do {
      if let udid {
        companion = try await manager.companionInfo(forUDID: udid, idleShutdownTime: idleShutdownTime)
      } else {
        companion = try await manager.defaultCompanion(idleShutdownTime: idleShutdownTime)
      }
    } catch {
      logStderr("Error: \(error)")
      exit(1)
    }

    logCompanion(companion)

    // Forward the remaining arguments to the companion as a `cli` JSON-RPC
    // request: the companion runs them through idb2's ArgumentParser and returns
    // the command's stdout and exit code, which we relay as our own.
    switch companion.address {
    case let .domainSocket(path):
      let response: Data
      do {
        response = try sendCLICommand(remainingArguments, toSocketPath: path)
      } catch {
        logStderr("Error: \(error)")
        exit(1)
      }
      emit(response)
    case let .tcp(host, port):
      logStderr("Error: forwarding to TCP companions is not supported yet (\(host):\(port))")
      exit(1)
    }
  }

  /// Parses the companion's JSON-RPC response: writes the command's stdout to our
  /// stdout and exits with its exit code, or reports an error response.
  private static func emit(_ data: Data) -> Never {
    var json = data
    while json.last == 0x0A || json.last == 0x0D {
      json.removeLast()
    }
    guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else {
      logStderr("Error: companion returned an invalid response")
      exit(1)
    }
    if let result = object["result"] as? [String: Any] {
      let output = result["stdout"] as? String ?? ""
      let exitCode = (result["exitCode"] as? NSNumber)?.int32Value ?? 0
      FileHandle.standardOutput.write(Data(output.utf8))
      exit(exitCode)
    }
    if let errorObject = object["error"] as? [String: Any] {
      logStderr("Error: \(errorObject["message"] as? String ?? "\(errorObject)")")
      exit(1)
    }
    logStderr("Error: companion response had neither result nor error")
    exit(1)
  }

  /// Writes a diagnostic line to stderr, keeping stdout for the forwarded
  /// command's own output.
  private static func logStderr(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
  }

  private static func logCompanion(_ companion: CompanionInfo) {
    let address: String
    switch companion.address {
    case let .tcp(host, port): address = "tcp \(host):\(port)"
    case let .domainSocket(path): address = "unix \(path)"
    }
    logStderr("Companion: udid=\(companion.udid) isLocal=\(companion.isLocal) pid=\(companion.pid.map(String.init) ?? "none") address=\(address)")
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

  /// Encodes `arguments` as a `cli` JSON-RPC request, writes it (newline framed)
  /// to the companion listening on `path`, then reads the response to EOF and
  /// returns it.
  private static func sendCLICommand(_ arguments: [String], toSocketPath path: String) throws -> Data {
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

    // Read the response to EOF: the companion writes one JSON-RPC response line
    // and then closes the connection.
    var response = Data()
    var chunk = [UInt8](repeating: 0, count: 4096)
    while true {
      let n = chunk.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
      if n <= 0 {
        break
      }
      response.append(contentsOf: chunk[0..<n])
    }
    return response
  }
}
