/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionDiscovery
import CompanionServer
import Darwin
import Foundation

@main
struct IdbForward {
  static func main() async {
    // Register the TLS identity provider so a TCP companion connection uses TLS by
    // default; without a provider, TCP falls back to plaintext.
    // @oss-disable

    let allArguments = Array(CommandLine.arguments.dropFirst())

    // Pull recognized flags out of the argument list; everything else is forwarded
    // to the companion. `--idb-companion-binary` overrides the default
    // system-installed companion CompanionDiscovery launches (mirrors idb-repl's
    // flag). `--companion <host:port>` connects directly to a TCP companion,
    // bypassing discovery. `--plaintext` forces an unencrypted TCP connection.
    var udid: String?
    var companionBinary: String?
    var explicitCompanion: String?
    var plaintext = false
    var remainingArguments: [String] = []
    var iterator = allArguments.makeIterator()
    while let argument = iterator.next() {
      switch argument {
      case "--udid": udid = iterator.next()
      case "--idb-companion-binary": companionBinary = iterator.next()
      case "--companion": explicitCompanion = iterator.next()
      case "--plaintext": plaintext = true
      default: remainingArguments.append(argument)
      }
    }

    logStderr("Remaining arguments: \(remainingArguments)")

    // Resolve the companion address. With `--companion host:port` we connect to an
    // explicit (typically remote) TCP companion and skip CompanionDiscovery
    // entirely. Otherwise we discover a companion, starting one if needed (it exits
    // after 5 minutes idle); with no udid we use the single running companion or
    // start one for the only available simulator.
    let address: CompanionAddress
    if let explicitCompanion {
      guard let parsed = CompanionAddress.parse(tcp: explicitCompanion) else {
        logStderr("Error: --companion expects host:port, e.g. 127.0.0.1:10882 (got '\(explicitCompanion)')")
        exit(1)
      }
      address = parsed
      logStderr("Companion: explicit \(addressDescription(parsed))")
    } else {
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
      address = companion.address
    }

    // Forward the remaining arguments to the companion as a `cli` JSON-RPC request:
    // the companion runs them through idb2's ArgumentParser and returns the
    // command's stdout and exit code, which we relay as our own. TLS (for a TCP
    // companion) is handled inside CompanionClient via the registered provider.
    let response: Data
    do {
      response = try await CompanionClient.sendCLICommand(
        remainingArguments, to: address, tls: plaintext ? .disabled : .metaIdentity)
    } catch {
      logStderr("Error: \(error)")
      exit(1)
    }
    emit(response)
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

  private static func addressDescription(_ address: CompanionAddress) -> String {
    switch address {
    case let .tcp(host, port): return "tcp \(host):\(port)"
    case let .domainSocket(path): return "unix \(path)"
    }
  }

  private static func logCompanion(_ companion: CompanionInfo) {
    logStderr("Companion: udid=\(companion.udid) isLocal=\(companion.isLocal) pid=\(companion.pid.map(String.init) ?? "none") address=\(addressDescription(companion.address))")
  }
}
