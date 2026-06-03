/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import ArgumentParser

@main
struct TestRepl: AsyncParsableCommand {
  static var configuration = CommandConfiguration(
    commandName: "idb-repl",
    abstract: "Launch a test bundle in REPL mode",
    subcommands: [DylibCommand.self])
}
