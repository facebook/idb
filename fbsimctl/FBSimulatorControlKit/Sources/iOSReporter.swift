/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

import Foundation

/**
 A Protocol for Commands to access and report about an iOS Target.
 */
public protocol iOSReporter : class {
  associatedtype Target : FBiOSTarget

  var reporter: EventReporter { get }
  unowned var target: Target { get }
  var format: FBiOSTargetFormat { get }
}

extension iOSReporter {
  public func report(eventName: EventName, _ eventType: EventType, _ subject: EventReporterSubject) {
    let targetSubject = iOSTargetSubject(target: self.target, format: self.format)
    self.reporter.report(iOSTargetWithSubject(
      targetSubject: targetSubject,
      eventName: eventName,
      eventType: eventType,
      subject: subject
    ))
  }

  public func reportValue(eventName: EventName, _ eventType: EventType, _ value: ControlCoreValue) {
    self.report(eventName, eventType, ControlCoreSubject(value))
  }
}
