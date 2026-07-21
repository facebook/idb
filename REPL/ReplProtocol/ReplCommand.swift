/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
import Foundation

/// The wire model for a REPL host command. Injected code (through the `IDB`
/// module) encodes one of these and the companion's `HostCommandDispatcher`
/// decodes it. Sharing this single `Codable` type across both sides makes the
/// request contract type-checked end-to-end -- instead of stringly-typed JSON
/// keys read with `as? Double` -- and lets the dispatcher switch exhaustively, so
/// adding a command is a compile-time change on both sides.
public enum ReplCommand: Codable, Sendable {
  case tap(CGPoint)
  case tapMarker(String)
  case swipe(from: CGPoint, to: CGPoint, duration: Double, delta: Double)
  case pinch(at: CGPoint, scale: Double, duration: Double, radius: Double)
  case button(String)
  case text(String)
  case touchDown(CGPoint)
  case touchMove(CGPoint)
  case touchUp(CGPoint)
  case describeAll
  case screenshot(area: ScreenshotArea, output: ScreenshotOutput)
  case startRecording
  case stopRecording
}

/// The area of the screen a screenshot should capture.
public enum ScreenshotArea: Codable, Sendable {
  /// The whole screen.
  case full
  /// A rectangle in screen points (the same coordinate space as `tap`).
  case rect(CGRect)
  /// The frontmost-app accessibility element whose label contains `label` (the
  /// same lookup as `tapMarker`); its frame is captured.
  case element(label: String)
}

/// How a captured screenshot is returned.
public enum ScreenshotOutput: Codable, Sendable {
  /// Return the encoded image bytes to injected code; nothing is written to disk.
  case data
  /// Write the image to a PNG file on the companion and return its path.
  case file
}
