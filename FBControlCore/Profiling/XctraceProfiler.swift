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

  /// Records until the time limit, or until the operation is stopped.
  public static func operation(_ configuration: TraceConfiguration, process: XctraceProcess, target: any Target, logger: any ControlCoreLogger) -> ProfileOperation {
    let deviceSetPath = target.customDeviceSetPath
    return operation(configuration, process: process, udid: target.udid, scratch: target.temporaryDirectory, logger: logger) {
      (try XCTraceRecordOperation.xctracePath(), try await recordEnvironment(deviceSetPath: deviceSetPath))
    }
  }

  /// `tool` resolves the xctrace to run and the environment `record` needs. Without an output path, the trace is
  /// recorded into a directory in `scratch` that is removed once the trace is exported.
  static func operation(
    _ configuration: TraceConfiguration,
    process: XctraceProcess,
    udid: String,
    scratch: TemporaryDirectory,
    logger: any ControlCoreLogger,
    tool: @escaping @Sendable () async throws -> (xctrace: String, recordEnvironment: [String: String])
  ) -> ProfileOperation {
    ProfileOperation(stoppable: { stop in
      let (xctrace, environment) = try await tool()
      func trace(into tracePath: String) async throws -> ProfileResult {
        try await Self.trace(configuration, process: process, xctrace: xctrace, udid: udid, tracePath: tracePath, environment: environment, stop: stop, logger: logger)
      }
      if let outputPath = configuration.outputPath {
        return try await trace(into: outputPath)
      }
      return try await scratch.withTemporaryDirectory { directory in
        try await trace(into: directory.appendingPathComponent("xctrace.trace").path)
      }
    })
  }

  private static func trace(
    _ configuration: TraceConfiguration,
    process: XctraceProcess,
    xctrace: String,
    udid: String,
    tracePath: String,
    environment: [String: String],
    stop: ProfileStopRequest,
    logger: any ControlCoreLogger
  ) async throws -> ProfileResult {
    let recordArguments = recordArguments(template: configuration.template, timeLimit: configuration.timeLimit, udid: udid, process: process, outputPath: tracePath)
    do {
      try await record(xctrace: xctrace, arguments: recordArguments, environment: environment, stop: stop, logger: logger)
    } catch let ProfileError.toolFailed(tool, exitCode, output) {
      guard case let .attach(pid) = process else {
        throw ProfileError.toolFailed(tool: tool, exitCode: exitCode, stderr: output)
      }
      // xctrace says only that it can't find the process, which doesn't tell one that exited from one it can't see.
      throw ProfileError.toolFailed(tool: tool, exitCode: exitCode, stderr: output + "\n" + runningState(of: pid))
    }

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
  private static func recordEnvironment(deviceSetPath: String?) async throws -> [String: String] {
    guard let deviceSetPath else {
      return [:]
    }
    let shim = try await XCTestShimConfiguration.sharedShimConfiguration()
    return ["SIM_DEVICE_SET_PATH": deviceSetPath, "DYLD_INSERT_LIBRARIES": shim.macOSTestShimPath]
  }

  private static func record(xctrace: String, arguments: [String], environment: [String: String], stop: ProfileStopRequest, logger: any ControlCoreLogger) async throws {
    logger.log("Recording with xctrace \(CollectionInformation.oneLineDescription(from: arguments))")
    let stdout = FBDataBuffer.accumulatingBuffer()
    let stderr = FBDataBuffer.accumulatingBuffer()
    let subprocess = Subprocess(executable: xctrace, arguments: arguments, environment: .additions(environment))
    let (processIdentifier, status) = try await subprocess.withRunning(output: .consumer(stdout), error: .consumer(stderr), logger: logger) { running in
      (running.processIdentifier, try await recordUntilStopped(running, stop: stop))
    }
    // xctrace reports why a recording failed on stdout, alongside its progress.
    try check(tool: "xctrace", processIdentifier: processIdentifier, status: status, output: [stdout.data(), stderr.data()])
  }

  private static func runningState(of pid: pid_t) -> String {
    // EPERM means the process exists but belongs to another user.
    let running = kill(pid, 0) == 0 || errno == EPERM
    return "Process \(pid) was \(running ? "still" : "no longer") running when xctrace exited."
  }

  private static func recordUntilStopped(_ running: RunningSubprocess, stop: ProfileStopRequest) async throws -> TerminationStatus {
    let finished = try await withThrowingTaskGroup(of: TerminationStatus?.self) { group in
      group.addTask { try await running.terminationStatus }
      group.addTask {
        try await stop.wait()
        return nil
      }
      guard let first = try await group.next() else {
        preconditionFailure("The task group has two children; next() cannot be empty")
      }
      group.cancelAll()
      return first
    }
    if let finished {
      return finished
    }
    // SIGINT is xctrace's Ctrl-C: it stops recording and saves the trace.
    return await running.terminate(with: SIGINT, gracePeriod: stopTimeout)
  }

  private static func export(xctrace: String, arguments: [String], logger: any ControlCoreLogger) async throws -> Data {
    let stdout = FBDataBuffer.accumulatingBuffer()
    let stderr = FBDataBuffer.accumulatingBuffer()
    let (processIdentifier, status) = try await Subprocess(executable: xctrace, arguments: arguments)
      .withRunning(output: .consumer(stdout), error: .consumer(stderr), logger: logger) { running in
        (running.processIdentifier, try await running.terminationStatus)
      }
    try check(tool: "xctrace", processIdentifier: processIdentifier, status: status, output: [stdout.data(), stderr.data()])
    return stdout.data()
  }

  private static func check(tool: String, processIdentifier: pid_t, status: TerminationStatus, output: [Data]) throws {
    switch status {
    case .exited(0):
      return
    case let .exited(exitCode):
      let text = output.map { String(decoding: $0, as: UTF8.self) }.joined(separator: "\n")
      throw ProfileError.toolFailed(tool: tool, exitCode: exitCode, stderr: text)
    case let .signalled(signal):
      throw ProcessTerminationError.exitedWithSignal(processIdentifier: processIdentifier, processName: tool, signal: signal)
    }
  }
}
