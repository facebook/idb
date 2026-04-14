/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>
#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@class FBDevice;

/**
 Fetches Devices from the list of Available Devices.
 */
@interface FBDeviceSet : NSObject <FBiOSTargetSet>

#pragma mark Initializers

/**
 The Designated Initializer.

 @param logger the logger to use.
 @param delegate a delegate that gets called when device status changes.
 @param ecidFilter a filter to restrict discovery to a single ECID.
 @param error an error out for any error that occurs constructing the set.
 @return the Default Device Set if successful, nil otherwise.
 */
+ (nullable instancetype)setWithLogger:(id<FBControlCoreLogger>)logger delegate:(nullable id<FBiOSTargetSetDelegate>)delegate ecidFilter:(nullable NSString *)ecidFilter error:(NSError **)error;

#pragma mark Querying

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

/**
 The Logger for the device set.
 */
@property (nonatomic, nullable, strong, readonly) id<FBControlCoreLogger> logger;

@end

NS_ASSUME_NONNULL_END
