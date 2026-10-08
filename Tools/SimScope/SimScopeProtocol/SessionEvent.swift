/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// Who originated an event.
public enum EventSource: String, Codable, Sendable {
  case human // the person driving the SimScope UI
  case agent // an external agent, over the control channel
  case replay // SimScope re-issuing recorded actions ("repeat after me")
  case system // SimScope itself (session lifecycle, notes)
}

/// A structured, replayable description of an action. Coordinates are simulator screen points.
public enum SessionAction: Codable, Equatable, Sendable {
  case tap(x: Double, y: Double)
  case swipe(fromX: Double, fromY: Double, toX: Double, toY: Double)
  case type(String) // typed text
  case key(String) // a named control key: "return" / "tab" / "escape"
  case device(String) // a hardware/device action: home/side/lock/siri/applePay/playPause/shake
  case chat(String) // a message on the human↔agent channel
  case note(String) // freeform annotation / session marker
  case inject(code: String, bundleID: String) // Swift compiled into a live app process

  /// Whether this is something the human said, as distinct from something they did.
  public var isChat: Bool {
    if case .chat = self { return true }
    return false
  }

  /// Whether this action can be re-issued to the simulator (for "repeat after me").
  ///
  /// An injection is not, even though re-running a snippet is a sensible thing to want: "repeat after
  /// me" replays touches through `SimBackend`, which has nothing that compiles. Re-running a session's
  /// snippets is `idb-repl replay` against the report `SessionREPL` writes.
  public var isReplayable: Bool {
    switch self {
    case .tap, .swipe, .type, .key, .device: return true
    case .chat, .note, .inject: return false
    }
  }
}

/// One entry in the session timeline: an action, who did it, when, and its agent-readable prose.
public struct SessionEvent: Codable, Equatable, Sendable {
  public let time: TimeInterval // seconds since the session started
  public let source: EventSource
  public let action: SessionAction
  public let prose: String
  public let element: String? // the acted-on element's phrase, when known

  public init(time: TimeInterval, source: EventSource, action: SessionAction, prose: String, element: String?) {
    self.time = time
    self.source = source
    self.action = action
    self.prose = prose
    self.element = element
  }
}
