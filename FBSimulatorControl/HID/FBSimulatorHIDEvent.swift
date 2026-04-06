// (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.

import FBControlCore
import Foundation

// MARK: - Private helper

private func directionString(from direction: FBSimulatorHIDDirection) -> String? {
  switch direction {
  case .down:
    return "down"
  case .up:
    return "up"
  @unknown default:
    return nil
  }
}

private func shouldLogHIDEventDetails() -> Bool {
  return ProcessInfo.processInfo.environment["FBSIMULATORCONTROL_LOG_HID_DETAILS"]?.boolValue ?? false
}

private extension String {
  var boolValue: Bool {
    return (self as NSString).boolValue
  }
}

// MARK: - FBSimulatorHIDEvent_Composite

private class FBSimulatorHIDEvent_Composite: NSObject, FBSimulatorHIDEventComposite {

  let events: [any FBSimulatorHIDEventProtocol]

  init(events: [any FBSimulatorHIDEventProtocol]) {
    self.events = events
    super.init()
  }

  func sendOn(hid: FBSimulatorHID) -> FBFuture<NSNull> {
    return performEvents(events, on: hid)
  }

  private func performEvents(_ events: [any FBSimulatorHIDEventProtocol], on hid: FBSimulatorHID) -> FBFuture<NSNull> {
    if events.isEmpty {
      return FBFuture<NSNull>.empty()
    }
    let event = events[0]
    let next = events.count == 1 ? [] : Array(events[1...])
    return
      (event.sendOn(hid: hid)
      .onQueue(
        DispatchQueue.main,
        fmap: { [weak self] (_: Any) -> FBFuture<AnyObject> in
          guard let self else {
            return unsafeBitCast(FBFuture<NSNull>.empty(), to: FBFuture<AnyObject>.self)
          }
          return unsafeBitCast(self.performEvents(next, on: hid), to: FBFuture<AnyObject>.self)
        })) as! FBFuture<NSNull>
  }

  override var description: String {
    return "Composite \(FBCollectionInformation.oneLineDescription(from: events))"
  }

  func copy(with zone: NSZone? = nil) -> Any {
    return self
  }

  override func isEqual(_ object: Any?) -> Bool {
    guard let other = object as? FBSimulatorHIDEvent_Composite else { return false }
    return (events as NSArray).isEqual(to: other.events)
  }

  override var hash: Int {
    return (events as NSArray).hash
  }
}

// MARK: - FBSimulatorHIDEvent_Touch

private class FBSimulatorHIDEvent_Touch: NSObject, FBSimulatorHIDEventPayload {

  let direction: FBSimulatorHIDDirection
  let x: Double
  let y: Double

  init(direction: FBSimulatorHIDDirection, x: Double, y: Double) {
    self.direction = direction
    self.x = x
    self.y = y
    super.init()
  }

  func sendOn(hid: FBSimulatorHID) -> FBFuture<NSNull> {
    return hid.sendEvent(payload(for: hid))
  }

  func payload(for hid: FBSimulatorHID) -> Data {
    return hid.indigo.touchScreenSize(hid.mainScreenSize, screenScale: hid.mainScreenScale, direction: direction, x: x, y: y)
  }

  override var description: String {
    if shouldLogHIDEventDetails() {
      return "Touch \(directionString(from: direction) ?? "unknown") at (\(UInt(x)),\(UInt(y)))"
    }
    return "Touch <hidden>"
  }

  func copy(with zone: NSZone? = nil) -> Any {
    return self
  }

  override func isEqual(_ object: Any?) -> Bool {
    guard let other = object as? FBSimulatorHIDEvent_Touch else { return false }
    return direction == other.direction && x == other.x && y == other.y
  }

  override var hash: Int {
    return Int(direction.rawValue) | (Int(x) ^ Int(y))
  }
}

// MARK: - FBSimulatorHIDEvent_Button

private class FBSimulatorHIDEvent_Button: NSObject, FBSimulatorHIDEventPayload {

  let type: FBSimulatorHIDDirection
  let button: FBSimulatorHIDButton

  init(direction: FBSimulatorHIDDirection, button: FBSimulatorHIDButton) {
    self.type = direction
    self.button = button
    super.init()
  }

