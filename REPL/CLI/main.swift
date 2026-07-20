/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import ArgumentParser
import Foundation

/// Carries the root command's global options to `ReplRunner.run`, which executes
/// on a subcommand. swift-argument-parser does not expose a parent command's
/// options to its subcommands; `TestRepl.validate()` runs on the root as the
/// parser descends into the subcommand, and is where the parsed global options
/// are stashed for the run.
final class GlobalOptions: @unchecked Sendable {
  static let shared = GlobalOptions()

  private let lock = NSLock()
  private var storedReason: String?

  var reason: String? {
    get {
      lock.lock()
      defer { lock.unlock() }
      return storedReason
    }
    set {
      lock.lock()
      defer { lock.unlock() }
      storedReason = newValue
    }
  }
}

@main
struct TestRepl: AsyncParsableCommand {
  @Option(help: "The reason the tool is being used.")
  var reason: String?

  static let configuration = CommandConfiguration(
    commandName: "idb-repl",
    abstract: "Launch a test bundle in REPL mode",
    subcommands: [TestCommand.self, SimulatorCommand.self, AppCommand.self])

  mutating func validate() throws {
    GlobalOptions.shared.reason = reason
  }
}

struct TestCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "test",
    abstract: "Run the REPL in a test context.")

  @OptionGroup var repl: ReplRunner
  @OptionGroup var bundle: TestBundleOptions

  func run() async throws {
    try await repl.run(context: .test(bundle))
  }
}

struct SimulatorCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "simulator",
    abstract: "Run the REPL in a simulator context.")

  @OptionGroup var repl: ReplRunner

  func run() async throws {
    try await repl.run(context: .simulator)
  }
}

struct AppCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "app",
    abstract: "Run the REPL in an app context (launch an installed app with the REPL injected).")

  @OptionGroup var repl: ReplRunner
  @OptionGroup var app: AppOptions

  func run() async throws {
    try await repl.run(context: .app(app))
  }
}
