/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionUtilities
import Foundation
import Testing

/// Tests the typed telemetry the REPL reports for sessions and runs.
@Suite
struct ReplRunTelemetryTests {

  // MARK: - codeMetrics

  @Test
  func codeMetricsCarryCharacterAndSignificantLineCounts() {
    let code = "let x = 1\n\n// comment only\nprint(x)"
    let metrics = ReplRunTelemetry.codeMetrics(code)
    #expect(metrics["code_size"] == code.count)
    #expect(metrics["code_lines"] == 2)
  }

  // MARK: - subject

  @Test
  func successSubjectCarriesIntsAndNoStage() {
    let start = Date(timeIntervalSince1970: 1000)
    let now = Date(timeIntervalSince1970: 1002)
    let subject = ReplRunTelemetry.subject(
      name: "run",
      start: start,
      arguments: ["size=9"],
      ints: ["code_size": 9, "code_lines": 1],
      failure: nil,
      stage: nil,
      now: now)
    #expect(subject.eventName == "run")
    #expect(subject.eventType == .success)
    #expect(subject.duration == NSNumber(value: 2000))
    #expect(subject.arguments == ["size=9"])
    #expect(subject.ints == ["code_size": 9, "code_lines": 1])
    #expect(subject.normals.isEmpty)
  }

  @Test
  func failureSubjectCarriesStageNormalAndMessage() {
    let start = Date(timeIntervalSince1970: 1000)
    let subject = ReplRunTelemetry.subject(
      name: "run",
      start: start,
      ints: ["code_size": 9],
      failure: "compiler exploded",
      stage: .compile,
      now: Date(timeIntervalSince1970: 1001))
    #expect(subject.eventType == .failure)
    #expect(subject.message == "compiler exploded")
    #expect(subject.normals == ["stage": "compile"])
    #expect(subject.ints == ["code_size": 9])
  }

  @Test
  func failureSubjectWithoutStageCarriesNoStageNormal() {
    let subject = ReplRunTelemetry.subject(
      name: "session_end",
      start: Date(timeIntervalSince1970: 1000),
      failure: "torn down uncleanly",
      now: Date(timeIntervalSince1970: 1001))
    #expect(subject.normals.isEmpty)
  }

  @Test
  func modeAndStageWireValuesArePinned() {
    // These raw values are the strings written to the mode/stage columns;
    // renaming a case must not silently rename the column value.
    #expect(ReplSessionMode.oneshot.rawValue == "oneshot")
    #expect(ReplSessionMode.interactive.rawValue == "interactive")
    #expect(ReplSessionMode.replay.rawValue == "replay")
    #expect(ReplRunStage.connect.rawValue == "connect")
    #expect(ReplRunStage.compile.rawValue == "compile")
    #expect(ReplRunStage.inject.rawValue == "inject")
    #expect(ReplRunStage.execute.rawValue == "execute")
  }
}
