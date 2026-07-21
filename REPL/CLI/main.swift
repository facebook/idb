/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

// patternlint-disable avoid-print-to-prevent-production-overhead

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
  @Option(help: "The reason the tool is being used. (Required for use by AI agents.)")
  var reason: String?

  @Flag(name: [.customShort("v"), .long], help: "Print the build date and time, then exit.")
  var version = false

  static let configuration = CommandConfiguration(
    commandName: "idb-repl",
    abstract: "Compile and run Swift code inside a live process on an iOS simulator.",
    subcommands: [TestCommand.self, SimulatorCommand.self, AppCommand.self])

  mutating func validate() throws {
    GlobalOptions.shared.reason = reason
  }

  func run() async throws {
    if version {
      print("idb-repl built at \(kBuildDate) \(kBuildTime)")
      return
    }
    // No subcommand and no --version: show help, matching the default behavior.
    throw CleanExit.helpRequest(self)
  }
}

struct TestCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "test",
    abstract: "Run code in a live test process.")

  @OptionGroup var repl: ReplRunner
  @OptionGroup var bundle: TestBundleOptions

  func run() async throws {
    try await repl.run(context: .test(bundle))
  }
}

struct SimulatorCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "simulator",
    abstract: "Run code in a live simulator process.")

  @OptionGroup var repl: ReplRunner

  func run() async throws {
    try await repl.run(context: .simulator)
  }
}

struct AppCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "app",
    abstract: "Run code in a live app process.")

  @OptionGroup var repl: ReplRunner
  @OptionGroup var app: AppOptions

  func run() async throws {
    try await repl.run(context: .app(app))
  }
}
