/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
import FBSimulatorBridgeProtocol
import FBSimulatorControl
import Foundation

/// A parsed axbridge read: the guest's node tree, the owning pid, whether the guest's walk was
/// truncated, and any fullscreen-modal descriptor.
///
/// The serialize step (`AXTreeWalk.describeAllElements`) and the truncation warning happen
/// once, in the shared `describeTree`, over this value — so a `.marker` poll that reads without
/// describing does not re-run either.
struct AXTreeRead: Sendable {
  let tree: BridgeAXNode
  let pid: pid_t
  let truncated: Bool
  let modal: AccessibilityModalInfo?
  var screen: AccessibilityScreenInfo?
  /// The device's accessibility automation mode as the guest saw it. Nil when the guest did not report it,
  /// which is why it is optional rather than defaulted — "the guest did not say" and "the device was not in
  /// automation mode" are different facts and must not collapse.
  var automation: AccessibilityAutomationState?
  /// What the guest measured of its own work, and what the host measured around the wire.
  var timings: AXReadTimings?
  /// The guest's reported phases, taken off the answer this read already decoded so the host does not
  /// decode the response a second time.
  var phases: (traverse: CFAbsoluteTime?, machRoundTrips: Int64?) = (nil, nil)
}

/// Where a guest-backed read's time went, from both sides of the boundary.
struct AXReadTimings: Equatable {
  /// Wall time of the whole transport call, host-side: request out, guest work, response back.
  let roundTrip: CFAbsoluteTime
  /// Decoding the guest's JSON, host-side.
  let decode: CFAbsoluteTime
  /// The guest's own walk, as it reported it.
  let traverse: CFAbsoluteTime?
  /// Round trips to the application's accessibility server, as the guest counted them.
  let machRoundTrips: Int64?
  /// Bytes the guest sent back.
  let responseBytes: Int64

  /// The round trip less the guest's walk: acquisition, bind, guest encoding and IPC, undivided.
  var residual: CFAbsoluteTime {
    max(0, roundTrip - (traverse ?? 0))
  }
}

// MARK: - Guest response decoding

/// Decodes the guest's answer to a read, a `BridgeAXOutcome`, into a read.
extension AXTreeRead {

  init(tree: BridgeAXNode, pid: pid_t, truncated: Bool, modal: AccessibilityModalInfo?) {
    self.init(tree: tree, pid: pid, truncated: truncated, modal: modal, automation: nil)
  }

  private init(answer: BridgeAXTreeResponse, pid: pid_t) {
    self.init(
      tree: answer.tree, pid: pid, truncated: answer.truncated, modal: answer.modal.map(AccessibilityModalInfo.init),
      automation: answer.automation.map { AccessibilityAutomationState(enabled: $0.enabled, asserted: $0.asserted) })
    // Milliseconds on the wire, seconds in the model, matching every other duration here.
    phases = (answer.phases?.traverseMilliseconds.map { $0 / 1000 }, answer.phases?.machRoundTrips)
  }

  init(wholeTreeResponse response: BridgeAXAnswer, pid: pid_t) throws {
    let answer = try AXBridgeResponse.decode(response, as: BridgeAXTreeResponse.self, context: "pid \(pid)", pid: pid)
    self.init(answer: answer, pid: pid)
  }

  /// The pid rides back in the answer because the guest resolved it. A failure is classified by the guest's
  /// failure kind, so a resolved app with no accessibility server reads the same as via `--pid`; `method` is
  /// named only when the strategy itself could not answer.
  init(frontmostResponse response: BridgeAXAnswer, method: AXBridgeFrontmostMethod) throws {
    let answer = try AXBridgeResponse.decode(
      response, as: BridgeAXTreeResponse.self, context: "fused frontmost describe", frontmostMethod: method)
    guard answer.pid > 0 else {
      throw AXBridgeError.guestFailure("fused frontmost describe response without a resolved pid")
    }
    self.init(answer: answer, pid: answer.pid)
  }

  /// `nil` when the guest reports no element at the point — a valid empty result. A failure throws,
  /// classified by the guest's kind. A hit carries no truncation flag or modal.
  init?(hitTestResponse response: BridgeAXAnswer) throws {
    switch try AXBridgeResponse.decode(response, as: BridgeAXHitTestResponse.self, context: "hit-test") {
    case .empty:
      return nil
    case let .element(node, pid):
      guard pid > 0 else {
        throw AXBridgeError.guestFailure("hit-test response without an owning pid")
      }
      self.init(tree: node, pid: pid, truncated: false, modal: nil)
    }
  }

  /// Whether a `perform`/`setvalue` landed. `empty` is a value, not a failure: only the caller can say
  /// an unoccupied point is wrong.
  static func writeLanded(fromResponse response: BridgeAXAnswer) throws -> Bool {
    try AXBridgeResponse.decode(response, as: BridgeAXWriteResponse.self, context: "write") != .empty
  }

  /// Whether a failed write's answer says nothing reached the application. A refused assertion never
  /// sends; otherwise an absent `effect` means the write may have been sent.
  static func writeSentNothing(fromResponse response: BridgeAXAnswer) -> Bool {
    guard case let .failure(failure) = response else {
      return false
    }
    return failure.kind == .assertionFailed || failure.effect == AXWire.Effect.none
  }
}
