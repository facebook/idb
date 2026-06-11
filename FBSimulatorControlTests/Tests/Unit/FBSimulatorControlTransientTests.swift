/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

@testable import FBSimulatorControl
import XCTest

// MARK: - FBSimulatorBootConfiguration Tests

final class FBSimulatorControlTransientTests: XCTestCase {

  // MARK: FBSimulatorBootConfiguration

  func testDefaultConfigurationHasVerifyUsable() {
    let config = FBSimulatorBootConfiguration.default
    XCTAssertTrue(
      config.options.contains(.verifyUsable),
      "Default configuration should have VerifyUsable option"
    )
    XCTAssertFalse(
      config.options.contains(.tieToProcessLifecycle),
      "Default configuration should not have TieToProcessLifecycle option"
    )
  }

  func testDefaultConfigurationHasEmptyEnvironment() {
    let config = FBSimulatorBootConfiguration.default
    XCTAssertNotNil(config.environment)
    XCTAssertEqual(config.environment.count, 0)
  }

  func testDefaultConfigurationIsSingleton() {
    let a = FBSimulatorBootConfiguration.default
    let b = FBSimulatorBootConfiguration.default
    XCTAssertTrue(a === b)
  }

  func testBootConfigurationInitWithOptions() {
    let config = FBSimulatorBootConfiguration(
      options: .tieToProcessLifecycle,
      environment: ["DYLD_INSERT_LIBRARIES": "/tmp/lib.dylib"]
    )
    XCTAssertTrue(config.options.contains(.tieToProcessLifecycle))
    XCTAssertFalse(config.options.contains(.verifyUsable))
    XCTAssertEqual(config.environment["DYLD_INSERT_LIBRARIES"], "/tmp/lib.dylib")
  }

  func testBootConfigurationInitWithCombinedOptions() {
    let combined: FBSimulatorBootOptions = [.tieToProcessLifecycle, .verifyUsable]
    let config = FBSimulatorBootConfiguration(options: combined, environment: [:])
    XCTAssertTrue(config.options.contains(.tieToProcessLifecycle))
    XCTAssertTrue(config.options.contains(.verifyUsable))
  }

  func testBootConfigurationEquality() {
    let a = FBSimulatorBootConfiguration(options: .verifyUsable, environment: ["A": "B"])
    let b = FBSimulatorBootConfiguration(options: .verifyUsable, environment: ["A": "B"])
    XCTAssertEqual(a, b)
    XCTAssertEqual(a.hash, b.hash)
  }

  func testBootConfigurationInequalityByOptions() {
    let a = FBSimulatorBootConfiguration(options: .verifyUsable, environment: [:])
    let b = FBSimulatorBootConfiguration(options: .tieToProcessLifecycle, environment: [:])
    XCTAssertNotEqual(a, b)
  }

  func testBootConfigurationInequalityByEnvironment() {
    let a = FBSimulatorBootConfiguration(options: .verifyUsable, environment: ["X": "1"])
    let b = FBSimulatorBootConfiguration(options: .verifyUsable, environment: ["Y": "2"])
    XCTAssertNotEqual(a, b)
  }

  func testBootConfigurationCopyReturnsSelf() {
    let config = FBSimulatorBootConfiguration(options: .verifyUsable, environment: [:])
    let copy = config.copy() as AnyObject
    XCTAssertTrue(config === copy)
  }

  func testBootConfigurationDescription() {
    let config = FBSimulatorBootConfiguration(
      options: .tieToProcessLifecycle,
      environment: ["KEY": "VAL"]
    )
    let desc = config.description
    XCTAssertTrue(desc.contains("Boot Environment"), "Description should contain 'Boot Environment'")
    XCTAssertTrue(desc.contains("Options"), "Description should contain 'Options'")
  }

  func testBootConfigurationDescriptionContainsDirectLaunch() {
    let config = FBSimulatorBootConfiguration(
      options: .tieToProcessLifecycle,
      environment: [:]
    )
    let desc = config.description
    XCTAssertTrue(desc.contains("Direct Launch"), "Description should contain 'Direct Launch' for tieToProcessLifecycle")
  }

  func testBootConfigurationDescriptionWithoutDirectLaunch() {
    let config = FBSimulatorBootConfiguration(
      options: .verifyUsable,
      environment: [:]
    )
    let desc = config.description
    XCTAssertFalse(desc.contains("Direct Launch"), "Description should not contain 'Direct Launch' for verifyUsable only")
  }

  // MARK: FBSimulatorHIDEvent - Tap Composite Structure

  func testTapProducesTwoSubEvents() {
    let tap = FBSimulatorHIDEvent.tapAt(x: 100, y: 200)
    XCTAssertEqual(tap.subEvents?.count, 2, "Tap should consist of touch-down and touch-up")
  }