  func sendOn(hid: FBSimulatorHID) -> FBFuture<NSNull> {
    return hid.sendEvent(payload(for: hid))
  }

  func payload(for hid: FBSimulatorHID) -> Data {
    return hid.indigo.button(with: type, button: button)
  }

  override var description: String {
    if shouldLogHIDEventDetails() {
      return "Button \(FBSimulatorHIDEvent_Button.buttonString(from: button) ?? "unknown") \(directionString(from: type) ?? "unknown")"
    }
    return "Button <hidden>"
  }

  func copy(with zone: NSZone? = nil) -> Any {
    return self
  }

  override func isEqual(_ object: Any?) -> Bool {
    guard let other = object as? FBSimulatorHIDEvent_Button else { return false }
    return type == other.type && button == other.button
  }

  override var hash: Int {
    return Int(type.rawValue) ^ Int(button.rawValue)
  }

  class func buttonString(from button: FBSimulatorHIDButton) -> String? {
    switch button {
    case .applePay:
      return "apple_pay"
    case .homeButton:
      return "home"
    case .lock:
      return "lock"
    case .sideButton:
      return "side"
    case .siri:
      return "siri"
    @unknown default:
      return nil
    }
  }
}

// MARK: - FBSimulatorHIDEvent_Keyboard

private class FBSimulatorHIDEvent_Keyboard: NSObject, FBSimulatorHIDEventPayload {

  let direction: FBSimulatorHIDDirection
  let keyCode: UInt32

  init(direction: FBSimulatorHIDDirection, keyCode: UInt32) {
    self.direction = direction
    self.keyCode = keyCode
    super.init()
  }

  func sendOn(hid: FBSimulatorHID) -> FBFuture<NSNull> {
    return hid.sendEvent(payload(for: hid))
  }

  func payload(for hid: FBSimulatorHID) -> Data {
    return hid.indigo.keyboard(with: direction, keyCode: keyCode)
  }

  override var description: String {
    if shouldLogHIDEventDetails() {
      return "Keyboard Code=\(keyCode) \(directionString(from: direction) ?? "unknown")"
    }
    return "Key <hidden>"
  }

  func copy(with zone: NSZone? = nil) -> Any {
    return self
  }

  override func isEqual(_ object: Any?) -> Bool {
    guard let other = object as? FBSimulatorHIDEvent_Keyboard else { return false }
    return direction == other.direction && keyCode == other.keyCode
  }

  override var hash: Int {
    return Int(direction.rawValue) ^ Int(keyCode)
  }
}

// MARK: - FBSimulatorHIDEvent_Delay

private class FBSimulatorHIDEvent_Delay: NSObject, FBSimulatorHIDEventDelay {

  let duration: TimeInterval

  init(duration: TimeInterval) {
    self.duration = duration
    super.init()
  }

  func sendOn(hid: FBSimulatorHID) -> FBFuture<NSNull> {
    return FBFuture(delay: duration, future: FBFuture<NSNull>.empty())
  }

  override var description: String {
    return "Delay for \(duration)"
  }

  func copy(with zone: NSZone? = nil) -> Any {
    return self
  }

  override func isEqual(_ object: Any?) -> Bool {
    guard let other = object as? FBSimulatorHIDEvent_Delay else { return false }
    return duration == other.duration
  }

  override var hash: Int {
    return Int(duration)
  }
}

// MARK: - FBSimulatorHIDEvent

@objc(FBSimulatorHIDEvent)
public final class FBSimulatorHIDEvent: NSObject {

  // MARK: - Single Payload Events

  @objc(touchDownAtX:y:)
  public class func touchDownAt(x: Double, y: Double) -> any FBSimulatorHIDEventPayload {
    return FBSimulatorHIDEvent_Touch(direction: .down, x: x, y: y)
  }

  @objc(touchUpAtX:y:)
  public class func touchUpAt(x: Double, y: Double) -> any FBSimulatorHIDEventPayload {
    return FBSimulatorHIDEvent_Touch(direction: .up, x: x, y: y)
  }

