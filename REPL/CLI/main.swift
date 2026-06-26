/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import ArgumentParser

@main
struct TestRepl: AsyncParsableCommand {
  @Option(help: "The reason the tool is being used.")
  var reason: String?

  static let configuration = CommandConfiguration(
    commandName: "idb-repl",
    abstract: "Launch a test bundle in REPL mode",
    subcommands: [TestCommand.self, SimulatorCommand.self])
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
