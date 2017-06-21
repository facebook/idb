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
 The Base Destination.
 */
@interface FBXCTestDestination : NSObject <NSCopying, FBJSONSerializable, FBJSONDeserializable>

/**
 The Path to the xctest executable.
 */
@property (nonatomic, copy, readonly) NSString *xctestPath;

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
