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
}
