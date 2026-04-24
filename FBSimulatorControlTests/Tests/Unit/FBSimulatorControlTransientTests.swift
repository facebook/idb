/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

// Disabled during swift-format 6.3 rollout, feel free to remove:
// swift-format-ignore-file: OrderedImports

import XCTest

@testable import FBSimulatorControl

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
    XCTAssertEqual(tap.events.count, 2, "Tap should consist of touch-down and touch-up")
  }

  func testTapWithDurationProducesThreeSubEvents() {
    let tap = FBSimulatorHIDEvent.tapAt(x: 50, y: 75, duration: 0.5)
    XCTAssertEqual(tap.events.count, 3, "Tap with duration should consist of touch-down, delay, touch-up")

    // The middle event should be a delay
    let delayEvent = tap.events[1] as? FBSimulatorHIDEventDelay
    XCTAssertNotNil(delayEvent, "Middle event should conform to FBSimulatorHIDEventDelay")
    if let d = delayEvent {
      XCTAssertEqual(d.duration, 0.5, accuracy: 0.001)
    }
  }

  func testShortButtonPressProducesTwoSubEvents() {
    let press = FBSimulatorHIDEvent.shortButtonPress(.homeButton)
    XCTAssertEqual(press.events.count, 2, "Short button press should be down + up")
  }

  func testShortKeyPressProducesTwoSubEvents() {
    let press = FBSimulatorHIDEvent.shortKeyPress(0x00) // keyCode for 'a'
    XCTAssertEqual(press.events.count, 2, "Short key press should be down + up")
  }

  func testShortKeyPressSequenceProducesCorrectCount() {
    let keyCodes: [NSNumber] = [0x00, 0x01, 0x02] // a, s, d
    let sequence = FBSimulatorHIDEvent.shortKeyPressSequence(keyCodes)
    // Each key produces a down + up pair
    let composite = sequence as! FBSimulatorHIDEventComposite
    XCTAssertEqual(composite.events.count, 6, "3 keys should produce 6 sub-events (3 down + 3 up)")
  }

  func testShortKeyPressSequenceEmptyArray() {
    let sequence = FBSimulatorHIDEvent.shortKeyPressSequence([])
    let composite = sequence as! FBSimulatorHIDEventComposite
    XCTAssertEqual(composite.events.count, 0)
  }

  // MARK: FBSimulatorHIDEvent - Delay

  func testDelayEventDuration() {
    let delay = FBSimulatorHIDEvent.delay(1.5)
    XCTAssertEqual(delay.duration, 1.5, accuracy: 0.001)
  }

  func testDelayEventEquality() {
    let a = FBSimulatorHIDEvent.delay(2.0) as! NSObject
    let b = FBSimulatorHIDEvent.delay(2.0) as! NSObject
    XCTAssertEqual(a, b)
  }

  func testDelayEventInequality() {
    let a = FBSimulatorHIDEvent.delay(1.0) as! NSObject
    let b = FBSimulatorHIDEvent.delay(2.0) as! NSObject
    XCTAssertNotEqual(a, b)
  }

  func testDelayEventCopyReturnsSelf() {
    let delay = FBSimulatorHIDEvent.delay(1.0)
    let delayObj = delay as! NSObject
    let copy = delayObj.copy() as AnyObject
    XCTAssertTrue(delayObj === copy)
  }

  // MARK: FBSimulatorHIDEvent - Composite

  func testEventWithEventsWrapsCorrectly() {
    let down = FBSimulatorHIDEvent.touchDownAt(x: 10, y: 20)
    let delay = FBSimulatorHIDEvent.delay(0.1)
    let up = FBSimulatorHIDEvent.touchUpAt(x: 10, y: 20)
    let composite = FBSimulatorHIDEvent.with(events: [down, delay, up])
    XCTAssertEqual(composite.events.count, 3)
  }

  func testCompositeEventEquality() {
    let a = FBSimulatorHIDEvent.tapAt(x: 100, y: 200) as! NSObject
    let b = FBSimulatorHIDEvent.tapAt(x: 100, y: 200) as! NSObject
    XCTAssertEqual(a, b)
    XCTAssertEqual(a.hash, b.hash)
  }

  func testCompositeEventInequalityByCoordinates() {
    let a = FBSimulatorHIDEvent.tapAt(x: 100, y: 200) as! NSObject
    let b = FBSimulatorHIDEvent.tapAt(x: 300, y: 400) as! NSObject
    XCTAssertNotEqual(a, b)
  }

  func testCompositeEventCopyReturnsSelf() {
    let composite = FBSimulatorHIDEvent.tapAt(x: 50, y: 50) as! NSObject
    let copy = composite.copy() as AnyObject
    XCTAssertTrue(composite === copy)
  }

  // MARK: FBSimulatorHIDEvent - Touch Events

  func testTouchDownEquality() {
    let a = FBSimulatorHIDEvent.touchDownAt(x: 10, y: 20) as! NSObject
    let b = FBSimulatorHIDEvent.touchDownAt(x: 10, y: 20) as! NSObject
    XCTAssertEqual(a, b)
  }

  func testTouchDownInequalityByCoordinates() {
    let a = FBSimulatorHIDEvent.touchDownAt(x: 10, y: 20) as! NSObject
    let b = FBSimulatorHIDEvent.touchDownAt(x: 30, y: 40) as! NSObject
    XCTAssertNotEqual(a, b)
  }

  func testTouchUpNotEqualToTouchDown() {
    let down = FBSimulatorHIDEvent.touchDownAt(x: 10, y: 20) as! NSObject
    let up = FBSimulatorHIDEvent.touchUpAt(x: 10, y: 20) as! NSObject
    XCTAssertNotEqual(down, up)
  }

  // MARK: FBSimulatorHIDEvent - Button Events

  func testButtonDownEquality() {
    let a = FBSimulatorHIDEvent.buttonDown(.homeButton) as! NSObject
    let b = FBSimulatorHIDEvent.buttonDown(.homeButton) as! NSObject
    XCTAssertEqual(a, b)
  }

  func testButtonDownInequalityByButton() {
    let a = FBSimulatorHIDEvent.buttonDown(.homeButton) as! NSObject
    let b = FBSimulatorHIDEvent.buttonDown(.lock) as! NSObject
    XCTAssertNotEqual(a, b)
  }

  func testButtonUpNotEqualToButtonDown() {
    let down = FBSimulatorHIDEvent.buttonDown(.siri) as! NSObject
    let up = FBSimulatorHIDEvent.buttonUp(.siri) as! NSObject
    XCTAssertNotEqual(down, up)
  }

  func testAllButtonTypesCreateDistinctEvents() {
    let buttons: [FBSimulatorHIDButton] = [.applePay, .homeButton, .lock, .sideButton, .siri]
    let events = buttons.map { FBSimulatorHIDEvent.buttonDown($0) as! NSObject }
    let uniqueSet = Set(events)
    XCTAssertEqual(uniqueSet.count, buttons.count, "Each button type should produce a distinct event")
  }

  // MARK: FBSimulatorHIDEvent - Keyboard Events

  func testKeyDownEquality() {
    let a = FBSimulatorHIDEvent.keyDown(0x0D) as! NSObject // W
    let b = FBSimulatorHIDEvent.keyDown(0x0D) as! NSObject
    XCTAssertEqual(a, b)
  }

  func testKeyDownInequalityByKeyCode() {
    let a = FBSimulatorHIDEvent.keyDown(0x0D) as! NSObject // W
    let b = FBSimulatorHIDEvent.keyDown(0x00) as! NSObject // A
    XCTAssertNotEqual(a, b)
  }

  func testKeyUpNotEqualToKeyDown() {
    let down = FBSimulatorHIDEvent.keyDown(0x0D) as! NSObject
    let up = FBSimulatorHIDEvent.keyUp(0x0D) as! NSObject
    XCTAssertNotEqual(down, up)
  }

  // MARK: FBSimulatorHIDEvent - Swipe

  func testSwipeHorizontalProducesCorrectStepCount() {
    // Horizontal swipe: 100 points with delta=10 -> 10 steps
    let swipe = FBSimulatorHIDEvent.swipe(0, yStart: 0, xEnd: 100, yEnd: 0, delta: 10, duration: 1.0)
    let composite = swipe as! FBSimulatorHIDEventComposite
    // steps = 10
    // Events: (10+1) * (touchDown + delay) + 1 extra touchDown + 1 extra delay + 1 touchUp
    // = 11*2 + 2 + 1 = 25
    let expectedSteps = 10
    let expectedEvents = (expectedSteps + 1) * 2 + 2 + 1
    XCTAssertEqual(composite.events.count, expectedEvents)
  }

  func testSwipeVerticalProducesCorrectStepCount() {
    // Vertical swipe: 50 points with delta=10 -> 5 steps
    let swipe = FBSimulatorHIDEvent.swipe(0, yStart: 0, xEnd: 0, yEnd: 50, delta: 10, duration: 0.5)
    let composite = swipe as! FBSimulatorHIDEventComposite
    let expectedSteps = 5
    let expectedEvents = (expectedSteps + 1) * 2 + 2 + 1
    XCTAssertEqual(composite.events.count, expectedEvents)
  }

  func testSwipeDiagonalProducesCorrectStepCount() {
    // Diagonal: distance = sqrt(30^2 + 40^2) = 50, delta=10 -> 5 steps
    let swipe = FBSimulatorHIDEvent.swipe(0, yStart: 0, xEnd: 30, yEnd: 40, delta: 10, duration: 1.0)
    let composite = swipe as! FBSimulatorHIDEventComposite
    let expectedSteps = 5
    let expectedEvents = (expectedSteps + 1) * 2 + 2 + 1
    XCTAssertEqual(composite.events.count, expectedEvents)
  }

  func testSwipeWithZeroDeltaUsesDefault() {
    // When delta <= 0, DEFAULT_SWIPE_DELTA (10.0) is used
    // 100 points / 10.0 = 10 steps
    let swipe = FBSimulatorHIDEvent.swipe(0, yStart: 0, xEnd: 100, yEnd: 0, delta: 0, duration: 1.0)
    let composite = swipe as! FBSimulatorHIDEventComposite
    let expectedSteps = 10
    let expectedEvents = (expectedSteps + 1) * 2 + 2 + 1
    XCTAssertEqual(composite.events.count, expectedEvents)
  }

  func testSwipeWithNegativeDeltaUsesDefault() {
    let swipe = FBSimulatorHIDEvent.swipe(0, yStart: 0, xEnd: 100, yEnd: 0, delta: -5, duration: 1.0)
    let composite = swipe as! FBSimulatorHIDEventComposite
    let expectedSteps = 10
    let expectedEvents = (expectedSteps + 1) * 2 + 2 + 1
    XCTAssertEqual(composite.events.count, expectedEvents)
  }

  func testSwipeEndsWithTouchUp() {
    let swipe = FBSimulatorHIDEvent.swipe(0, yStart: 0, xEnd: 50, yEnd: 0, delta: 10, duration: 0.5)
    let composite = swipe as! FBSimulatorHIDEventComposite
    let lastEvent = composite.events.last
    XCTAssertNotNil(lastEvent)
    XCTAssertFalse(lastEvent is FBSimulatorHIDEventDelay, "Last event should not be a delay")
  }

  func testSwipeEquality() {
    let a = FBSimulatorHIDEvent.swipe(0, yStart: 0, xEnd: 100, yEnd: 0, delta: 10, duration: 1.0) as! NSObject
    let b = FBSimulatorHIDEvent.swipe(0, yStart: 0, xEnd: 100, yEnd: 0, delta: 10, duration: 1.0) as! NSObject
    XCTAssertEqual(a, b)
  }

  func testSwipeInequalityByEndpoint() {
    let a = FBSimulatorHIDEvent.swipe(0, yStart: 0, xEnd: 100, yEnd: 0, delta: 10, duration: 1.0) as! NSObject
    let b = FBSimulatorHIDEvent.swipe(0, yStart: 0, xEnd: 200, yEnd: 0, delta: 10, duration: 1.0) as! NSObject
    XCTAssertNotEqual(a, b)
  }

  // MARK: FBSimulatorHIDEvent - Cross-type inequality

  func testTouchNotEqualToButton() {
    let touch = FBSimulatorHIDEvent.touchDownAt(x: 0, y: 0) as! NSObject
    let button = FBSimulatorHIDEvent.buttonDown(.homeButton) as! NSObject
    XCTAssertNotEqual(touch, button)
  }

  func testButtonNotEqualToKeyboard() {
    let button = FBSimulatorHIDEvent.buttonDown(.homeButton) as! NSObject
    let key = FBSimulatorHIDEvent.keyDown(0x00) as! NSObject
    XCTAssertNotEqual(button, key)
  }

  func testDelayNotEqualToTouch() {
    let delay = FBSimulatorHIDEvent.delay(1.0) as! NSObject
    let touch = FBSimulatorHIDEvent.touchDownAt(x: 0, y: 0) as! NSObject
    XCTAssertNotEqual(delay, touch)
  }

  // MARK: DEFAULT_SWIPE_DELTA constant

  func testDefaultSwipeDeltaValue() {
    XCTAssertEqual(DEFAULT_SWIPE_DELTA, 10.0, accuracy: 0.001)
  }
}
