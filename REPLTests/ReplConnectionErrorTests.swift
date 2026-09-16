/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionDiscovery
import GRPCCore
import Testing

@Suite
struct ReplConnectionErrorTests {

  private let registryCompanion = ResolvedCompanion(
    address: .tcp(host: "companion.example", port: 10882),
    source: .registry)

  @Test
  func connectionSourceTelemetryValuesAreStable() {
    #expect(CompanionConnectionSource.commandLine.rawValue == "command_line")
    #expect(CompanionConnectionSource.environment.rawValue == "environment")
    #expect(CompanionConnectionSource.registry.rawValue == "registry")
    #expect(CompanionConnectionSource.localDiscovery.rawValue == "local_discovery")
  }

  @Test
  func unavailableWithoutReplPrefixNamesEndpointSourceAndRemedy() {
    let error = actionableCompanionConnectionError(
      RPCError(code: .unavailable, message: "connection refused"),
      companion: registryCompanion)

    let description = String(describing: error)
    #expect(description.contains("companion.example:10882"))
    #expect(description.contains("/tmp/idb/state"))
    #expect(description.contains("connection refused"))
    #expect(description.contains("--companion"))
  }

  @Test
  func companionUnavailableErrorPassesThrough() {
    let original = RPCError(
      code: .unavailable,
      message: "repl: control socket closed; the target process may have crashed")
    let error = actionableCompanionConnectionError(original, companion: registryCompanion)

    #expect(error as? RPCError == original)
  }

  @Test
  func deadlineWithoutReplPrefixIsActionable() {
    let error = actionableCompanionConnectionError(
      RPCError(code: .deadlineExceeded, message: "deadline exceeded"),
      companion: ResolvedCompanion(
        address: .tcp(host: "2001:db8::1", port: 10882),
        source: .environment))

    #expect(
      error as? ReplConnectionError
        == .timedOut(
          ResolvedCompanion(
            address: .tcp(host: "2001:db8::1", port: 10882),
            source: .environment),
          detail: "deadline exceeded"))
    #expect(String(describing: error).contains("[2001:db8::1]:10882"))
    #expect(String(describing: error).contains("IDB_COMPANION"))
  }

  @Test
  func companionDeadlineErrorPassesThrough() {
    let original = RPCError(
      code: .deadlineExceeded,
      message: "repl: timed out connecting to control socket")
    let error = actionableCompanionConnectionError(original, companion: registryCompanion)

    #expect(error as? RPCError == original)
  }

  @Test
  func unimplementedErrorRequestsCompanionUpgrade() {
    let error = actionableCompanionConnectionError(
      RPCError(code: .unimplemented, message: "unknown method repl"),
      companion: registryCompanion)

    #expect(error as? ReplConnectionError == .unsupported(registryCompanion, detail: "unknown method repl"))
    #expect(String(describing: error).contains("Upgrade or restart"))
  }

  @Test
  func otherRPCErrorPassesThrough() {
    let original = RPCError(code: .failedPrecondition, message: "app is not launchable")
    let error = actionableCompanionConnectionError(original, companion: registryCompanion)

    #expect(error as? RPCError == original)
  }

  @Test
  func nonGRPCErrorPassesThrough() {
    let original = TestError.example
    let error = actionableCompanionConnectionError(original, companion: registryCompanion)

    #expect(error as? TestError == .example)
  }

  @Test
  func cancellationPassesThrough() {
    let error = actionableCompanionConnectionError(
      CancellationError(),
      companion: registryCompanion)

    #expect(error is CancellationError)
  }

  private enum TestError: Error, Equatable {
    case example
  }
}
