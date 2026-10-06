/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

public final class ProcessLogOperation: LogOperation {

  public let process: RunningSubprocess
  public let consumer: any DataConsumer
  private let executable: String

  public init(process: RunningSubprocess, executable: String, consumer: any DataConsumer) {
    self.process = process
    self.executable = executable
    self.consumer = consumer
  }

  // MARK: - LogOperation

  public func waitUntilCompleted() async throws {
    let status: TerminationStatus
    do {
      status = try await process.terminationStatus
    } catch {
      await process.terminate(gracePeriod: 5)
      throw error
    }
    guard ExitPolicy.mustExitZero.accepts(status) else {
      throw SubprocessError.unacceptableTermination(status: status, policy: .mustExitZero, executable: executable, processIdentifier: process.processIdentifier)
    }
  }

  public class func osLogArgumentsInsertStreamIfNeeded(_ arguments: [String]) -> [String] {
    guard let firstArgument = arguments.first else {
      return ["stream"]
    }
    if ProcessLogOperation.osLogSubcommands.contains(firstArgument) {
      return arguments
    }
    return ["stream"] + arguments
  }

  private static let osLogSubcommands: Set<String> = {
    Set(["collect", "config", "erase", "show", "stream", "stats"])
  }()
}
