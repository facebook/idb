/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

import Foundation
import FBSimulatorControl

extension FBSimulatorState {
  public var description: String {
    get {
      return FBSimulator.stateStringFromSimulatorState(self)
    }
  }
}

public typealias ControlCoreValue = protocol<FBJSONSerializable, CustomStringConvertible>

@objc public class ControlCoreLoggerBridge : NSObject {
  let reporter: EventReporter

  init(reporter: EventReporter) {
    self.reporter = reporter
  }

  @objc public func log(level: Int32, string: String) {
    let subject = LogSubject(logString: string, level: level)
    self.reporter.report(subject)
  }
}

extension String : CustomStringConvertible {
  public var description: String { get {
    return self
  }}
}
