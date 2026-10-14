/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Contacts
import Foundation
import Testing

@Suite
struct ContactsMutationTests {
  @Test
  func clearRetriesAfterSaveFailureAndAcceptsAnEmptyStore() {
    let contact = CNMutableContact()
    contact.givenName = "Retry"
    let runtime = FBContactsTestRuntime()
    runtime.contacts = [contact]
    runtime.saveSucceeds = false

    #expect(runtime.run() == 1)
    #expect(runtime.saves == 1)
    #expect(runtime.deletedContacts.count == 1)

    runtime.saveSucceeds = true
    #expect(runtime.run() == 0)
    #expect(runtime.requestCreations == 2)
    #expect(runtime.saves == 2)
    #expect(runtime.deletedContacts.count == 2)
    #expect(runtime.savedExpectedRequest)

    runtime.contacts = []
    #expect(runtime.run() == 0)
    #expect(runtime.fetches == 3)
    #expect(runtime.requestCreations == 2)
    #expect(runtime.saves == 2)
  }

  @Test
  func emptyStoreDoesNotCreateOrExecuteADeletionRequest() {
    let runtime = FBContactsTestRuntime()
    #expect(runtime.run() == 0)
    #expect(runtime.fetches == 1)
    #expect(runtime.predicateMatches)
    #expect(runtime.fetchKeyCount == 0)
    #expect(runtime.requestCreations == 0)
    #expect(runtime.saves == 0)
    #expect(runtime.deletedContacts.count == 0)
  }

  @Test
  func fetchFailureDoesNotCreateOrExecuteADeletionRequest() {
    let runtime = FBContactsTestRuntime()
    runtime.contacts = nil
    #expect(runtime.run() == 1)
    #expect(runtime.fetches == 1)
    #expect(runtime.requestCreations == 0)
    #expect(runtime.saves == 0)
    #expect(runtime.deletedContacts.count == 0)
  }

  @Test
  func deletesMutableCopiesInOneRequestAndPropagatesSaveResult() throws {
    for succeeds in [true, false] {
      let first = CNMutableContact()
      first.givenName = "First"
      let second = CNMutableContact()
      second.givenName = "Second"
      let runtime = FBContactsTestRuntime()
      runtime.contacts = [first, second]
      runtime.saveSucceeds = succeeds
      #expect(runtime.run() == (succeeds ? 0 : 1))
      #expect(runtime.fetches == 1)
      #expect(runtime.predicateMatches)
      #expect(runtime.fetchKeyCount == 0)
      #expect(runtime.requestCreations == 1)
      #expect(runtime.saves == 1)
      #expect(runtime.savedExpectedRequest)
      #expect(runtime.deletedContacts.count == 2)
      let deleted = try #require(runtime.deletedContacts as? [CNMutableContact])
      #expect(deleted.map(\.givenName) == ["First", "Second"])
      #expect(deleted[0] !== first)
      #expect(deleted[1] !== second)
      #expect(first.givenName == "First")
      #expect(second.givenName == "Second")
    }
  }
}
