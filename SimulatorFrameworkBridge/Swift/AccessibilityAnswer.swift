/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBSimulatorBridgeProtocol
import Foundation

/// An accessibility stream: answers its request with a run of answers, each its own frame.
protocol AccessibilityAnswerStream: AnyObject {
  /// Whether the stream ended because its source failed rather than because it was cancelled.
  var failed: Bool { get }
  /// Runs on the serving thread until the stream ends, handing each answer to `emit`, which answers false once
  /// one could not be sent.
  func run(emit: @escaping (BridgeAXAnswer) -> Bool)
  /// Asks a running stream to end, from another thread; `run` must return promptly afterwards.
  func cancel()
}

extension BridgeAXAnswer {
  /// The answer on its own, as the one-shot command line prints it. One that cannot be encoded is printed as a
  /// failure saying so: the guest must never abort or print nothing.
  public func encoded() -> Data {
    do {
      return try JSONEncoder().encode(self)
    } catch {
      NSLog("[AccessibilityService] could not encode an answer, sending a failure instead: %@", error as NSError)
      return Data(#"{"error":"response serialization failed","ok":false}"#.utf8)
    }
  }

  /// The answer an outcome makes, its success wrapped as `success` says.
  init<Success>(_ outcome: BridgeAXOutcome<Success>, _ success: (Success) -> BridgeAXAnswer) {
    switch outcome {
    case let .success(answer): self = success(answer)
    case let .failure(failure): self = .failure(failure)
    }
  }
}
