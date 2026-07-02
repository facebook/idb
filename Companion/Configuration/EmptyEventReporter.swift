/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBSimulatorControl
import Foundation

/// Mock class for OSS implementation. It is easier to have mock than to use optional everywhere.
@objc final class EmptyEventReporter: NSObject, FBEventReporter {

  @objc static let shared = EmptyEventReporter()

  var metadata: [String: String] = [:]

  func report(_ subject: FBEventReporterSubject) {}
  func addMetadata(_ metadata: [String: String]) {}
}
