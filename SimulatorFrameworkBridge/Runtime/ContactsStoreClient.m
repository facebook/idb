/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "ContactsStoreClient.h"

#if !TARGET_OS_TV
@implementation FBContactsStoreClient
{
  CNContactStore *_store;
}

- (instancetype)initWithStore:(CNContactStore *)store
{
  self = [super init];
  if (self) {
    _store = store;
  }
  return self;
}

- (NSArray<CNContact *> *)fetchContactsWithError:(NSError **)error
{
  return [_store unifiedContactsMatchingPredicate:[NSPredicate predicateWithValue:YES] keysToFetch:@[] error:error];
}

- (BOOL)executeSaveRequest:(CNSaveRequest *)request error:(NSError **)error
{
  return [_store executeSaveRequest:request error:error];
}

@end
#endif
