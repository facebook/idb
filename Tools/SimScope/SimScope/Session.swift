/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
import Foundation
import SimScopeProtocol

/// The single event bus every action funnels through. Observers (the action-log pane, the recorder,
/// the simulator view's touch feedback, and the agent control channel) subscribe; recording, replay,
/// and the transcript all read from the one timeline.
@MainActor
final class Session {

  private(set) var events: [SessionEvent] = []
  private let start = Date()
  private var observers: [(SessionEvent) -> Void] = []

  /// Subscribe to every recorded event (replayed the backlog is *not* — observers see events from now on).
  func observe(_ callback: @escaping (SessionEvent) -> Void) {
    observers.append(callback)
  }

  func record(source: EventSource, action: SessionAction, prose: String, element: String? = nil) {
    let event = SessionEvent(
      time: Date().timeIntervalSince(start), source: source, action: action, prose: prose, element: element)
    events.append(event)
    for observer in observers { observer(event) }
  }

  // MARK: - Convenience recorders (also build the prose)

  func recordTap(source: EventSource, hit: AXHit?, at point: CGPoint) {
    record(
      source: source, action: .tap(x: Double(point.x), y: Double(point.y)),
      prose: Prose.tap(hit: hit, at: point), element: hit?.phrase)
  }

  func recordSwipe(source: EventSource, from start: CGPoint, to end: CGPoint, startHit: AXHit?) {
    record(
      source: source,
      action: .swipe(fromX: Double(start.x), fromY: Double(start.y), toX: Double(end.x), toY: Double(end.y)),
      prose: Prose.swipe(from: start, to: end, startHit: startHit), element: startHit?.phrase)
  }

  func recordType(source: EventSource, _ text: String) {
    record(source: source, action: .type(text), prose: "Typed “\(text)”.")
  }

  func recordKey(source: EventSource, named name: String) {
    record(source: source, action: .key(name), prose: "Pressed \(name.capitalized).")
  }

  func recordDevice(source: EventSource, name: String, prose: String) {
    record(source: source, action: .device(name), prose: prose)
  }

  func recordChat(source: EventSource, _ text: String) {
    record(source: source, action: .chat(text), prose: text)
  }

  func recordNote(_ text: String) {
    record(source: .system, action: .note(text), prose: text)
  }
}

/// Agent-readable prose for actions — the same phrasing used across the log, transcript, and channel.
enum Prose {
  static func tap(hit: AXHit?, at point: CGPoint) -> String {
    if let hit { return "Tapped the \(hit.phrase) at \(pointString(point))." }
    return "Tapped at \(pointString(point)) (no accessibility element there)."
  }

  static func swipe(from start: CGPoint, to end: CGPoint, startHit: AXHit?) -> String {
    let path = "from \(pointString(start)) to \(pointString(end))"
    if let startHit { return "Swiped \(direction(from: start, to: end)) \(path), starting on the \(startHit.phrase)." }
    return "Swiped \(direction(from: start, to: end)) \(path)."
  }

  static func pointString(_ p: CGPoint) -> String {
    "(\(Int(p.x.rounded())), \(Int(p.y.rounded())))"
  }

  private static func direction(from a: CGPoint, to b: CGPoint) -> String {
    let dx = b.x - a.x
    let dy = b.y - a.y
    if abs(dx) >= abs(dy) { return dx >= 0 ? "right" : "left" }
    return dy >= 0 ? "down" : "up" // simulator points are top-left origin
  }
}
