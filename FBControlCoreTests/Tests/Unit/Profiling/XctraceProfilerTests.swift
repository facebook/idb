/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBControlCore
import Foundation
import Testing

@Suite
struct XctraceProfilerTests {

  private static let udid = "B8169862-96E1-4841-B6D0-B1231442D766"

  @Test
  func recordAttachesToAProcess() {
    let arguments = XctraceProfiler.recordArguments(template: "Time Profiler", timeLimit: .seconds(5), udid: Self.udid, process: .attach(42), outputPath: "/tmp/a.trace")

    #expect(arguments == ["record", "--template", "Time Profiler", "--device", Self.udid, "--output", "/tmp/a.trace", "--time-limit", "5000ms", "--no-prompt", "--attach", "42"])
  }

  @Test
  func recordLaunchesWithTheBundleIDLast() {
    let arguments = XctraceProfiler.recordArguments(template: "Hangs", timeLimit: .milliseconds(1500), udid: Self.udid, process: .launch(bundleID: "com.example.app"), outputPath: "/tmp/a.trace")

    #expect(arguments.suffix(3) == ["--launch", "--", "com.example.app"])
    #expect(arguments.contains("1500ms"))
  }

  @Test
  func recordAllProcesses() {
    let arguments = XctraceProfiler.recordArguments(template: "Time Profiler", timeLimit: .seconds(1), udid: Self.udid, process: .allProcesses, outputPath: "/tmp/a.trace")

    #expect(arguments.last == "--all-processes")
    #expect(!arguments.contains("--attach"))
  }

  @Test(arguments: [(Duration.microseconds(400), "1ms"), (.microseconds(1500), "2ms"), (.zero, "1ms")])
  func aTimeLimitRoundsUpToWholeMilliseconds(timeLimit: Duration, expected: String) throws {
    let arguments = XctraceProfiler.recordArguments(template: "Time Profiler", timeLimit: timeLimit, udid: Self.udid, process: .allProcesses, outputPath: "/tmp/a.trace")

    let index = try #require(arguments.firstIndex(of: "--time-limit"))
    #expect(arguments[index + 1] == expected)
  }

  @Test
  func defaultSchemasComeFromTheTemplate() throws {
    let run = try #require(XctraceExportParser.runs(fromTableOfContents: Data(contentsOf: URL(fileURLWithPath: TestFixtures.probeXctraceTableOfContentsPath))).first)

    #expect(try XctraceProfiler.schemas(requested: nil, template: "Time Profiler", available: run.schemas) == ["time-profile"])
    #expect(try XctraceProfiler.schemas(requested: nil, template: "Hangs", available: run.schemas) == ["potential-hangs"])
    #expect(try XctraceProfiler.schemas(requested: nil, template: "Allocations", available: run.schemas) == [])
  }

  @Test
  func defaultSchemasTheTraceLacksAreSkipped() throws {
    #expect(try XctraceProfiler.schemas(requested: nil, template: "Time Profiler", available: ["potential-hangs"]) == [])
  }

