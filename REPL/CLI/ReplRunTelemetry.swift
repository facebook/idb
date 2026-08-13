/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionUtilities
import Foundation

/// How the REPL is being driven for this session, recorded as the `mode`
/// normal on every row the session reports.
enum ReplSessionMode: String {
  case oneshot
  case interactive
  case replay
}

/// The phase a REPL call was in when it failed, recorded as the `stage`
/// normal on failure rows so the failure taxonomy is queryable without
/// parsing messages. `connect` covers session establishment; the other
/// stages cover a run's pipeline.
enum ReplRunStage: String {
  case connect
  case compile
  case inject
  case execute
}

enum ReplRunTelemetry {

  /// Typed size metrics for a block of code: its character count and its
  /// significant line count.
  static func codeMetrics(_ code: String) -> [String: Int] {
    [
      "code_size": code.count,
      "code_lines": ReplSourceMetadata.countSignificantLinesOfCode(in: code),
    ]
  }

  /// Builds the terminal subject for a timed call (`nil` failure means
  /// success). Failure subjects record the stage the call failed in;
  /// success subjects never carry a stage.
  static func subject(
    name: String,
    start: Date,
    arguments: [String] = [],
    ints: [String: Int] = [:],
    failure: String?,
    stage: ReplRunStage? = nil,
    now: Date = Date()
  ) -> FBEventReporterSubject {
    let duration = now.timeIntervalSince(start)
    guard let failure else {
      return FBEventReporterSubject(
        forSuccessfulCall: name,
        duration: duration,
        size: nil,
        arguments: arguments,
        ints: ints)
    }
    var normals = [String: String]()
    if let stage {
      normals["stage"] = stage.rawValue
    }
    return FBEventReporterSubject(
      forFailingCall: name,
      duration: duration,
      message: failure,
      size: nil,
      arguments: arguments,
      normals: normals,
      ints: ints)
  }
}
