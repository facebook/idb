/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
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
@interface FBXCTestShimConfiguration : NSObject <NSCopying>

/**
 Constructs or returned the singleton shim configuration

 @param logger to use for logging.
 @return a future wrapping the Shim Configuration.
 */
+ (FBFuture<FBXCTestShimConfiguration *> *)sharedShimConfigurationWithLogger:(nullable id<FBControlCoreLogger>)logger;

/**
 Constructs a Shim Configuration from the default base directory.

 @param logger to use for logging.
 @return a future wrapping the Shim Configuration.
 */
+ (FBFuture<FBXCTestShimConfiguration *> *)defaultShimConfigurationWithLogger:(nullable id<FBControlCoreLogger>)logger;

/**
 Constructs a Shim Configuration from the given base directory.

 @param directory the base directory of the shims
 @param logger to use for logging.
 @return a future wrapping the Shim Configuration.
 */
+ (FBFuture<FBXCTestShimConfiguration *> *)shimConfigurationWithDirectory:(NSString *)directory logger:(nullable id<FBControlCoreLogger>)logger;

/**
 The Designated Intializer.

 @param iosSimulatorTestShim The Path to he iOS Simulator Test Shim.
 @param macOSTestShimPath The Path to the macOS Test Shim.
 */
- (instancetype)initWithiOSSimulatorTestShimPath:(NSString *)iosSimulatorTestShim macOSTestShimPath:(NSString *)macOSTestShimPath;

#pragma mark Helpers

/**
 Determines the location of the shim directory, or fails

 @param queue the queue to use
 @param logger to use for logging.
 @return a Path to the Shim Configuration.
 */
+ (FBFuture<NSString *> *)findShimDirectoryOnQueue:(dispatch_queue_t)queue logger:(nullable id<FBControlCoreLogger>)logger;

#pragma mark Properties

/**
 The location of the shim used to run & list iOS Simulator Tests.
 */
@property (nonatomic, copy, readonly) NSString *iOSSimulatorTestShimPath;

/**
 The location of the shim used to run & list macOS Tests.
 */
@property (nonatomic, copy, readonly) NSString *macOSTestShimPath;

@end

NS_ASSUME_NONNULL_END
