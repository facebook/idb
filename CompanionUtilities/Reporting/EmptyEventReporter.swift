/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// A no-op `EventReporter`. It is the default reporter for the OSS implementation.
public final class EmptyEventReporter: EventReporter, @unchecked Sendable {

  public static let shared = EmptyEventReporter()

  public var metadata: [String: String] { [:] }

  public init() {}

  public func report(_ subject: EventReporterSubject) {}
  public func addMetadata(_ metadata: [String: String]) {}
}
