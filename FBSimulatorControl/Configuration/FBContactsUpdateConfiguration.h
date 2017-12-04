/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

/**
 The Action Type for updating the Address Book
 */
extern FBiOSTargetFutureType const FBiOSTargetFutureTypeContactsUpdate;

/**
 The configuration for updating Address Book Contacts.
 */
@interface FBContactsUpdateConfiguration : NSObject <FBiOSTargetFuture, NSCopying>

/**
 The Designated Initializer.

 @param databaseDirectory the AddressBook Directory containing Address Book Databases
 @return a new Contacts Update Configuration.
 */
+ (instancetype)configurationWithDatabaseDirectory:(NSString *)databaseDirectory;

/**
 The local File Paths for updating the address book.
 */
@property (nonatomic, copy, readonly) NSString *databaseDirectory;

@end

NS_ASSUME_NONNULL_END

