/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBProfilingCore
import Foundation
import Testing

private func fixture(_ path: String) throws -> Data {
  try Data(contentsOf: URL(fileURLWithPath: path))
}

private func frames(_ value: TraceValue) -> [ProfileFrame] {
  guard case let .backtrace(frames) = value else { return [] }
  return frames
}

@Suite
struct XctraceExportParserTests {

  @Test
  func tableOfContentsReadsTheRunSummary() throws {
    let runs = try XctraceExportParser.runs(fromTableOfContents: fixture(TestFixtures.probeXctraceTableOfContentsPath))

    let run = try #require(runs.first)
    #expect(runs.count == 1)
    #expect(run.number == 1)
    #expect(run.templateName == "Time Profiler")
    #expect(run.durationSeconds == 5.666322)
    #expect(run.endReason == "Time limit reached")
    #expect(run.processes.map(\.name) == ["kernel", "Probe"])
    #expect(run.processes.last?.pid == 83644)
    #expect(run.schemas.count == 27)
    #expect(run.schemas.first == "potential-hangs")
    #expect(run.schemas.contains("time-profile"))
  }

  @Test
  func tableReadsColumnsAndDisplayedValues() throws {
    let table = try XctraceExportParser.table(from: fixture(TestFixtures.probeXctraceTimeProfilePath))

    #expect(table.schema == "time-profile")
    #expect(table.columns.map(\.mnemonic) == ["time", "thread", "process", "core", "thread-state", "weight", "stack"])
    #expect(table.columns.last?.engineeringType == "tagged-backtrace")
    #expect(table.rowCount == 60)
    #expect(table.rows.count == 60)
    #expect(
      table.rows[0].prefix(6) == [
        .text("00:00.361.577"),
        .text("Main Thread (0x17964b) (Probe, pid: 83644)"),
        .text("Probe (83644)"),
        .text("CPU 11 ((null) Core)"),
        .text("Running"),
        .text("1.00 ms"),
      ])
  }

  @Test
  func tableResolvesRefsToEarlierValues() throws {
    let table = try XctraceExportParser.table(from: fixture(TestFixtures.probeXctraceTimeProfilePath))

    // Row 0's process is a child of its thread, and row 1 refers to both.
    #expect(table.rows[1][1] == .text("Main Thread (0x17964b) (Probe, pid: 83644)"))
    #expect(table.rows[1][2] == .text("Probe (83644)"))
    // Row 11's backtrace is a ref to row 9's.
    #expect(frames(table.rows[11][6]).count > 0)
    #expect(table.rows[11][6] == table.rows[9][6])
  }

  @Test
  func backtracesAreInnermostFirstWithTheirBinaries() throws {
    let table = try XctraceExportParser.table(from: fixture(TestFixtures.probeXctraceTimeProfilePath))

    let stack = frames(table.rows[0][6])
    #expect(stack.count == 15)
    #expect(stack[0] == ProfileFrame(symbol: "swift_retain", binary: "libswiftCore.dylib"))
    #expect(stack[1] == ProfileFrame(symbol: "closure #1 in AppDelegate.application(_:didFinishLaunchingWithOptions:)", binary: "Probe"))
    // This frame's binary is a ref to the frame before's.
    #expect(stack[2].binary == "Probe")
    let everyFrame = table.rows.flatMap { frames($0[6]) }
    #expect(everyFrame.allSatisfy { !$0.symbol.isEmpty })
  }

  @Test
  func rowLimitCountsButDropsLaterRows() throws {
    let table = try XctraceExportParser.table(from: fixture(TestFixtures.probeXctraceTimeProfilePath), rowLimit: 5)

    #expect(table.rowCount == 60)
    #expect(table.rows.count == 5)
  }

  @Test
  func potentialHangsReadsTheHang() throws {
    let table = try XctraceExportParser.table(from: fixture(TestFixtures.probeXctracePotentialHangsPath))

    #expect(table.schema == "potential-hangs")
    #expect(table.rows.count == 1)
    #expect(table.rows[0][1] == .text("2.02 s"))
    #expect(table.rows[0][2] == .text("Severe Hang"))
    #expect(table.rows[0][4] == .text("Probe (83644)"))
  }

  @Test
  func valuesEncodeAsPlainJSON() throws {
    let values: [TraceValue] = [.empty, .text("1.00 ms"), .backtrace([ProfileFrame(symbol: "main", binary: "Probe")])]

    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let json = try String(decoding: encoder.encode(values), as: UTF8.self)

    #expect(json == #"[null,"1.00 ms",[{"binary":"Probe","symbol":"main"}]]"#)
    #expect(try JSONDecoder().decode([TraceValue].self, from: Data(json.utf8)) == values)
  }

  @Test
  func exportWithoutATableThrows() {
    #expect(throws: ProfileReportParseError.missingSection(tool: "xctrace", section: "table schema")) {
      try XctraceExportParser.table(from: Data("<trace-query-result/>".utf8))
    }
  }
}
