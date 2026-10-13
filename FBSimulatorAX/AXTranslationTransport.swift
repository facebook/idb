/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@preconcurrency internal import AccessibilityPlatformTranslation
import CoreSimulator
import Foundation

/// Carries one translator request to the simulator's accessibility service and brings back its answer.
///
/// Synchronous because `AXPTranslator` asks its bridge delegate for an answer synchronously: the transport
/// is the one place that waits, and it never waits longer than `timeout`.
protocol AXTranslationTransport: Sendable {
  /// The service's answer, or nil when none arrived within `timeout`. Must not be called on the main queue.
  func send(_ request: AXPTranslatorRequest, timeout: TimeInterval) -> AXPTranslatorResponse?
}

/// Sends translator requests through CoreSimulator's own client,
/// `-[SimDevice sendAccessibilityRequestAsync:completionQueue:completionHandler:]`.
final class CoreSimulatorAXTranslationTransport: AXTranslationTransport, @unchecked Sendable {
  // SAFETY: both are only read after init; `SimDevice` messages its service from any queue.
  private let device: SimDevice
  private let completionQueue: DispatchQueue

  init(device: SimDevice) {
    self.device = device
    self.completionQueue = DispatchQueue(label: "com.facebook.fbsimulatorcontrol.accessibility_translator.callback")
  }

  func send(_ request: AXPTranslatorRequest, timeout: TimeInterval) -> AXPTranslatorResponse? {
    let answered = DispatchSemaphore(value: 0)
    let box = ResponseBox()
    device.sendAccessibilityRequestAsync(request, completionQueue: completionQueue) { response in
      box.response = response
      answered.signal()
    }
    guard answered.wait(timeout: .now() + timeout) == .success else {
      return nil
    }
    return box.response
  }
}

/// Mutable holder so the synchronous send can capture the response out of the `@Sendable` CoreSimulator
/// completion handler. The semaphore wait establishes the happens-before needed before the value is read.
private final class ResponseBox: @unchecked Sendable {
  var response: AXPTranslatorResponse?
}
