/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

public protocol FBEventReporter: AnyObject {

  /// Reports a Subject.
  func report(_ subject: FBEventReporterSubject)

  /// Add metadata to attach to each report.
  func addMetadata(_ metadata: [String: String])

  /// Gets the total metadata.
  var metadata: [String: String] { get }
}
