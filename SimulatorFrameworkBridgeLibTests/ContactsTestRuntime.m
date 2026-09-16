/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "ContactsTestRuntime.h"

#import <SimulatorFrameworkBridgeLib/ContactsService+Testing.h>

@interface FBContactsTestRuntime ()
@property (nonatomic) NSUInteger fetches;
@property (nonatomic) NSUInteger requestCreations;
@property (nonatomic) NSUInteger saves;
@property (nonatomic) BOOL predicateMatches;
@property (nonatomic) NSUInteger fetchKeyCount;
@property (nonatomic) BOOL savedExpectedRequest;
@property (nonatomic, strong) CNSaveRequest *saveRequest;
@end

@interface FBFakeContactStore : CNContactStore
@property (nonatomic, weak) FBContactsTestRuntime *runtime;
@end

@implementation FBFakeContactStore
- (NSArray<CNContact *> *)unifiedContactsMatchingPredicate:(NSPredicate *)predicate keysToFetch:(NSArray<id<CNKeyDescriptor>> *)keys error:(NSError **)error
{
  self.runtime.fetches++;
  self.runtime.predicateMatches = [predicate evaluateWithObject:@"any object"];
  self.runtime.fetchKeyCount = keys.count;
  if (!self.runtime.contacts && error) {
    *error = [NSError errorWithDomain:@"ContactsTest" code:1 userInfo:nil];
  }
  return self.runtime.contacts;
}

- (BOOL)executeSaveRequest:(CNSaveRequest *)saveRequest error:(NSError **)error
{
  self.runtime.saves++;
  self.runtime.savedExpectedRequest = saveRequest == self.runtime.saveRequest;
  if (!self.runtime.saveSucceeds && error) {
    *error = [NSError errorWithDomain:@"ContactsTest" code:2 userInfo:nil];
  }
  return self.runtime.saveSucceeds;
}

@end

@interface FBFakeContactSaveRequest : CNSaveRequest
@property (nonatomic, weak) FBContactsTestRuntime *runtime;
@end

@implementation FBFakeContactSaveRequest
- (void)deleteContact:(CNMutableContact *)contact
{
  [self.runtime.deletedContacts addObject:contact];
}

@end

@implementation FBContactsTestRuntime
- (instancetype)init
{
  self = [super init];
  if (self) {
    _contacts = @[];
    _saveSucceeds = YES;
    _deletedContacts = [NSMutableArray array];
  }
  return self;
}

- (int)run
{
  FBFakeContactStore *store = [FBFakeContactStore new];
  store.runtime = self;
  return FBContactsClearWithStore(store, ^{
    self.requestCreations++;
    FBFakeContactSaveRequest *request = [FBFakeContactSaveRequest new];
    request.runtime = self;
    self.saveRequest = request;
    return request;
  });
}

@end
