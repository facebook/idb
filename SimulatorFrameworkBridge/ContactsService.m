/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "ContactsService.h"
#import "ContactsService+Testing.h"

#import <Contacts/Contacts.h>
#import <Foundation/Foundation.h>

int FBContactsClearWithStore(CNContactStore *contactStore, CNSaveRequest *(^makeSaveRequest)(void))
{
  NSError *fetchError = nil;
  NSArray<CNContact *> *allContacts = [contactStore unifiedContactsMatchingPredicate:[NSPredicate predicateWithValue:YES]
                                                                         keysToFetch:@[]
                                                                               error:&fetchError];

  if (!allContacts) {
    NSLog(@"Failed to fetch contacts: %@", fetchError.localizedDescription);
    return 1;
  }

  NSLog(@"Found %lu contacts to delete", (unsigned long)allContacts.count);

  if (allContacts.count == 0) {
    NSLog(@"No contacts to delete");
    return 0;
  }

  CNSaveRequest *saveRequest = makeSaveRequest();
  for (CNContact *contact in allContacts) {
    CNMutableContact *mutableContact = [contact mutableCopy];
    [saveRequest deleteContact:mutableContact];
  }

  NSError *deleteError = nil;
  BOOL success = [contactStore executeSaveRequest:saveRequest error:&deleteError];

  if (!success) {
    NSLog(@"Failed to delete contacts: %@", deleteError.localizedDescription);
    return 1;
  }

  NSLog(@"Successfully deleted all contacts");
  return 0;
}

int handleContactsAction(NSString *action)
{
  if ([action isEqualToString:@"clear"]) {
    return FBContactsClearWithStore([[CNContactStore alloc] init], ^{ return [[CNSaveRequest alloc] init]; });
  } else {
    NSLog(@"Unknown action: %@", action);
    return 1;
  }
}
