/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import Foundation

/// Profiles simulator processes with the runtime's own memory and sampling tools, which can read a `dyld_sim` process
/// where the host's builds cannot.
public struct SimulatorProfileCommands: ProfileCommands {

  private let simulator: Simulator

  public static func commands(with simulator: Simulator) -> SimulatorProfileCommands {
    SimulatorProfileCommands(simulator: simulator)
  }

  public func profile(_ configuration: ProfileConfiguration, target: ProfileTarget) async throws -> ProfileOperation {
    let pid = try await resolvePID(target)
    let tools = simulator.runtimeTools
    switch configuration {
    case .leaks:
      return Self.oneShot {
        // leaks exits 1 when it finds leaks.
        let stdout = try await Self.run("leaks", [String(pid)], acceptingExitCodes: [0, 1], tools: tools)
        return ProfileResult(report: .leaks(try RuntimeToolOutputParser.leaks(Self.text(stdout))), toolOutput: stdout, artifact: nil)
      }
    case let .memgraph(outputPath):
      let graphPath = Self.graphPath(for: outputPath)
      return Self.oneShot {
        // Writing the graph prints nothing useful, so the report comes from reading the graph back.
        _ = try await Self.run("leaks", ["--outputGraph=\(graphPath)", String(pid)], acceptingExitCodes: [0, 1], tools: tools)
        let stdout = try await Self.run("leaks", [graphPath], acceptingExitCodes: [0, 1], tools: tools)
        return ProfileResult(report: .leaks(try RuntimeToolOutputParser.leaks(Self.text(stdout))), toolOutput: stdout, artifact: URL(fileURLWithPath: graphPath))
      }
    case .heap:
      return Self.oneShot {
        let stdout = try await Self.run("heap", [String(pid)], tools: tools)
        return ProfileResult(report: .heap(try RuntimeToolOutputParser.heap(Self.text(stdout))), toolOutput: stdout, artifact: nil)
      }
    case let .sample(seconds):
      return Self.oneShot {
        let stdout = try await Self.run("sample", [String(pid), String(seconds)], tools: tools)
        return ProfileResult(report: .sample(try RuntimeToolOutputParser.sample(Self.text(stdout))), toolOutput: stdout, artifact: nil)
      }
    case .vmmap:
      return Self.oneShot {
        let stdout = try await Self.run("vmmap", [String(pid), "-summary"], tools: tools)
        return ProfileResult(report: .vmmap(try RuntimeToolOutputParser.vmmap(Self.text(stdout))), toolOutput: stdout, artifact: nil)
      }
    case .footprint:
      return Self.oneShot {
        let json = try await Self.footprint(pid: pid, tools: tools)
        return ProfileResult(report: .footprint(try RuntimeToolOutputParser.footprint(json)), toolOutput: json, artifact: nil)
      }
    case let .resources(interval, scope):
      let (samples, continuation) = AsyncStream<ResourceSample>.makeStream()
      let task = Task<ProfileResult, Error> {
        await ResourceSampler.sample(pid: pid, interval: interval, scope: scope) { continuation.yield($0) }
        continuation.finish()
        return ProfileResult(report: nil, toolOutput: Data(), artifact: nil)
      }
      continuation.onTermination = { _ in task.cancel() }
      return ProfileOperation(samples: samples, task: task)
    }
  }

  private func resolvePID(_ target: ProfileTarget) async throws -> pid_t {
    switch target {
    case let .pid(pid):
      return pid
    case let .bundleID(bundleID):
      return try await simulator.application.processID(forBundleID: bundleID)
    }
  }

  /// leaks runs inside the simulator, where a relative path resolves against a different directory than the host's,
  /// and appends the extension to a path that lacks it.
  static func graphPath(for outputPath: String) -> String {
    let path = URL(fileURLWithPath: outputPath).standardizedFileURL.path
    return path.hasSuffix(".memgraph") ? path : path + ".memgraph"
  }

  private static func oneShot(_ body: @escaping @Sendable () async throws -> ProfileResult) -> ProfileOperation {
    ProfileOperation(task: Task(operation: body))
  }

  private static func run(_ tool: String, _ arguments: [String], acceptingExitCodes: Set<Int32> = [0], tools: SimulatorRuntimeToolCommands) async throws -> Data {
    let output = try await tools.run("usr/bin/\(tool)", arguments: arguments)
    try check(output, tool: tool, acceptingExitCodes: acceptingExitCodes)
    return output.stdout
  }

  /// The runtime ships no footprint, and the host's must run inside the simulator: run on the host, it can't read a
  /// simulator process without root.
  private static func footprint(pid: pid_t, tools: SimulatorRuntimeToolCommands) async throws -> Data {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent("footprint-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: path) }
    let output = try await tools.launchConsumingOutput(launchPath: "/usr/bin/footprint", arguments: [String(pid), "-j", path.path])
    try check(output, tool: "footprint", acceptingExitCodes: [0])
    guard let json = try? Data(contentsOf: path) else {
      throw ProfileError.toolFailed(tool: "footprint", exitCode: output.exitCode, stderr: "wrote no report to \(path.path)\nstdout: \(text(output.stdout))\nstderr: \(text(output.stderr))")
    }
    return json
  }

  private static func check(_ output: InSimulatorToolOutput, tool: String, acceptingExitCodes: Set<Int32>) throws {
    guard acceptingExitCodes.contains(output.exitCode) else {
      throw ProfileError.toolFailed(tool: tool, exitCode: output.exitCode, stderr: text(output.stderr))
    }
  }

  private static func text(_ data: Data) -> String {
    String(decoding: data, as: UTF8.self)
  }
}
