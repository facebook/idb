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
  var reporter: EventReporter { get }
  unowned var target: FBiOSTarget { get }
  var format: FBiOSTargetFormat { get }
}

/**
 Conveniences for a Reporter.
 */
extension iOSReporter {
  public func report(_ eventName: EventName, _ eventType: EventType, _ subject: EventReporterSubject) {
    let subject = FBEventReporterSubject(
      target: self.target,
      format: self.format,
      name: eventName,
      type: eventType,
      subject: EventReporterSubjectBridge(subject)
    )
    self.reporter.report(subject)
  }

  public func reportValue(_ eventName: EventName, _ eventType: EventType, _ value: ControlCoreValue) {
    self.report(eventName, eventType, value.subject)
  }
}
