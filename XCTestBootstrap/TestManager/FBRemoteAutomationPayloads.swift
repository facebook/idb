/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
import Foundation

/// The `XCPointerEventPath` selectors the write path drives. The concrete class is runtime-loaded
/// from `XCTest.framework` and relocated per Xcode, so it is constructed by name in
/// `FBRemoteAutomationRuntime` and messaged here through this protocol. `XCTestPrivate` is
/// deliberately not imported into this module's Swift: naming the concrete `XC*` classes emits an
/// `_OBJC_CLASS_$_` reference that is undefined at link, since those classes are never linked.
@objc private protocol XCPointerEventPathMessaging {
  @objc(pressDownAtOffset:)
  func pressDown(atOffset offset: Double)
  @objc(moveToPoint:atOffset:)
  func move(toPoint point: CGPoint, atOffset offset: Double)
  @objc(liftUpAtOffset:)
  func liftUp(atOffset offset: Double)
}

/// A single pointer's path through a synthesized event, wrapping the runtime-loaded
/// `XCPointerEventPath`. Offsets are seconds relative to the start of the event.
///
/// Instances are produced by `pathForTouch(atX:y:)` and assembled into a record by
/// `FBRemoteAutomationPayloads`, keeping construction of the private event class in
/// `FBRemoteAutomationRuntime` and letting the caller compose gestures without naming it.
public final class FBRemoteAutomationPointerPath {

  fileprivate let path: AnyObject

  private var messaging: XCPointerEventPathMessaging {
    unsafeBitCast(path, to: XCPointerEventPathMessaging.self)
  }

  private init(path: AnyObject) {
    self.path = path
  }

  /// A path beginning at a touch point.
  ///
  /// - Throws: if `XCPointerEventPath` is unavailable.
  public static func pathForTouch(atX x: Double, y: Double) throws -> FBRemoteAutomationPointerPath {
    let path = try FBRemoteAutomationRuntime.pointerEventPath(forTouchAtX: x, y: y)
    return FBRemoteAutomationPointerPath(path: path as AnyObject)
  }

  public func pressDown(atOffset offset: Double) {
    messaging.pressDown(atOffset: offset)
  }

  public func move(toX x: Double, y: Double, atOffset offset: Double) {
    messaging.move(toPoint: CGPoint(x: x, y: y), atOffset: offset)
  }

  public func liftUp(atOffset offset: Double) {
    messaging.liftUp(atOffset: offset)
  }
}

/// Builders for the runtime-loaded payload classes used by the remote-automation read and write
/// paths. The returned `Any` values are opaque `XCSynthesizedEventRecord` / `XCAccessibilityElement`
/// instances passed straight back to `FBRemoteAutomationSession`.
public enum FBRemoteAutomationPayloads {

  /// The application accessibility root for a process, or nil if `XCAccessibilityElement` is
  /// unavailable. Passed to `_XCTD_fetchAttributes:forElement:` to walk the tree.
  public static func applicationElement(forProcessIdentifier processIdentifier: Int32) -> Any? {
    try? FBRemoteAutomationRuntime.applicationElement(forProcessIdentifier: processIdentifier)
  }

  /// An `XCSynthesizedEventRecord` composed of the given pointer paths. Submitted via
  /// `_XCTD_synthesizeEvent:implicitConfirmationInterval:`.
  ///
  /// - Throws: if `XCSynthesizedEventRecord` is unavailable.
  public static func eventRecord(withName name: String, pointerPaths: [FBRemoteAutomationPointerPath]) throws -> Any {
    try FBRemoteAutomationRuntime.synthesizedEventRecord(withName: name, pointerPaths: pointerPaths.map(\.path))
  }
}
