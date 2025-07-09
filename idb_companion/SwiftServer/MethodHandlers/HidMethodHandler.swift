/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import CompanionLib
import FBSimulatorControl
import GRPC
import IDBGRPCSwift

struct HidMethodHandler {

  let commandExecutor: FBIDBCommandExecutor

  func handle(requestStream: GRPCAsyncRequestStream<Idb_HIDEvent>, context: GRPCAsyncServerCallContext) async throws -> Idb_HIDResponse {
    for try await request in requestStream {
      let event = try fbSimulatorHIDEvent(from: request)
      try await BridgeFuture.await(commandExecutor.hid(event))
    }
    return .init()
  }

  private func fbSimulatorHIDEvent(from request: Idb_HIDEvent) throws -> FBSimulatorHIDEventProtocol {
    switch request.event {
    case let .press(press):
      switch press.action.action {
      case let .key(key):
        switch press.direction {
        case .up:
          return FBSimulatorHIDEvent.keyUp(UInt32(key.keycode))
        case .down:
          return FBSimulatorHIDEvent.keyDown(UInt32(key.keycode))
        case .UNRECOGNIZED:
          throw GRPCStatus(code: .invalidArgument, message: "Unrecognized press.direction")
        }

      case let .button(button):
        guard let hidButton = fbSimulatorHIDButton(from: button.button) else {
          throw GRPCStatus(code: .invalidArgument, message: "Unrecognized hid button type")
        }
        switch press.direction {
        case .up:
          return FBSimulatorHIDEvent.buttonUp(hidButton)
        case .down:
          return FBSimulatorHIDEvent.buttonDown(hidButton)
        case .UNRECOGNIZED:
          throw GRPCStatus(code: .invalidArgument, message: "Unrecognized press.direction")
        }

      case let .touch(touch):
        switch press.direction {
        case .up:
          return FBSimulatorHIDEvent.touchUpAt(x: touch.point.x, y: touch.point.y)
        case .down:
          return FBSimulatorHIDEvent.touchDownAt(x: touch.point.x, y: touch.point.y)
        case .UNRECOGNIZED:
          throw GRPCStatus(code: .invalidArgument, message: "Unrecognized press.direction")
        }

      case .none:
        throw GRPCStatus(code: .invalidArgument, message: "Unrecognized press.action")
      }

    case let .swipe(swipe):
      return FBSimulatorHIDEvent.swipe(
        swipe.start.x,
        yStart: swipe.start.y,
        xEnd: swipe.end.x,
        yEnd: swipe.end.y,
        delta: swipe.delta,
        duration: swipe.duration)

    case let .delay(delay):
      return FBSimulatorHIDEvent.delay(delay.duration)

    case .none:
      throw GRPCStatus(code: .invalidArgument, message: "Unrecognized request.event")
    }
  }

  private func fbSimulatorHIDButton(from request: Idb_HIDEvent.HIDButtonType) -> FBSimulatorHIDButton? {
    switch request {
    case .applePay:
      return .applePay
    case .home:
      return .homeButton
    case .lock:
      return .lock
    case .sideButton:
      return .sideButton
    case .siri:
      return .siri
    case .UNRECOGNIZED:
      return nil
    }
  }
}
