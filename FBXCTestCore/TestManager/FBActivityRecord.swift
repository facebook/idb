/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation

/// An XCTest activity, copied out of XCTest's own `XCActivityRecord`.
/// Objective-C only constructs it with `from(_:)` and hands it to reporters.
@objc public final class FBActivityRecord: NSObject {

  public let title: String
  public let activityType: String
  public let uuid: UUID
  public let start: Date
  /// Equal to `start` for an activity that has not finished, consistent with its zero `duration`.
  public let finish: Date
  public let attachments: [FBAttachment]
  public let duration: Double
  public let name: String
  /// Starts empty; reporters nest records into it themselves.
  public var subactivities: [FBActivityRecord] = []

  /// `XCActivityRecord` is read through KVC because the XCTest private headers are not importable from Swift.
  @objc(from:) public static func from(_ record: NSObject) -> FBActivityRecord {
    FBActivityRecord(record)
  }

  private init(_ record: NSObject) {
    let start = record.value(forKey: "start") as? Date ?? Date()
    self.title = record.value(forKey: "title") as? String ?? ""
    self.activityType = record.value(forKey: "activityType") as? String ?? ""
    self.uuid = record.value(forKey: "uuid") as? UUID ?? UUID()
    self.start = start
    self.finish = record.value(forKey: "finish") as? Date ?? start
    let attachments = record.value(forKey: "attachments") as? [NSObject] ?? []
    self.attachments = attachments.map(FBAttachment.from)
    self.duration = record.value(forKey: "duration") as? Double ?? 0
    self.name = record.value(forKey: "name") as? String ?? ""
    super.init()
  }

  public override var description: String {
    String(format: "Title %@ | Duration %f | Start %@ | Finish %@ | Uuid %@", title, duration, start as NSDate, finish as NSDate, uuid as NSUUID)
  }
}
