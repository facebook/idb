/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@_implementationOnly import ArgumentParser
@_implementationOnly import CompanionUtilities
import Foundation

@main
struct VideoCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "sim-video",
    abstract: "Record or stream a simulator with JSON-line overlay control",
    subcommands: [Record.self, Stream.self])
}

func waitForStopSignal() async {
  let stopped = AsyncPromise<Void>()
  let previousInterrupt = signal(SIGINT, SIG_IGN)
  let previousTerminate = signal(SIGTERM, SIG_IGN)
  let sources = [SIGINT, SIGTERM].map { number in
    let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
    source.setEventHandler { stopped.resolve(()) }
    source.resume()
    return source
  }
  defer {
    sources.forEach { $0.cancel() }
    signal(SIGINT, previousInterrupt)
    signal(SIGTERM, previousTerminate)
  }
  _ = try? await stopped.value
}