  @Test
  func aRequestedSchemaTheTraceLacksThrows() {
    #expect(throws: ProfileError.traceSchemaMissing(schema: "time-sample", available: ["time-profile"])) {
      try XctraceProfiler.schemas(requested: ["time-profile", "time-sample"], template: "Time Profiler", available: ["time-profile"])
    }
  }

  @Test
  func xpathSelectsTheTableInTheTableOfContents() throws {
    let document = try XMLDocument(data: Data(contentsOf: URL(fileURLWithPath: TestFixtures.probeXctraceTableOfContentsPath)))

    let nodes = try document.nodes(forXPath: XctraceProfiler.xpath(run: 1, schema: "time-profile"))

    #expect(nodes.count == 1)
    #expect((nodes.first as? XMLElement)?.attribute(forName: "schema")?.stringValue == "time-profile")
    #expect(try document.nodes(forXPath: XctraceProfiler.xpath(run: 2, schema: "time-profile")).isEmpty)
  }

  @Test
  func stoppingATraceReportsWhatItRecorded() async throws {
    let directory = try FakeXctrace.makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let tracePath = directory.appendingPathComponent("stopped.trace").path
    let configuration = TraceConfiguration(template: "Time Profiler", schemas: nil, timeLimit: .seconds(60), rowLimit: nil, outputPath: tracePath)
    let xctrace = directory.appendingPathComponent("xctrace").path

    let operation = XctraceProfiler.operation(configuration, process: .allProcesses, udid: Self.udid, scratch: TemporaryDirectory(rootDirectory: directory, logger: ControlCoreLoggerDouble()), logger: ControlCoreLoggerDouble()) {
      (xctrace, [:])
    }
    try await FakeXctrace.waitUntilRecording(to: tracePath)
    operation.stop()

    let result = try await operation.result

    guard case let .trace(report) = result.report else {
      Issue.record("Expected a trace report, got \(String(describing: result.report))")
      return
    }
    #expect(report.tables.map(\.schema) == ["time-profile"])
    #expect(FileManager.default.fileExists(atPath: (tracePath as NSString).appendingPathComponent("saved")))
  }

  @Test
  func aTraceWithoutAnOutputPathIsRecordedIntoScratch() async throws {
    let directory = try FakeXctrace.makeDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    // Nothing creates it beforehand, just as nothing creates a simulator's auxillary directory.
    let scratchDirectory = directory.appendingPathComponent("scratch")
    let configuration = TraceConfiguration(template: "Time Profiler", schemas: nil, timeLimit: .milliseconds(100), rowLimit: nil, outputPath: nil)
    let xctrace = directory.appendingPathComponent("xctrace").path

    let operation = XctraceProfiler.operation(configuration, process: .allProcesses, udid: Self.udid, scratch: TemporaryDirectory(rootDirectory: scratchDirectory, logger: ControlCoreLoggerDouble()), logger: ControlCoreLoggerDouble()) {
      (xctrace, [:])
    }

    let result = try await operation.result

    guard case let .trace(report) = result.report else {
      Issue.record("Expected a trace report, got \(String(describing: result.report))")
      return
    }
    #expect(report.tables.map(\.schema) == ["time-profile"])
    #expect(result.artifact == nil)
    #expect(try FileManager.default.contentsOfDirectory(atPath: scratchDirectory.path).isEmpty)
  }
}

/// Stands in for xctrace: `record` creates its output once it is recording, and saves it on SIGINT, as Ctrl-C does, or
/// finishes at the time limit; like xctrace, it exits 40 if it can't create the output. `export` prints the captured
/// Probe app exports.
private enum FakeXctrace {

  static func makeDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("fake-xctrace-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let script = """
      #!/bin/sh
      case "$1" in
      record)
        while [ $# -gt 0 ]; do
          [ "$1" = --output ] && out="$2"
          [ "$1" = --time-limit ] && limit="${2%ms}"
          shift
        done
        trap 'touch "$out/saved"; exit 0' INT
        mkdir "$out" || exit 40
        elapsed=0
        while [ "$elapsed" -lt "$limit" ]; do
          sleep 0.05
          elapsed=$((elapsed + 50))
        done
        ;;
      export)
        case "$*" in
        *--toc*) cat '\(TestFixtures.probeXctraceTableOfContentsPath)' ;;
        *) cat '\(TestFixtures.probeXctraceTimeProfilePath)' ;;
        esac
        ;;
      esac

      """
    let path = directory.appendingPathComponent("xctrace")
    try script.write(to: path, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path.path)
    return directory
  }

  static func waitUntilRecording(to tracePath: String) async throws {
    for _ in 0..<500 where !FileManager.default.fileExists(atPath: tracePath) {
      try await Task.sleep(for: .milliseconds(20))
    }
    try #require(FileManager.default.fileExists(atPath: tracePath), "The fake xctrace never started recording")
  }
}
