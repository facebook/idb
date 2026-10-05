/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// What a failed simulator operation says about trying again.
///
/// Classification exists so that callers outside this module do not match on message text. A
/// substring match reads "failed to fork" or an app's own logging as a missing capability, and the
/// consequence of getting that wrong is a hinge-capable simulator permanently mislabelled.
public enum SimulatorFailureKind: Equatable, Sendable {
  /// The device, its runtime or the toolchain driving it lacks `capability` altogether. Retrying cannot
  /// help, and a caller may stop offering it.
  case unsupported(capability: String)
  /// The simulator is not yet in a state that can answer: a service still starting, a display transition,
  /// or a configuration that moved under the operation. The same request may succeed shortly.
  case notReady
  /// The attempt failed, or the request was wrong. Neither says anything about what the device can do.
  case failed

  /// Errors from outside this module are `.failed`, as is an unsupported case carrying no detail: a caller
  /// told to stop offering something cannot act on, or explain, a blank reason.
  public init(_ error: any Error) {
    guard let error = error as? any SimulatorFailureClassifying else {
      self = .failed
      return
    }
    switch error.failureKind {
    case let .unsupported(capability) where capability.isEmpty: self = .failed
    case let kind: self = kind
    }
  }
}

/// Not public: conforming error types this module has never seen would move the permanent-versus-transient
/// judgement out of it, and it is a transient failure answering "permanently missing" that retires a
/// working device for good.
protocol SimulatorFailureClassifying: Error {
  var failureKind: SimulatorFailureKind { get }
}

extension SimulatorDisplayInteractionError: SimulatorFailureClassifying {
  var failureKind: SimulatorFailureKind {
    switch self {
    case let .unsupportedCapability(capability): .unsupported(capability: capability)
    // The display exists and the request was answerable; it was the request that was wrong.
    case .inactiveDisplay, .missingMapping, .invalidPoint, .nonFinitePoint: .failed
    }
  }
}

extension SimulatorCoreDeviceError: SimulatorFailureClassifying {
  var failureKind: SimulatorFailureKind {
    switch self {
    case let .unsupported(detail): .unsupported(capability: detail)
    // A service that is missing or slow while the simulator boots may answer later.
    case .unavailable, .timedOut: .notReady
    case .malformed: .failed
    }
  }
}

extension SimulatorDisplayError: SimulatorFailureClassifying {
  var failureKind: SimulatorFailureKind {
    switch self {
    case .changed, .transitioning, .noActiveIntegratedDisplay, .ambiguousActiveDisplays, .screensNotReported: .notReady
    }
  }
}

extension SimulatorPoseConfirmationError: SimulatorFailureClassifying {
  var failureKind: SimulatorFailureKind {
    switch self {
    // The simulator answered, with a pose other than the one requested.
    case .notReached: .failed
    }
  }
}

/// The capability a failure says is missing, or `nil` when it says nothing of the kind.
public func unsupportedSimulatorCapability(in error: any Error) -> String? {
  guard case let .unsupported(capability) = SimulatorFailureKind(error) else { return nil }
  return capability
}
