/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

// patternlint-disable avoid-print-to-prevent-production-overhead

import Foundation
import SimScopeProtocol

/// How a reply reads on a terminal. Prose rather than JSON by default, because the caller is usually
/// an agent reading its own scrollback, and the app has already phrased everything it knows.
enum Render {

  /// `--json` output. Sorted keys so a diff between two runs is a diff in the device, not in Foundation.
  static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return encoder
  }()

  static func status(_ status: AgentStatus) {
    print(
      """
      \(status.device) (\(status.udid))
        screen \(round(status.screenWidth)) x \(round(status.screenHeight)) points
        \(status.eventCount) events on the timeline
        session bundle: \(recording(status.recording))
        window recording: \(recording(status.windowRecording))
      """)
  }

  static func element(_ element: AgentElement) -> String {
    let indent = String(repeating: "  ", count: min(element.depth, 8))
    let label = element.label ?? element.identifier ?? ""
    let value = element.value.map { "  = \($0)" } ?? ""
    let tap = element.tapX.map { x in "  tap (\(round(x)), \(round(element.tapY ?? 0)))" } ?? ""
    // The semantic traversal cannot satisfy `type` — the translator vocabulary has no class-name
    // attribute — so a row there is a label and a point and nothing else. Printing a placeholder for
    // every element on that path is noise pretending to be data; omit it and let the row be short.
    let role = element.type.map { "\($0) " } ?? ""
    return "\(indent)\(role)“\(label)”\(value)\(tap)"
  }

  static func event(_ event: SessionEvent) -> String {
    "[\(event.source.rawValue.padding(toLength: 6, withPad: " ", startingAt: 0))] \(event.prose)"
  }

  static func recording(_ state: AgentRecordingState) {
    if state.active {
      print("recording to \(state.path ?? "an unnamed file")")
    } else if let path = state.path {
      print("stopped — the recording is at \(path)")
    } else {
      print("nothing was recording")
    }
  }

  private static func recording(_ active: Bool) -> String {
    active ? "recording" : "not recording"
  }

  /// Points, to the pixel the human would read off the window.
  private static func round(_ value: Double) -> String {
    String(Int(value.rounded()))
  }
}
