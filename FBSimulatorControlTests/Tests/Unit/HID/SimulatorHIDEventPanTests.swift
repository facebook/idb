/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
@testable import FBSimulatorControl
import Foundation
import Testing

/// Coverage of `SimulatorHIDEvent.pan(...)` — the tvOS trackpad pan factory that expands a
/// start→end drag into a phased began → changed×steps → ended gesture with interleaved delays.
@Suite
struct SimulatorHIDEventPanTests {

  @Test
  func panExpandsToPhasedGesture() throws {
    let from = try #require(SimulatorTrackpadPoint(x: 0.5, y: 0.2))
    let to = try #require(SimulatorTrackpadPoint(x: 0.5, y: 0.8))
    let pan = SimulatorHIDEvent.pan(from: from, to: to, steps: 3, duration: 0.3)
    let subs = try #require(pan.subEvents, "pan should be a composite")

    let trackpads: [(SimulatorTrackpadPhase, SimulatorTrackpadPoint)] = subs.compactMap {
      if case let .trackpad(phase, point) = $0 { return (phase, point) }
      return nil
    }

    // began + (steps) changed + ended.
    #expect(trackpads.count == 5, "began + 3 changed + ended")
    #expect(trackpads.first?.0 == .began)
    #expect(trackpads.first?.1 == from, "began at the start point")
    #expect(trackpads.last?.0 == .ended)
    #expect(trackpads.last?.1 == to, "ended at the end point")
    #expect(Array(trackpads[1...3]).map(\.0) == [.changed, .changed, .changed], "interior samples are changed")

    // A delay precedes each changed sample and the ended sample (steps + 1 delays).
    let delays = subs.filter {
      if case .delay = $0 { return true }
      return false
    }
    #expect(delays.count == 4, "steps + 1 interleaved delays")
  }

  // The trackpad surface is absolute-normalized and the type enforces it: screen coordinates
  // cannot be represented as a SimulatorTrackpadPoint, so `pan` cannot be handed them.
  @Test
  func trackpadPointRejectsCoordinatesOutsideTheSurface() throws {
    #expect(SimulatorTrackpadPoint(x: 100, y: 200) == nil, "screen coordinates are not surface coordinates")
    #expect(SimulatorTrackpadPoint(x: 0.5, y: 1.5) == nil, "one axis outside the unit square is enough")
    #expect(SimulatorTrackpadPoint(x: -0.1, y: 0.5) == nil, "and so is a negative one")

    #expect(SimulatorTrackpadPoint(x: 0, y: 0) != nil, "the corners are on the surface")
    #expect(SimulatorTrackpadPoint(x: 1, y: 1) != nil, "including the far one")
  }

  @Test
  func panClampsStepsToAtLeastOne() throws {
    // steps <= 0 must not trap; it degrades to a single changed sample.
    let from = try #require(SimulatorTrackpadPoint(x: 0, y: 0))
    let to = try #require(SimulatorTrackpadPoint(x: 1, y: 1))
    let pan = SimulatorHIDEvent.pan(from: from, to: to, steps: 0, duration: 0.1)
    let trackpads = try #require(pan.subEvents).filter {
      if case .trackpad = $0 { return true }
      return false
    }
    #expect(trackpads.count == 3, "began + 1 changed + ended")
  }
}
