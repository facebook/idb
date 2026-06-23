/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

// patternlint-disable avoid-print-to-prevent-production-overhead

import CompanionDiscovery
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
}
