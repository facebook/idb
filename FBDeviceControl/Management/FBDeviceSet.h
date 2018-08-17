/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>
#import <FBControlCore/FBiOSTargetSet.h>

NS_ASSUME_NONNULL_BEGIN

@class FBDevice;
@class FBiOSTargetQuery;
@protocol FBControlCoreLogger;
@protocol FBiOSTargetSetDelegate;

/**
 Fetches Devices from the list of Available Devices.
 */
@interface FBDeviceSet : NSObject <FBiOSTargetSet>

#pragma mark Initializers

/**
 Returns the Default Device Set.

 @param error an error out for any error that occurs constructing the set.
 @param delegate a delegate that gets called when device status changes.
 @return the Default Device Set if successful, nil otherwise.
 */
+ (nullable instancetype)defaultSetWithLogger:(nullable id<FBControlCoreLogger>)logger error:(NSError **)error delegate:(nullable id<FBiOSTargetSetDelegate>)delegate;

/**
 Returns the Default Device Set.

@param error an error out for any error that occurs constructing the set.
@return the Default Device Set if successful, nil otherwise.
*/
+ (nullable instancetype)defaultSetWithLogger:(nullable id<FBControlCoreLogger>)logger error:(NSError **)error;

#pragma mark Querying

/**
 Fetches the Simulators from the Set, matching the query.

 @param query the Query to query with.
 @return an array of matching Simulators.
 */
- (NSArray<FBDevice *> *)query:(FBiOSTargetQuery *)query;

/**
 Fetches a Device with by a UDID.

 @param udid the UDID of the Device to Fetch.
 @return a Device with the specified UDID, if one exists.
 */
- (nullable FBDevice *)deviceWithUDID:(NSString *)udid;

#pragma mark Properties

/**
 All of the Available Devices.
 */
@property (nonatomic, copy, readonly) NSArray<FBDevice *> *allDevices;

@end

NS_ASSUME_NONNULL_END
