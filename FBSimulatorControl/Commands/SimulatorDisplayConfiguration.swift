/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// A simulator's displays, numbered so that a consumer can tell whether anything that maps touches or
/// shapes frames has changed since it last looked.
public struct SimulatorDisplayConfiguration: Equatable, Sendable {

  public enum Phase: Equatable, Sendable {
    case settled
    /// Layout has moved to a display whose backlight has not caught up, as during a hinge change.
    /// `displays` and `active` are the outgoing configuration, and input should wait for `.settled`.
    case transitioning
  }

  /// The display interactions target: the sole integrated display, or the active one of several.
  public enum ActiveDisplay: Equatable, Sendable {
    case identified(SimulatorDisplay)
    /// The sole integrated display of a runtime that does not identify its displays.
    case unidentified(SimulatorDisplayGeometry)
    /// No integrated display is active, or several are. A later configuration may settle on one.
    case unresolved
    /// The runtime cannot say which display interactions target: it reports an integrated display's activity
    /// as `unknown`, or several integrated displays without identifying them.
    case unknown
  }

  /// Increases whenever a display appears or disappears, or any display's activity or geometry changes,
  /// including its interface rotation. A transition that settles back where it started keeps its generation.
  /// Generations are per simulator, start at 1, and may skip values. A change reverted before anything reads
  /// the displays goes unnumbered unless a `configurations()` stream is following them.
  public let generation: UInt64
  /// Every identified display. Empty on runtimes that do not identify their displays.
  public let displays: [SimulatorDisplay]
  public let active: ActiveDisplay
  public let phase: Phase

  /// The identified display interactions target, or why the configuration has none.
  public func activeDisplay() throws -> SimulatorDisplay {
    switch try settledActive() {
    case let .identified(display):
      return display
    case .unidentified:
      throw SimulatorDisplayInteractionError.unsupportedCapability("an identified integrated display")
    case .unresolved:
      throw unresolved
    case .unknown:
      throw SimulatorDisplayInteractionError.unsupportedCapability("one active integrated display")
    }
  }

  /// The geometry of the display interactions target, whether or not the runtime identifies it.
  public func activeGeometry() throws -> SimulatorDisplayGeometry {
    switch try settledActive() {
    case let .identified(display):
      return display.geometry
    case let .unidentified(geometry):
      return geometry
    case .unresolved:
      throw unresolved
    case .unknown:
      throw SimulatorDisplayInteractionError.unsupportedCapability("one integrated display")
    }
  }

  private func settledActive() throws -> ActiveDisplay {
    switch phase {
    case .settled: active
    case .transitioning: throw SimulatorDisplayError.transitioning
    }
  }

  private var unresolved: SimulatorDisplayError {
    let identities = displays.filter { $0.isIntegrated && $0.isActive }.map(\.uniqueID)
    return identities.isEmpty ? .noActiveIntegratedDisplay : .ambiguousActiveDisplays(identities)
  }
}

/// Assigns generations to display reports. Every read of a simulator's displays passes through one tracker,
/// so all readers agree on the generation of a configuration.
// SAFETY: Every access to the stored configuration holds the lock.
// patternlint-disable-next-line unchecked-sendable
final class DisplayConfigurationTracker: @unchecked Sendable {
  private let lock = NSLock()
  private var current: (configuration: SimulatorDisplayConfiguration, basis: [SimulatorInteractionDisplay])?
  let follower = DisplayConfigurationFollower()

  /// The most recently observed configuration, if any read has succeeded.
  var latest: SimulatorDisplayConfiguration? {
    lock.lock()
    defer { lock.unlock() }
    return current?.configuration
  }

  /// Throws a failed read's error, which says nothing about the configuration.
  func observe(_ report: SimulatorDisplayReport) throws -> SimulatorDisplayConfiguration {
    try observation(of: report).configuration.get()
  }

  /// Where interactions route for `report`, numbered alongside its configuration. A failed read falls back to the
  /// main display rather than throwing.
  func resolution(of report: SimulatorDisplayReport) -> SimulatorDisplayResolution {
    observation(of: report).resolution
  }

  private func observation(
    of report: SimulatorDisplayReport
  ) -> (configuration: Result<SimulatorDisplayConfiguration, SimulatorCoreDeviceError>, resolution: SimulatorDisplayResolution) {
    let resolution = SimulatorDisplayResolution(report)
    lock.lock()
    defer { lock.unlock() }
    switch report {
    case let .failed(error):
      return (.failure(error), resolution)
    case .transitioning:
      guard let current else {
        return (.success(SimulatorDisplayConfiguration(generation: 1, displays: [], active: .unresolved, phase: .transitioning)), resolution)
      }
      let previous = current.configuration
      return (
        .success(
          SimulatorDisplayConfiguration(
            generation: previous.generation, displays: previous.displays, active: previous.active, phase: .transitioning)),
        resolution
      )
    case let .displays(displays):
      return (.success(settle(displays: displays, basis: displays.map { .identified($0) }, active: Self.active(in: resolution))), resolution)
    case let .legacy(integrated):
      return (.success(settle(displays: [], basis: integrated.map { .legacy($0) }, active: Self.active(in: resolution))), resolution)
    }
  }

  private func settle(
    displays: [SimulatorDisplay], basis: [SimulatorInteractionDisplay], active: SimulatorDisplayConfiguration.ActiveDisplay
  ) -> SimulatorDisplayConfiguration {
    let generation: UInt64 =
      switch current {
      case nil: 1
      case let (previous, previousBasis)?:
        previousBasis.count == basis.count && zip(previousBasis, basis).allSatisfy { $0.hasSameConfiguration(as: $1) }
          ? previous.generation : previous.generation + 1
      }
    let configuration = SimulatorDisplayConfiguration(generation: generation, displays: displays, active: active, phase: .settled)
    current = (configuration, basis)
    return configuration
  }

  /// Only called for reports that list displays, so neither an unreadable report nor a transition reaches here.
  private static func active(in resolution: SimulatorDisplayResolution) -> SimulatorDisplayConfiguration.ActiveDisplay {
    switch resolution {
    case let .target(.selected(display)), let .target(.sole(.identified(display))): .identified(display)
    case let .target(.sole(.legacy(geometry))): .unidentified(geometry)
    case .fallback(.noActiveIntegratedDisplay), .fallback(.ambiguousActiveDisplays), .transitioning: .unresolved
    case .fallback(.legacyIntegratedDisplays), .fallback(.unknownActivity), .fallback(.unreadable): .unknown
    }
  }
}
