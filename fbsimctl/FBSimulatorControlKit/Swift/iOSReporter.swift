/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/**
 A Protocol for Commands to access and report about an iOS Target.
 */
public protocol iOSReporter: class {
  var reporter: EventReporter { get }
  var target: FBiOSTarget { get }
  var format: FBiOSTargetFormat { get }
}

/**
 Conveniences for a Reporter.
 */
extension iOSReporter {
  public func report(_ eventName: EventName, _ eventType: EventType, _ subject: EventReporterSubject) {
    let subject = FBEventReporterSubject(
      target: target,
      format: format,
      name: eventName,
      type: eventType,
      subject: subject
    )
    reporter.report(subject)
  }

  public func reportValue(_ eventName: EventName, _ eventType: EventType, _ value: ControlCoreValue) {
    report(eventName, eventType, value.subject)
  }
}