  @objc(buttonDown:)
  public class func buttonDown(_ button: FBSimulatorHIDButton) -> any FBSimulatorHIDEventPayload {
    return FBSimulatorHIDEvent_Button(direction: .down, button: button)
  }

  @objc(buttonUp:)
  public class func buttonUp(_ button: FBSimulatorHIDButton) -> any FBSimulatorHIDEventPayload {
    return FBSimulatorHIDEvent_Button(direction: .up, button: button)
  }

  @objc(keyDown:)
  public class func keyDown(_ keyCode: UInt32) -> any FBSimulatorHIDEventPayload {
    return FBSimulatorHIDEvent_Keyboard(direction: .down, keyCode: keyCode)
  }

  @objc(keyUp:)
  public class func keyUp(_ keyCode: UInt32) -> any FBSimulatorHIDEventPayload {
    return FBSimulatorHIDEvent_Keyboard(direction: .up, keyCode: keyCode)
  }

  // MARK: - Multiple Payload Events

  @objc(eventWithEvents:)
  public class func with(events: [any FBSimulatorHIDEventProtocol]) -> any FBSimulatorHIDEventComposite {
    return FBSimulatorHIDEvent_Composite(events: events)
  }

  @objc(tapAtX:y:)
  public class func tapAt(x: Double, y: Double) -> any FBSimulatorHIDEventComposite {
    return with(events: [
      touchDownAt(x: x, y: y),
      touchUpAt(x: x, y: y),
    ])
  }

  @objc(tapAtX:y:duration:)
  public class func tapAt(x: Double, y: Double, duration: Double) -> any FBSimulatorHIDEventComposite {
    return with(events: [
      touchDownAt(x: x, y: y),
      delay(duration),
      touchUpAt(x: x, y: y),
    ])
  }

  @objc(shortButtonPress:)
  public class func shortButtonPress(_ button: FBSimulatorHIDButton) -> any FBSimulatorHIDEventComposite {
    return with(events: [
      buttonDown(button),
      buttonUp(button),
    ])
  }

  @objc(shortKeyPress:)
  public class func shortKeyPress(_ keyCode: UInt32) -> any FBSimulatorHIDEventComposite {
    return with(events: [
      keyDown(keyCode),
      keyUp(keyCode),
    ])
  }

  @objc(shortKeyPressSequence:)
  public class func shortKeyPressSequence(_ sequence: [NSNumber]) -> any FBSimulatorHIDEventProtocol {
    var events: [any FBSimulatorHIDEventPayload] = []
    for keyCode in sequence {
      events.append(keyDown(keyCode.uint32Value))
      events.append(keyUp(keyCode.uint32Value))
    }
    return with(events: events)
  }

  @objc(swipe:yStart:xEnd:yEnd:delta:duration:)
  public class func swipe(_ xStart: Double, yStart: Double, xEnd: Double, yEnd: Double, delta: Double, duration: Double) -> any FBSimulatorHIDEventProtocol {
    var events: [any FBSimulatorHIDEventProtocol] = []
    let distance = sqrt(pow(yEnd - yStart, 2) + pow(xEnd - xStart, 2))
    var effectiveDelta = delta
    if effectiveDelta <= 0.0 {
      effectiveDelta = DEFAULT_SWIPE_DELTA
    }
    let steps = Int(distance / effectiveDelta)

    let dx = (xEnd - xStart) / Double(steps)
    let dy = (yEnd - yStart) / Double(steps)

    let stepDelay = duration / Double(steps + 2)

    for i in 0...steps {
      events.append(touchDownAt(x: xStart + dx * Double(i), y: yStart + dy * Double(i)))
      events.append(delay(stepDelay))
    }
    // Add an additional touch down event at the end of the swipe to avoid inertial scroll on arm simulators.
    events.append(touchDownAt(x: xStart + dx * Double(steps), y: yStart + dy * Double(steps)))
    events.append(delay(stepDelay))

    events.append(touchUpAt(x: xEnd, y: yEnd))

    return with(events: events)
  }

  @objc(delay:)
  public class func delay(_ duration: Double) -> any FBSimulatorHIDEventDelay {
    return FBSimulatorHIDEvent_Delay(duration: duration)
  }
}
