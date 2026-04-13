/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

@objc(FBEventReporter)
public protocol FBEventReporter: NSObjectProtocol {

  /// Reports a Subject.
  @objc func report(_ subject: FBEventReporterSubject)

  /// Add metadata to attach to each report.
  @objc func addMetadata(_ metadata: [String: String])

  /// Gets the total metadata.
  @objc var metadata: [String: String] { get }
}
