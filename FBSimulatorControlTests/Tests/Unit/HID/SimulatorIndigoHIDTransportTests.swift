/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CoreGraphics
import Darwin
import FBControlCore
@testable import FBSimulatorControl
import Foundation
import Testing
import os

/// Stands in for `SimulatorKit.SimDeviceLegacyHIDClient`, accepting every message and counting it.
private final class CountingLegacyHIDClientStub: NSObject {
  static let delivered = OSAllocatedUnfairLock(initialState: 0)

  @objc(initWithDevice:error:)
  func initWithDevice(_ device: Any, error: AutoreleasingUnsafeMutablePointer<AnyObject?>?) -> AnyObject? {
    self
  }

  @objc(sendWithMessage:freeWhenDone:completionQueue:completion:)
  func send(
    withMessage message: UnsafeMutableRawPointer,
    freeWhenDone: Bool,
    completionQueue: DispatchQueue,
    completion: @escaping @Sendable (Error?) -> Void
  ) {
    if freeWhenDone {
      free(message)
    }
    Self.delivered.withLock { $0 += 1 }
    completionQueue.async { completion(nil) }
  }
}

@Suite("Indigo HID transport", .serialized)
struct SimulatorIndigoHIDTransportTests {

  init() throws {
    // SimulatorIndigoHID() dlopens SimulatorKit; see SimulatorIndigoHIDTests for why the frameworks
    // are pre-loaded with the default logger.
    try SimulatorControlFrameworkLoader.essentialFrameworks.loadPrivateFrameworks(ControlCoreGlobalConfiguration.defaultLogger)
    try SimulatorControlFrameworkLoader.xcodeFrameworks.loadPrivateFrameworks(ControlCoreGlobalConfiguration.defaultLogger)
    CountingLegacyHIDClientStub.delivered.withLock { $0 = 0 }
  }

  private func makeTransport(legacyInputSuppressed: Bool) throws -> SimulatorIndigoHIDTransport {
    SimulatorIndigoHIDTransport(
      indigoClient: try SimulatorIndigoHIDClient(device: NSObject(), clientClass: ObjCRuntimeClass(CountingLegacyHIDClientStub.self)),
      indigo: try SimulatorIndigoHID(),
      mainScreenSize: CGSize(width: 1206, height: 2622),
      mainScreenScale: 3,
      legacyInputSuppressed: legacyInputSuppressed,
      productFamily: .iPhone)
  }

  private var delivered: Int {
    CountingLegacyHIDClientStub.delivered.withLock { $0 }
  }

  @Test("Touch is delivered on a toolchain whose guest honours legacy input")
  func touchDeliveredWhenNotSuppressed() async throws {
    let transport = try makeTransport(legacyInputSuppressed: false)
    try await transport.sendTouch(direction: .down, x: 100, y: 200, edge: .none)
    #expect(delivered == 1)
  }

  @Test("Button is delivered on a toolchain whose guest honours legacy input")
  func buttonDeliveredWhenNotSuppressed() async throws {
    let transport = try makeTransport(legacyInputSuppressed: false)
    try await transport.sendButton(direction: .down, button: .homeButton)
    #expect(delivered == 1)
  }

  @Test("Keyboard fails loudly on a toolchain whose guest drops legacy input")
  func keyboardRejectedWhenSuppressed() async throws {
    let transport = try makeTransport(legacyInputSuppressed: true)
    let error = await #expect(throws: SimulatorHIDError.self) {
      try await transport.sendKeyboard(direction: .down, keyCode: 4)
    }
    guard case .legacyInputSuppressed(operation: "Keyboard") = error else {
      Issue.record("Unexpected error \(String(describing: error))")
      return
    }
    #expect(delivered == 0)
  }

  @Test("Touch on a toolchain whose guest drops legacy input")
  func touchWhenSuppressed() async throws {
    let transport = try makeTransport(legacyInputSuppressed: true)
    // BUG: the guest drops this touch, but it is sent and reported as delivered — flipped in the
    // following commit.
    try await transport.sendTouch(direction: .down, x: 100, y: 200, edge: .none)
    #expect(delivered == 1)
  }

  @Test("Two-finger touch on a toolchain whose guest drops legacy input")
  func twoFingerTouchWhenSuppressed() async throws {
    let transport = try makeTransport(legacyInputSuppressed: true)
    // BUG: the guest drops this touch, but it is sent and reported as delivered — flipped in the
    // following commit.
    try await transport.sendTwoFingerTouch(direction: .down, finger1: CGPoint(x: 100, y: 200), finger2: CGPoint(x: 200, y: 300))
    #expect(delivered == 1)
  }

  @Test("Button on a toolchain whose guest drops legacy input")
  func buttonWhenSuppressed() async throws {
    let transport = try makeTransport(legacyInputSuppressed: true)
    // BUG: the guest drops this button, but it is sent and reported as delivered — flipped in the
    // following commit.
    try await transport.sendButton(direction: .down, button: .homeButton)
    #expect(delivered == 1)
  }
}
