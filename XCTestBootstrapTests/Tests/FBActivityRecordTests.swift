/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import XCTest
import XCTestBootstrap

/// `XCActivityRecord` lives in `XCTestPrivate`, which cannot be imported alongside `XCTest` (both define `XCTAttachment`/`XCTIssue`), so the input record is built and `+[FBActivityRecord from:]` is invoked through the Objective-C runtime.
final class FBActivityRecordTests: XCTestCase {

  // MARK: - Helpers

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

  private func wrapActivity(_ record: NSObject) -> FBActivityRecord {
    let selector = NSSelectorFromString("from:")
    guard let method = class_getClassMethod(FBActivityRecord.self, selector) else {
      preconditionFailure("FBActivityRecord +from: is missing; the class layout has changed.")
    }
    typealias FromIMP = @convention(c) (AnyClass, Selector, AnyObject) -> Unmanaged<AnyObject>
    let imp = method_getImplementation(method)
    let fromFn = unsafeBitCast(imp, to: FromIMP.self)
    let result = fromFn(FBActivityRecord.self, selector, record).takeUnretainedValue()
    guard let wrapped = result as? FBActivityRecord else {
      preconditionFailure("FBActivityRecord +from: returned an unexpected type.")
    }
    return wrapped
  }

  // MARK: - from(_:) field mapping

  func testFromXCActivityRecord_CopiesAllScalarFields() {
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

    XCTAssertEqual(fb.title, "Tap Login Button")
    XCTAssertEqual(fb.activityType, "com.apple.dt.xctest.activity-type.userCreated")
    XCTAssertEqual(fb.uuid, id)
    XCTAssertEqual(fb.start, start)
    XCTAssertEqual(fb.finish, finish)
  }

  func testFromXCActivityRecord_InitializesSubactivitiesAsEmptyMutableArray() {
    let record = makeXCActivityRecord()

    let fb = wrapActivity(record)

    XCTAssertEqual(fb.subactivities.count, 0, "Subactivities must start empty; from(_:) does not recursively wrap the source's nested records.")
    fb.subactivities.add(fb)
    XCTAssertEqual(fb.subactivities.count, 1, "from(_:) must seed subactivities with a mutable container, not an immutable copy.")
  }

  func testFromXCActivityRecord_WithoutAttachments_ProducesEmptyArray() {
    let record = makeXCActivityRecord(attachments: [])

    let fb = wrapActivity(record)

    XCTAssertEqual(fb.attachments.count, 0, "An XCActivityRecord with no attachments must yield an empty attachments array on the wrapper, not nil.")
  }

  func testFromXCActivityRecord_WrapsEachXCTAttachmentAsFBAttachment() {
    let first = XCTAttachment(string: "first-payload")
    first.name = "first.txt"
    let second = XCTAttachment(string: "second-payload")
    second.name = "second.txt"
    let record = makeXCActivityRecord(attachments: [first, second])

    let fb = wrapActivity(record)

    XCTAssertEqual(fb.attachments.count, 2, "Every XCTAttachment in record.attachments must be wrapped into one FBAttachment, preserving order.")
    XCTAssertEqual(fb.attachments[0].name, "first.txt", "Wrapped FBAttachment must preserve the source attachment's name.")
    XCTAssertEqual(fb.attachments[1].name, "second.txt", "Wrapped FBAttachment must preserve attachment order.")
  }

  // MARK: - description

  func testDescription_IncludesTitleStartFinishAndUUID() {
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

    XCTAssertTrue(description.contains("Tap Login Button"), "Description must include the title.")
    XCTAssertTrue(description.contains(id.uuidString), "Description must include the UUID's string form.")
    XCTAssertTrue(description.contains((start as NSDate).description), "Description must format `start` through NSDate's description.")
    XCTAssertTrue(description.contains((finish as NSDate).description), "Description must format `finish` through NSDate's description.")
  }
}
