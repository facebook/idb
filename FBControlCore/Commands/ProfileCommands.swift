/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// The process a profiler inspects.
public enum ProfileTarget: Equatable, Sendable {
  case pid(pid_t)
  /// The running process of an installed application.
  case bundleID(String)
}

/// What to profile, with the options that apply to it.
public enum ProfileConfiguration: Equatable, Sendable {
  /// Leaked allocations, with the stack that allocated each.
  case leaks
  /// A memory graph written to `outputPath`, reported as `leaks` reports it.
  case memgraph(outputPath: String)
  /// Live heap allocations, grouped by class.
  case heap
  /// Call stacks sampled for `seconds`.
  case sample(seconds: UInt)
  /// Virtual memory, summarised by region type.
  case vmmap
  /// Physical memory footprint, by category.
  case footprint
  /// Resource usage sampled every `interval` until the target exits or the operation is stopped.
  case resources(interval: Duration, scope: ResourceSampleScope)
}

public enum ProfileReport: Equatable, Sendable {
  case leaks(LeaksReport)
  case heap(HeapReport)
  case sample(SampleReport)
  case vmmap(VmmapReport)
  case footprint(FootprintReport)
}

public struct ProfileResult: Equatable, Sendable {
  /// Nil for `resources`, which reports through `ProfileOperation.samples` instead.
  public let report: ProfileReport?
  /// What the tool wrote, unparsed: text for most tools, JSON for `footprint`.
  public let toolOutput: Data
  /// The file the profiler wrote, such as a memory graph.
  public let artifact: URL?

  public init(report: ProfileReport?, toolOutput: Data, artifact: URL?) {
    self.report = report
    self.toolOutput = toolOutput
    self.artifact = artifact
  }
}

/// A profiler that has started.
public struct ProfileOperation: Sendable {
  /// Every sample a `resources` profiler takes; finishes immediately for every other profiler.
  public let samples: AsyncStream<ResourceSample>
  private let task: Task<ProfileResult, Error>

  public init(samples: AsyncStream<ResourceSample> = AsyncStream { $0.finish() }, task: Task<ProfileResult, Error>) {
    self.samples = samples
    self.task = task
  }

  /// Returns once the profiler finishes, throwing if its tool failed.
  public var result: ProfileResult {
    get async throws { try await task.value }
  }

  /// Ends a `resources` profiler. Any other profiler is cancelled, so `result` throws `CancellationError`.
  public func stop() {
    task.cancel()
  }
}

public enum ProfileError: Error, Equatable, LocalizedError {
  case toolFailed(tool: String, exitCode: Int32, stderr: String)

  public var errorDescription: String? {
    switch self {
    case let .toolFailed(tool, exitCode, stderr):
      return "\(tool) exited with code \(exitCode): \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
    }
  }
}

public protocol ProfileCommands {

  /// Starts profiling `target`. Throws if the target can't be resolved; the profiler's own failures surface from
  /// `ProfileOperation.result`.
  func profile(_ configuration: ProfileConfiguration, target: ProfileTarget) async throws -> ProfileOperation
}
