/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// A no-op `FBEventReporter`. It is the default reporter for the OSS implementation.
@objc public final class EmptyEventReporter: NSObject, FBEventReporter, @unchecked Sendable {

  @objc public static let shared = EmptyEventReporter()

  public var metadata: [String: String] { [:] }

  public override init() {
    super.init()
  }

  public func report(_ subject: FBEventReporterSubject) {}
  public func addMetadata(_ metadata: [String: String]) {}
}