  func testTapWithDurationProducesThreeSubEvents() {
    let tap = FBSimulatorHIDEvent.tapAt(x: 50, y: 75, duration: 0.5)
    XCTAssertEqual(tap.subEvents?.count, 3, "Tap with duration should consist of touch-down, delay, touch-up")

    // The middle event should be a delay.
    guard case let .delay(duration)? = tap.subEvents?[1] else {
      return XCTFail("Middle event should be a .delay")
    }
    XCTAssertEqual(duration, 0.5, accuracy: 0.001)
  }

  func testShortButtonPressProducesTwoSubEvents() {
    let press = FBSimulatorHIDEvent.shortButtonPress(.homeButton)
    XCTAssertEqual(press.subEvents?.count, 2, "Short button press should be down + up")
  }

  func testShortKeyPressProducesTwoSubEvents() {
    let press = FBSimulatorHIDEvent.shortKeyPress(0x00) // keyCode for 'a'
    XCTAssertEqual(press.subEvents?.count, 2, "Short key press should be down + up")
  }

  func testShortKeyPressSequenceProducesCorrectCount() {
    let keyCodes: [NSNumber] = [0x00, 0x01, 0x02] // a, s, d
    let sequence = FBSimulatorHIDEvent.shortKeyPressSequence(keyCodes)
    XCTAssertEqual(sequence.subEvents?.count, 6, "3 keys should produce 6 sub-events (3 down + 3 up)")
  }

  func testShortKeyPressSequenceEmptyArray() {
    let sequence = FBSimulatorHIDEvent.shortKeyPressSequence([])
    XCTAssertEqual(sequence.subEvents?.count, 0)
  }

  // MARK: FBSimulatorHIDEvent - Delay

  func testDelayEventDuration() {
    guard case let .delay(duration) = FBSimulatorHIDEvent.delay(1.5) else {
      return XCTFail("delay should produce a .delay event")
    }
    XCTAssertEqual(duration, 1.5, accuracy: 0.001)
  }

  func testDelayEventEquality() {
    XCTAssertEqual(FBSimulatorHIDEvent.delay(2.0), .delay(2.0))
  }

  func testDelayEventInequality() {
    XCTAssertNotEqual(FBSimulatorHIDEvent.delay(1.0), .delay(2.0))
  }

  // MARK: FBSimulatorHIDEvent - Composite

  func testEventWithEventsWrapsCorrectly() {
    let composite = FBSimulatorHIDEvent.with(events: [
      .touchDownAt(x: 10, y: 20),
      .delay(0.1),
      .touchUpAt(x: 10, y: 20),
    ])
    XCTAssertEqual(composite.subEvents?.count, 3)
  }

  func testCompositeEventEquality() {
    let a = FBSimulatorHIDEvent.tapAt(x: 100, y: 200)
    let b = FBSimulatorHIDEvent.tapAt(x: 100, y: 200)
    XCTAssertEqual(a, b)
    XCTAssertEqual(a.hashValue, b.hashValue)
  }

  func testCompositeEventInequalityByCoordinates() {
    XCTAssertNotEqual(FBSimulatorHIDEvent.tapAt(x: 100, y: 200), .tapAt(x: 300, y: 400))
  }

  // MARK: FBSimulatorHIDEvent - Touch Events

  func testTouchDownEquality() {
    XCTAssertEqual(FBSimulatorHIDEvent.touchDownAt(x: 10, y: 20), .touchDownAt(x: 10, y: 20))
  }

  func testTouchDownInequalityByCoordinates() {
    XCTAssertNotEqual(FBSimulatorHIDEvent.touchDownAt(x: 10, y: 20), .touchDownAt(x: 30, y: 40))
  }

  func testTouchUpNotEqualToTouchDown() {
    XCTAssertNotEqual(FBSimulatorHIDEvent.touchDownAt(x: 10, y: 20), .touchUpAt(x: 10, y: 20))
  }

  // MARK: FBSimulatorHIDEvent - Button Events

  func testButtonDownEquality() {
    XCTAssertEqual(FBSimulatorHIDEvent.buttonDown(.homeButton), .buttonDown(.homeButton))
  }

  func testButtonDownInequalityByButton() {
    XCTAssertNotEqual(FBSimulatorHIDEvent.buttonDown(.homeButton), .buttonDown(.lock))
  }

  func testButtonUpNotEqualToButtonDown() {
    XCTAssertNotEqual(FBSimulatorHIDEvent.buttonDown(.siri), .buttonUp(.siri))
  }

  func testAllButtonTypesCreateDistinctEvents() {
    let buttons: [FBSimulatorHIDButton] = [.applePay, .homeButton, .lock, .sideButton, .siri]
    let events = Set(buttons.map { FBSimulatorHIDEvent.buttonDown($0) })
    XCTAssertEqual(events.count, buttons.count, "Each button type should produce a distinct event")
  }

  // MARK: FBSimulatorHIDEvent - Keyboard Events

  func testKeyDownEquality() {
    XCTAssertEqual(FBSimulatorHIDEvent.keyDown(0x0D), .keyDown(0x0D)) // W
  }

  func testKeyDownInequalityByKeyCode() {
    XCTAssertNotEqual(FBSimulatorHIDEvent.keyDown(0x0D), .keyDown(0x00)) // W vs A
  }

