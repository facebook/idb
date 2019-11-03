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
 The environment key for an override of the test shims directory.
 */
extern NSString *const FBXCTestShimDirectoryEnvironmentOverride;

/**
 A Configuration object for the location of the Test Shims.
 */
@interface FBXCTestShimConfiguration : NSObject <FBJSONSerializable, FBJSONDeserializable, NSCopying>

/**
 Constructs a Shim Configuration from the default base directory.

 @return a future wrapping the Shim Configuration.
 */
+ (FBFuture<FBXCTestShimConfiguration *> *)defaultShimConfiguration;

/**
 Constructs a Shim Configuration from the given base directory.

 @param directory the base directory of the shims
 @return a future wrapping the Shim Configuration.
 */
+ (FBFuture<FBXCTestShimConfiguration *> *)shimConfigurationWithDirectory:(NSString *)directory;

/**
 The Designated Intializer.

 @param iosSimulatorTestShim The Path to he iOS Simulator Test Shim.
 @param macOSTestShimPath The Path to the Mac Test Shim.
 @param macOSQueryShimPath The Path to the Mac Query Shim.
 */
- (instancetype)initWithiOSSimulatorTestShimPath:(NSString *)iosSimulatorTestShim macOSTestShimPath:(NSString *)macOSTestShimPath macOSQueryShimPath:(NSString *)macOSQueryShimPath;

#pragma mark Helpers

/**
 Determines the location of the shim directory, or fails

 @param queue the queue to use
 @return a Path to the Shim Configuration.
 */
+ (FBFuture<NSString *> *)findShimDirectoryOnQueue:(dispatch_queue_t)queue;

#pragma mark Properties

/**
 The location of the shim used to run iOS Simulator Logic Tests.
 */
@property (nonatomic, copy, readonly) NSString *iOSSimulatorTestShimPath;

/**
 The location of the shim used to run Mac Logic Tests.
 */
@property (nonatomic, copy, readonly) NSString *macOSTestShimPath;

/**
 The location of the shim used to query Mac Tests.
 */
@property (nonatomic, copy, readonly) NSString *macOSQueryShimPath;

@end

NS_ASSUME_NONNULL_END
