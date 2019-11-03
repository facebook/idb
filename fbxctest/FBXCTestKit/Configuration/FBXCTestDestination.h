/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

/**
 The Base Destination.
 */
@interface FBXCTestDestination : NSObject <NSCopying, FBJSONSerializable, FBJSONDeserializable>

@end

/**
 A MacOSX Destination
 */
@interface FBXCTestDestinationMacOSX : FBXCTestDestination

@end

/**
 An iPhoneSimulator Destination
 */
@interface FBXCTestDestinationiPhoneSimulator : FBXCTestDestination

/**
 The Designated Initializer

 @param model the model of the device to use. If nil the default will be used.
 @param version the version to use. If nil the default will be used.
 @return a new iPhoneSimulator Destination.
 */
- (instancetype)initWithModel:(nullable FBDeviceModel)model version:(nullable FBOSVersionName)version;

/**
 The Device Model, if provided.
 */
@property (nonatomic, strong, nullable, readonly) FBDeviceModel model;

/**
 The Device OS Version, if provided.
 */
@property (nonatomic, strong, nullable, readonly) FBOSVersionName version;

@end

NS_ASSUME_NONNULL_END
