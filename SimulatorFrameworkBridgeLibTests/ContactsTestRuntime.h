/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Contacts/Contacts.h>

NS_ASSUME_NONNULL_BEGIN

@interface FBContactsTestRuntime : NSObject
@property (nullable, nonatomic, copy) NSArray<CNContact *> *contacts;
@property (nonatomic) BOOL saveSucceeds;
@property (nonatomic, readonly) NSUInteger fetches;
@property (nonatomic, readonly) NSUInteger requestCreations;
@property (nonatomic, readonly) NSUInteger saves;
@property (nonatomic, readonly) BOOL predicateMatches;
@property (nonatomic, readonly) NSUInteger fetchKeyCount;
@property (nonatomic, readonly) BOOL savedExpectedRequest;
@property (nonatomic, readonly) NSMutableArray<CNMutableContact *> *deletedContacts;
- (int)run;
@end

NS_ASSUME_NONNULL_END
