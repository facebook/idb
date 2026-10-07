/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// An attachment recorded by an XCTest activity, copied out of XCTest's own `XCTAttachment`.
@objc public final class FBAttachment: NSObject {

  @objc public let payload: Data?
  @objc public let timestamp: Date?
  @objc public let name: String
  @objc public let uniformTypeIdentifier: String
  @objc public let userInfo: [String: Any]?

  /// `XCTAttachment` is read through KVC because the XCTest private headers are not importable from Swift.
  @objc(from:) public static func from(_ attachment: NSObject) -> FBAttachment {
    FBAttachment(attachment)
  }

  private init(_ attachment: NSObject) {
    let hasPayload = attachment.value(forKey: "hasPayload") as? Bool ?? false
    self.payload = hasPayload ? attachment.value(forKey: "payload") as? Data : nil
    self.timestamp = attachment.value(forKey: "timestamp") as? Date
    self.name = attachment.value(forKey: "name") as? String ?? ""
    self.uniformTypeIdentifier = attachment.value(forKey: "uniformTypeIdentifier") as? String ?? ""
    self.userInfo = attachment.value(forKey: "userInfo") as? [String: Any]
    super.init()
  }
}
