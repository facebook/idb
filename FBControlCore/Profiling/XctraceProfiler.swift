/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// What `xctrace record` records.
public enum XctraceProcess: Equatable, Sendable {
  case attach(pid_t)
  case launch(bundleID: String)
  case allProcesses
}

/// Records with `xctrace`, then exports the tables the report is made of.
public enum XctraceProfiler {

  /// How long a stopped recording gets to finish writing the trace before it is killed.
  private static let stopTimeout: TimeInterval = 600

  static let defaultSchemas: [String: [String]] = [
    "Time Profiler": ["time-profile"],
    "Hangs": ["potential-hangs"],
  ]

  /// Records until the time limit, or until the calling task is cancelled.
  public static func trace(_ configuration: TraceConfiguration, process: XctraceProcess, target: any Target, logger: any ControlCoreLogger) async throws -> ProfileResult {
    let xctrace = try XCTraceRecordOperation.xctracePath()
    let tracePath = configuration.outputPath ?? (target.auxillaryDirectory as NSString).appendingPathComponent("xctrace-\(UUID().uuidString).trace")
    defer {
      if configuration.outputPath == nil {
        try? FileManager.default.removeItem(atPath: tracePath)
      }
    }

    let environment = try await recordEnvironment(target: target)
    let recordArguments = recordArguments(template: configuration.template, timeLimit: configuration.timeLimit, udid: target.udid, process: process, outputPath: tracePath)
    try await record(xctrace: xctrace, arguments: recordArguments, environment: environment, logger: logger)

    let tableOfContents = try await export(xctrace: xctrace, arguments: ["export", "--input", tracePath, "--toc"], logger: logger)
    let runs = try XctraceExportParser.runs(fromTableOfContents: tableOfContents)
    var tables: [TraceTable] = []
    if let run = runs.last {
      for schema in try schemas(requested: configuration.schemas, template: configuration.template, available: run.schemas) {
        let xml = try await export(xctrace: xctrace, arguments: ["export", "--input", tracePath, "--xpath", xpath(run: run.number, schema: schema)], logger: logger)
        tables.append(try XctraceExportParser.table(from: xml, rowLimit: configuration.rowLimit))
      }
    }
    return ProfileResult(
      report: .trace(TraceReport(runs: runs, tables: tables)),
      toolOutput: tableOfContents,
      artifact: configuration.outputPath.map { URL(fileURLWithPath: $0) })
  }

  static func recordArguments(template: String, timeLimit: Duration, udid: String, process: XctraceProcess, outputPath: String) -> [String] {
    // Rounding up keeps a positive limit from reaching xctrace as 0ms.
    let attosecondsPerMillisecond: Int64 = 1_000_000_000_000_000
    let milliseconds = max(1, timeLimit.components.seconds * 1000 + (timeLimit.components.attoseconds + attosecondsPerMillisecond - 1) / attosecondsPerMillisecond)
    var arguments = ["record", "--template", template, "--device", udid, "--output", outputPath, "--time-limit", "\(milliseconds)ms", "--no-prompt"]
    switch process {
    case let .attach(pid):
      arguments += ["--attach", String(pid)]
    case .allProcesses:
      arguments += ["--all-processes"]
    case let .launch(bundleID):
      // Everything after the bundle ID is passed to the application, so it goes last.
      arguments += ["--launch", "--", bundleID]
    }
    return arguments
  }

  static func schemas(requested: [String]?, template: String, available: [String]) throws -> [String] {
    guard let requested else {
      return (defaultSchemas[template] ?? []).filter(available.contains)
    }
    if let missing = requested.first(where: { !available.contains($0) }) {
      throw ProfileError.traceSchemaMissing(schema: missing, available: available)
    }
    return requested
  }

  static func xpath(run: Int, schema: String) -> String {
    "/trace-toc/run[@number=\"\(run)\"]/data/table[@schema=\"\(schema)\"]"
  }

  /// xctrace can only see a simulator outside the default device set through the shim.
  private static func recordEnvironment(target: any Target) async throws -> [String: String] {
    guard let deviceSetPath = target.customDeviceSetPath else {
      return [:]
    }
    let shim = try await XCTestShimConfiguration.sharedShimConfiguration()
    return ["SIM_DEVICE_SET_PATH": deviceSetPath, "DYLD_INSERT_LIBRARIES": shim.macOSTestShimPath]
  }

  private static func record(xctrace: String, arguments: [String], environment: [String: String], logger: any ControlCoreLogger) async throws {
    logger.log("Recording with xctrace \(CollectionInformation.oneLineDescription(from: arguments))")
    let process = try await awaitStart(
      of: FBProcessBuilder<NSNull, NSData, NSData>
        .withLaunchPath(xctrace, arguments: arguments)
        .withEnvironmentAdditions(environment)
        .withStdOutInMemoryAsData()
        .withStdErrInMemoryAsData()
        .withTaskLifecycleLogging(to: logger))
    let recording = Running(process: process)
    let exitCode = try await withTaskCancellationHandler {
      try await awaitExitCode(of: recording.process)
    } onCancel: {
      // SIGINT is xctrace's Ctrl-C: it stops recording and saves the trace.
      _ = recording.process.sendSignal(SIGINT, backingOffToKillWithTimeout: stopTimeout, logger: logger)
    }
    // xctrace reports why a recording failed on stdout, alongside its progress.
    try check(tool: "xctrace", exitCode: exitCode, output: [process.stdOut, process.stdErr])
  }

  private static func export(xctrace: String, arguments: [String], logger: any ControlCoreLogger) async throws -> Data {
    let process = try await awaitStart(
      of: FBProcessBuilder<NSNull, NSData, NSData>
        .withLaunchPath(xctrace, arguments: arguments)
        .withStdOutInMemoryAsData()
        .withStdErrInMemoryAsData()
        .withTaskLifecycleLogging(to: logger))
    let exporting = Running(process: process)
    let exitCode = try await withTaskCancellationHandler {
      try await awaitExitCode(of: exporting.process)
    } onCancel: {
      // An abandoned export has nothing worth saving.
      _ = exporting.process.sendSignal(SIGKILL)
    }
    try check(tool: "xctrace", exitCode: exitCode, output: [process.stdOut, process.stdErr])
    return process.stdOut.map { Data(referencing: $0) } ?? Data()
  }

  private static func check(tool: String, exitCode: Int32, output: [NSData?]) throws {
    guard exitCode == 0 else {
      let text = output.compactMap { $0.map { String(decoding: Data(referencing: $0), as: UTF8.self) } }.joined(separator: "\n")
      throw ProfileError.toolFailed(tool: tool, exitCode: exitCode, stderr: text)
    }
  }

  /// The process a cancellation handler signals; it is only ever signalled, never mutated.
  private struct Running: @unchecked Sendable {
    let process: FBSubprocess<NSNull, NSData, NSData>
  }
}
