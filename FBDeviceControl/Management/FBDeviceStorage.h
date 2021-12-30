/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>
#import <FBDeviceControl/FBAMDefines.h>

NS_ASSUME_NONNULL_BEGIN

@interface FBDeviceStorage<PublicDevice : id> : NSObject

#pragma mark Properties

/**
 A mapping of all referenced devices, keyed by identifier.
 */
@property (nonatomic, copy, readonly) NSDictionary<NSString *, PublicDevice> *attached;

/**
 A mapping of all referenced devices, keyed by identifier.
 */
@property (nonatomic, copy, readonly) NSDictionary<NSString *, PublicDevice> *referenced;

#pragma mark Public Methods

/**
 The Designated Initializer

 @param logger the logger to use.
 @return a storage instance.
 */
- (instancetype)initWithLogger:(id<FBControlCoreLogger>)logger;

/**
 Will attach the device to the collection

 @param device the device to add.
 @param key the key of the device
 */
- (void)deviceAttached:(PublicDevice)device forKey:(NSString *)key;

/**
 Will attach the device to the collection.
 If a device is still referenced, it can still be obtained later

 @param key the key of the device
 */
- (void)deviceDetachedForKey:(NSString *)key;

/**
 Obtains a device from the collection.
 If a device is still referenced, but not attached it will still be returned.

 @param key the key of the device
 @return a device, if present.
 */
- (nullable PublicDevice)deviceForKey:(NSString *)key;

@end

NS_ASSUME_NONNULL_END