  func testKeyUpNotEqualToKeyDown() {
    XCTAssertNotEqual(FBSimulatorHIDEvent.keyDown(0x0D), .keyUp(0x0D))
  }

  // MARK: FBSimulatorHIDEvent - Swipe

  func testSwipeHorizontalProducesCorrectStepCount() {
    // Horizontal swipe: 100 points with delta=10 -> 10 steps
    let swipe = FBSimulatorHIDEvent.swipe(0, yStart: 0, xEnd: 100, yEnd: 0, delta: 10, duration: 1.0)
    // Events: (10+1) * (touchDown + delay) + 1 extra touchDown + 1 extra delay + 1 touchUp = 25
    let expectedSteps = 10
    let expectedEvents = (expectedSteps + 1) * 2 + 2 + 1
    XCTAssertEqual(swipe.subEvents?.count, expectedEvents)
  }

  func testSwipeVerticalProducesCorrectStepCount() {
    // Vertical swipe: 50 points with delta=10 -> 5 steps
    let swipe = FBSimulatorHIDEvent.swipe(0, yStart: 0, xEnd: 0, yEnd: 50, delta: 10, duration: 0.5)
    let expectedSteps = 5
    let expectedEvents = (expectedSteps + 1) * 2 + 2 + 1
    XCTAssertEqual(swipe.subEvents?.count, expectedEvents)
  }

  func testSwipeDiagonalProducesCorrectStepCount() {
    // Diagonal: distance = sqrt(30^2 + 40^2) = 50, delta=10 -> 5 steps
    let swipe = FBSimulatorHIDEvent.swipe(0, yStart: 0, xEnd: 30, yEnd: 40, delta: 10, duration: 1.0)
    let expectedSteps = 5
    let expectedEvents = (expectedSteps + 1) * 2 + 2 + 1
    XCTAssertEqual(swipe.subEvents?.count, expectedEvents)
  }

  func testSwipeWithZeroDeltaUsesDefault() {
    // When delta <= 0, DEFAULT_SWIPE_DELTA (10.0) is used: 100 points / 10.0 = 10 steps
    let swipe = FBSimulatorHIDEvent.swipe(0, yStart: 0, xEnd: 100, yEnd: 0, delta: 0, duration: 1.0)
    let expectedSteps = 10
    let expectedEvents = (expectedSteps + 1) * 2 + 2 + 1
    XCTAssertEqual(swipe.subEvents?.count, expectedEvents)
  }

  func testSwipeWithNegativeDeltaUsesDefault() {
    let swipe = FBSimulatorHIDEvent.swipe(0, yStart: 0, xEnd: 100, yEnd: 0, delta: -5, duration: 1.0)
    let expectedSteps = 10
    let expectedEvents = (expectedSteps + 1) * 2 + 2 + 1
    XCTAssertEqual(swipe.subEvents?.count, expectedEvents)
  }

  func testSwipeEndsWithTouchUp() {
    let swipe = FBSimulatorHIDEvent.swipe(0, yStart: 0, xEnd: 50, yEnd: 0, delta: 10, duration: 0.5)
    guard let last = swipe.subEvents?.last else {
      return XCTFail("Swipe should have sub-events")
    }
    if case .delay(_) = last {
      XCTFail("Last event should not be a delay")
    }
  }

  func testSwipeEquality() {
    let a = FBSimulatorHIDEvent.swipe(0, yStart: 0, xEnd: 100, yEnd: 0, delta: 10, duration: 1.0)
    let b = FBSimulatorHIDEvent.swipe(0, yStart: 0, xEnd: 100, yEnd: 0, delta: 10, duration: 1.0)
    XCTAssertEqual(a, b)
  }

  func testSwipeInequalityByEndpoint() {
    let a = FBSimulatorHIDEvent.swipe(0, yStart: 0, xEnd: 100, yEnd: 0, delta: 10, duration: 1.0)
    let b = FBSimulatorHIDEvent.swipe(0, yStart: 0, xEnd: 200, yEnd: 0, delta: 10, duration: 1.0)
    XCTAssertNotEqual(a, b)
  }

  // MARK: FBSimulatorHIDEvent - Cross-type inequality

  func testTouchNotEqualToButton() {
    XCTAssertNotEqual(FBSimulatorHIDEvent.touchDownAt(x: 0, y: 0), .buttonDown(.homeButton))
  }

  func testButtonNotEqualToKeyboard() {
    XCTAssertNotEqual(FBSimulatorHIDEvent.buttonDown(.homeButton), .keyDown(0x00))
  }

  func testDelayNotEqualToTouch() {
    XCTAssertNotEqual(FBSimulatorHIDEvent.delay(1.0), .touchDownAt(x: 0, y: 0))
  }

  // MARK: DEFAULT_SWIPE_DELTA constant

  func testDefaultSwipeDeltaValue() {
    XCTAssertEqual(DEFAULT_SWIPE_DELTA, 10.0, accuracy: 0.001)
  }
}
