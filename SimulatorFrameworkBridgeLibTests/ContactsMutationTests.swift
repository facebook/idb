/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Contacts
import XCTest

final class ContactsMutationTests: XCTestCase {
  func testEmptyStoreDoesNotCreateOrExecuteADeletionRequest() {
    let runtime = FBContactsTestRuntime()
    XCTAssertEqual(runtime.run(), 0)
    XCTAssertEqual(runtime.fetches, 1)
    XCTAssertTrue(runtime.predicateMatches)
    XCTAssertEqual(runtime.fetchKeyCount, 0)
    XCTAssertEqual(runtime.requestCreations, 0)
    XCTAssertEqual(runtime.saves, 0)
    XCTAssertEqual(runtime.deletedContacts.count, 0)
  }

  func testFetchFailureDoesNotCreateOrExecuteADeletionRequest() {
    let runtime = FBContactsTestRuntime()
    runtime.contacts = nil
    XCTAssertEqual(runtime.run(), 1)
    XCTAssertEqual(runtime.fetches, 1)
    XCTAssertEqual(runtime.requestCreations, 0)
    XCTAssertEqual(runtime.saves, 0)
    XCTAssertEqual(runtime.deletedContacts.count, 0)
  }

  func testDeletesMutableCopiesInOneRequestAndPropagatesSaveResult() throws {
    for succeeds in [true, false] {
      let first = CNMutableContact()
      first.givenName = "First"
      let second = CNMutableContact()
      second.givenName = "Second"
      let runtime = FBContactsTestRuntime()
      runtime.contacts = [first, second]
      runtime.saveSucceeds = succeeds
      XCTAssertEqual(runtime.run(), succeeds ? 0 : 1)
      XCTAssertEqual(runtime.fetches, 1)
      XCTAssertTrue(runtime.predicateMatches)
      XCTAssertEqual(runtime.fetchKeyCount, 0)
      XCTAssertEqual(runtime.requestCreations, 1)
      XCTAssertEqual(runtime.saves, 1)
      XCTAssertTrue(runtime.savedExpectedRequest)
      XCTAssertEqual(runtime.deletedContacts.count, 2)
      let deleted = try XCTUnwrap(runtime.deletedContacts as? [CNMutableContact])
      XCTAssertEqual(deleted.map(\.givenName), ["First", "Second"])
      XCTAssertFalse(deleted[0] === first)
      XCTAssertFalse(deleted[1] === second)
      XCTAssertEqual(first.givenName, "First")
      XCTAssertEqual(second.givenName, "Second")
    }
  }
}
