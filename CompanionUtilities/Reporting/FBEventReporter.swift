/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

// The reporting types are `@objc` so the Objective-C companion can adopt and call
// them on Apple platforms. Objective-C interop is unavailable on Linux, where they
// are plain Swift types (idb-repl, the only Linux client, uses them from Swift).
#if canImport(ObjectiveC)
@objc(FBEventReporter)
public protocol FBEventReporter: NSObjectProtocol {

  /// Reports a Subject.
  @objc func report(_ subject: FBEventReporterSubject)

  /// Add metadata to attach to each report.
  @objc func addMetadata(_ metadata: [String: String])

  /// Gets the total metadata.
  @objc var metadata: [String: String] { get }
}
#else
public protocol FBEventReporter: NSObjectProtocol {

  /// Reports a Subject.
  func report(_ subject: FBEventReporterSubject)

  /// Add metadata to attach to each report.
  func addMetadata(_ metadata: [String: String])

  /// Gets the total metadata.
  var metadata: [String: String] { get }
}
#endif
