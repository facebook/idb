/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class FBDevice;
@protocol FBControlCoreLogger;

/**
 Fetches Devices from the list of Available Devices.
 */
@interface FBDeviceSet : NSObject

/**
 Returns the Default Device Set.

 @param error an error out for any error that occurs constructing the set.
 @return the Default Device Set if successful, NO otherwise.
 */
+ (instancetype)defaultSetWithLogger:(nullable id<FBControlCoreLogger>)logger error:(NSError **)error;

/**
 Fetches a Device with by a UDID.

 @param udid the UDID of the Device to Fetch.
 @return a Device with the specified UDID, if one exists.
 */
- (nullable FBDevice *)deviceWithUDID:(NSString *)udid;

/**
 All of the Available Devices.
 */
@property (nonatomic, copy, readonly) NSArray<FBDevice *> *allDevices;

@end

NS_ASSUME_NONNULL_END
