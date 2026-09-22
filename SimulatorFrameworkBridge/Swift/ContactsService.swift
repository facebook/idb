/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#if !os(tvOS)
import Contacts
import Foundation

#if canImport(SimulatorFrameworkBridgeRuntime)
@_implementationOnly import SimulatorFrameworkBridgeRuntime
#endif

private func FBContactsClearWithStore(contactStore: CNContactStore, makeSaveRequest: () -> CNSaveRequest) -> Int {
  let client = FBContactsStoreClient(store: contactStore)
  var fetchError: NSError?
  let allContacts = client.fetchContacts(error: &fetchError)

  guard let allContacts else {
    NSLog("Failed to fetch contacts: %@", fetchError?.localizedDescription ?? "(null)")
    return 1
  }

  NSLog("Found %lu contacts to delete", UInt(allContacts.count))

  if allContacts.isEmpty {
    NSLog("No contacts to delete")
    return 0
  }

  let saveRequest = makeSaveRequest()
  for contact in allContacts {
    guard let mutableContact = contact.mutableCopy() as? CNMutableContact else {
      return 1
    }
    saveRequest.delete(mutableContact)
  }

  var deleteError: NSError?
  let success = client.execute(saveRequest, error: &deleteError)

  guard success else {
    NSLog("Failed to delete contacts: %@", deleteError?.localizedDescription ?? "(null)")
    return 1
  }

  NSLog("Successfully deleted all contacts")
  return 0
}

@objc public final class ContactsServiceStaticFuncs: NSObject {
  @objc(clearWithStore:makeSaveRequest:)
  public static func clear(with store: CNContactStore, makeSaveRequest: () -> CNSaveRequest) -> Int {
    FBContactsClearWithStore(contactStore: store, makeSaveRequest: makeSaveRequest)
  }

  @objc(handleContactsAction:)
  public static func handleContactsAction(action: String) -> Int {
    if action == "clear" {
      return FBContactsClearWithStore(
        contactStore: CNContactStore(),
        makeSaveRequest: {
          CNSaveRequest()
        }
      )
    } else {
      NSLog("Unknown action: %@", action)
      return 1
    }
  }
}
#endif
