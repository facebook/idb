/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBControlCore
@testable import FBSimulatorControl
import Foundation
import IOSurface

/// A fake `FBFramebufferSurface` that lets tests drive `FBFramebuffer` without the private
/// CoreSimulator renderable. Tests call `ioSurfaceChanged` / `damageReceived` to simulate callbacks.
final class FakeFramebufferSurface: FBFramebufferSurface {
  var immediateSurface: IOSurface?
  var registerError: Error?

  private(set) var ioSurfaceChanged: ((IOSurface?) -> Void)?
  private(set) var damageReceived: ((FBFramebufferDamage) -> Void)?
  private(set) var registeredTokens: [UUID] = []
  private(set) var unregisteredTokens: [UUID] = []

  func immediatelyAvailableSurface() -> IOSurface? {
    immediateSurface
  }

  func registerCallbacks(
    token: UUID,
    ioSurfaceChanged: @escaping (IOSurface?) -> Void,
    damageReceived: @escaping (FBFramebufferDamage) -> Void
  ) throws {
    if let registerError {
      throw registerError
    }
    registeredTokens.append(token)
    self.ioSurfaceChanged = ioSurfaceChanged
    self.damageReceived = damageReceived
  }

  func unregisterCallbacks(token: UUID) {
    unregisteredTokens.append(token)
  }
}

/// A fake `FBFramebufferConsumer` that records what it receives. The `onSurface`/`onDamage` hooks
/// fire after each recorded delivery (on the delivery queue), so tests can await delivery with an
/// `XCTestExpectation` without encoding any assumption about when the delivery was enqueued.
final class FakeFramebufferConsumer: NSObject, FBFramebufferConsumer {
  private(set) var receivedSurfaces: [IOSurface?] = []
  private(set) var damageCallbackCount = 0

  var onSurface: (() -> Void)?
  var onDamage: (() -> Void)?

  func didChange(_ surface: IOSurface?) {
    receivedSurfaces.append(surface)
    onSurface?()
  }

  func didReceiveDamageRect() {
    damageCallbackCount += 1
    onDamage?()
  }
}

/// Creates a small IOSurface for tests.
func makeTestIOSurface(width: Int = 16, height: Int = 16) -> IOSurface {
  let properties: [IOSurfacePropertyKey: Any] = [
    .width: width,
    .height: height,
    .bytesPerElement: 4,
  ]
  guard let surface = IOSurface(properties: properties) else {
    fatalError("Failed to create test IOSurface")
  }
  return surface
}
