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

  /// Increases whenever a display appears or disappears, or any display's activity or geometry changes,
  /// including its interface rotation. A transition that settles back where it started keeps its generation.
  /// Generations are per simulator, start at 1, and may skip values. A change reverted before anything reads
  /// the displays goes unnumbered unless a `configurations()` stream is following them.
  public let generation: UInt64
  /// Every identified display. Empty on runtimes that do not identify their displays.
  public let displays: [SimulatorDisplay]
  /// The display interactions target: the sole integrated display, or the active one of several. Nil when
  /// the runtime cannot name one.
  public let active: SimulatorDisplay?
  public let phase: Phase
}

/// Assigns generations to display reports. Every read of a simulator's displays passes through one tracker,
/// so all readers agree on the generation of a configuration.
// SAFETY: Every access to the stored configuration holds the lock.
// patternlint-disable-next-line unchecked-sendable
final class DisplayConfigurationTracker: @unchecked Sendable {
  private let lock = NSLock()
  private var current: (configuration: SimulatorDisplayConfiguration, basis: [SimulatorInteractionDisplay])?

  /// The most recently observed configuration, if any read has succeeded.
  var latest: SimulatorDisplayConfiguration? {
    lock.lock()
    defer { lock.unlock() }
    return current?.configuration
  }

  /// Throws a failed read's error, which says nothing about the configuration.
  func observe(_ report: SimulatorDisplayReport) throws -> SimulatorDisplayConfiguration {
    lock.lock()
    defer { lock.unlock() }
    switch report {
    case let .failed(error):
      throw error
    case .transitioning:
      guard let current else {
        return SimulatorDisplayConfiguration(generation: 1, displays: [], active: nil, phase: .transitioning)
      }
      let previous = current.configuration
      return SimulatorDisplayConfiguration(
        generation: previous.generation, displays: previous.displays, active: previous.active, phase: .transitioning)
    case let .displays(displays):
      return settle(displays: displays, basis: displays.map { .identified($0) }, active: Self.active(in: report))
    case let .legacy(integrated):
      return settle(displays: [], basis: integrated.map { .legacy($0) }, active: nil)
    }
  }

  private func settle(
    displays: [SimulatorDisplay], basis: [SimulatorInteractionDisplay], active: SimulatorDisplay?
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

  private static func active(in report: SimulatorDisplayReport) -> SimulatorDisplay? {
    switch SimulatorDisplayResolution(report) {
    case let .target(.selected(display)), let .target(.sole(.identified(display))): display
    case .target(.sole(.legacy)), .fallback, .transitioning: nil
    }
  }
}
