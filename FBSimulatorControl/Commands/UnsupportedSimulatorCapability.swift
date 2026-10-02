/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// A failure that is a fact about the simulator rather than about the attempt: this device, or the
/// toolchain driving it, does not have the capability at all, so retrying cannot help and a caller
/// may safely stop offering it.
///
/// Classification exists so that callers outside this module do not match on message text. A
/// substring match reads "failed to fork" or an app's own logging as a missing capability, and the
/// consequence of getting that wrong is a hinge-capable simulator permanently mislabelled.
///
/// The protocol itself is not part of that API. Outside callers ask
/// `unsupportedSimulatorCapability(in:)`, which is the whole of what they need; conforming their own
/// error types as well would move the permanent-versus-transient judgement to types this module has
/// never seen, and it is precisely a transient failure answering "yes, permanently missing" that
/// retires a working device for good.
protocol UnsupportedSimulatorCapabilityError: Error {
  /// What is missing, in a few words, for a caller assembling its own message — or `nil` where this
  /// value describes an attempt that failed or a request that was wrong, neither of which says
  /// anything about what the device can do.
  var unsupportedCapability: String? { get }
}

extension SimulatorDisplayInteractionError: UnsupportedSimulatorCapabilityError {
  var unsupportedCapability: String? {
    switch self {
    case let .unsupportedCapability(capability): capability
    // The display exists and the request was answerable; it was the request that was wrong.
    case .inactiveDisplay, .missingMapping, .invalidPoint, .nonFinitePoint: nil
    }
  }
}

extension SimulatorCoreDeviceError: UnsupportedSimulatorCapabilityError {
  var unsupportedCapability: String? {
    switch self {
    case let .unsupported(detail): detail
    // A missing service may appear on another boot; malformed replies and timeouts are attempt
    // failures. None establish that the simulator permanently lacks the capability.
    case .unavailable, .malformed, .timedOut: nil
    }
  }
}

/// The capability a failure says is missing, or `nil` when it says nothing of the kind.
///
/// A permanent case carrying no detail is reported as no classification at all: a caller is being
/// asked to stop offering something, and it cannot act on, or explain, a blank reason.
public func unsupportedSimulatorCapability(in error: any Error) -> String? {
  guard let error = error as? any UnsupportedSimulatorCapabilityError,
    let capability = error.unsupportedCapability,
    !capability.isEmpty
  else {
    return nil
  }
  return capability
}
