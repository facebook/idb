/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import FBXCTestCore
import Foundation
import Testing
import XCTest

/// `XCActivityRecord` lives in `XCTestPrivate`, which cannot be imported alongside `XCTest` (both define `XCTAttachment`/`XCTIssue`), so the input record is built through the Objective-C runtime.
@Suite
struct ActivityRecordTests {

  private func makeXCActivityRecord(
    title: String = "Activity Title",
    activityType: String = "com.apple.dt.xctest.activity-type.userCreated",
    uuid: UUID = UUID(),
    start: Date = Date(timeIntervalSince1970: 1_000_000),
    finish: Date = Date(timeIntervalSince1970: 1_000_010),
    attachments: [XCTAttachment] = []
  ) -> NSObject {
    guard let recordClass = NSClassFromString("XCActivityRecord") as? NSObject.Type else {
      preconditionFailure("XCActivityRecord is not available at runtime; XCTest.framework must be linked.")
    }
    let record = recordClass.init()
    record.setValue(title, forKey: "title")
    record.setValue(activityType, forKey: "activityType")
    record.setValue(uuid, forKey: "uuid")
    record.setValue(start, forKey: "start")
    record.setValue(finish, forKey: "finish")
    // Not KVC-compliant for the readonly `attachments` key; go through `addAttachment:`.
    let addAttachment = NSSelectorFromString("addAttachment:")
    for attachment in attachments {
      record.perform(addAttachment, with: attachment)
    }
    return record
  }

  private func wrapActivity(_ record: NSObject) -> ActivityRecord {
    ActivityRecord.from(record)
  }

  // MARK: - from(_:) field mapping

  @Test
  func fromXCActivityRecord_CopiesAllScalarFields() {
    let id = UUID()
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let finish = Date(timeIntervalSince1970: 1_700_000_042)
    let record = makeXCActivityRecord(
      title: "Tap Login Button",
      activityType: "com.apple.dt.xctest.activity-type.userCreated",
      uuid: id,
      start: start,
      finish: finish
    )

    let fb = wrapActivity(record)

    #expect(fb.title == "Tap Login Button")
    #expect(fb.activityType == "com.apple.dt.xctest.activity-type.userCreated")
    #expect(fb.uuid == id)
    #expect(fb.start == start)
    #expect(fb.finish == finish)
  }

  @Test
  func fromXCActivityRecord_InitializesSubactivitiesAsEmpty() {
    let record = makeXCActivityRecord()

    let fb = wrapActivity(record)

    #expect(fb.subactivities.count == 0, "Subactivities must start empty; from(_:) does not recursively wrap the source's nested records.")
    fb.subactivities.append(fb)
    #expect(fb.subactivities.count == 1, "Reporters nest records into subactivities after from(_:).")
  }

  @Test
  func fromXCActivityRecord_WithoutAttachments_ProducesEmptyArray() {
    let record = makeXCActivityRecord(attachments: [])

    let fb = wrapActivity(record)

    #expect(fb.attachments.count == 0, "An XCActivityRecord with no attachments must yield an empty attachments array on the wrapper, not nil.")
  }

  @Test
  func fromXCActivityRecord_WrapsEachXCTAttachmentAsFBAttachment() {
    let first = XCTAttachment(string: "first-payload")
    first.name = "first.txt"
    let second = XCTAttachment(string: "second-payload")
    second.name = "second.txt"
    let record = makeXCActivityRecord(attachments: [first, second])

    let fb = wrapActivity(record)

    #expect(fb.attachments.count == 2, "Every XCTAttachment in record.attachments must be wrapped into one Attachment, preserving order.")
    #expect(fb.attachments[0].name == "first.txt", "Wrapped Attachment must preserve the source attachment's name.")
    #expect(fb.attachments[1].name == "second.txt", "Wrapped Attachment must preserve attachment order.")
  }

  // MARK: - description

  @Test
  func description_IncludesTitleStartFinishAndUUID() {
    let id = UUID()
    let start = Date(timeIntervalSince1970: 500)
    let finish = Date(timeIntervalSince1970: 700)
    let record = makeXCActivityRecord(
      title: "Tap Login Button",
      uuid: id,
      start: start,
      finish: finish
    )

    let description = wrapActivity(record).description

    #expect(description.contains("Tap Login Button"), "Description must include the title.")
    #expect(description.contains(id.uuidString), "Description must include the UUID's string form.")
    #expect(description.contains((start as NSDate).description), "Description must format `start` through NSDate's description.")
    #expect(description.contains((finish as NSDate).description), "Description must format `finish` through NSDate's description.")
  }
}
