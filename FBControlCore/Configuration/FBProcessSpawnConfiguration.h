/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBProcessLaunchConfiguration.h>

NS_ASSUME_NONNULL_BEGIN

/**
 An enum representing how an process should be launched.
 */
typedef NS_ENUM(NSUInteger, FBProcessSpawnMode) {
  FBProcessSpawnModeDefault = 0,
  FBProcessSpawnModePosixSpawn = 1,
  FBProcessSpawnModeLaunchd = 2,
};

/**
 A configuration for spawning an executable.
 */
@interface FBProcessSpawnConfiguration <StdInType : id, StdOutType : id, StdErrType : id> : FBProcessLaunchConfiguration <StdInType, StdOutType, StdErrType>

/**
 The designated initializer.

 @param launchPath the path to the executable to launch.
 @param arguments an array-of-strings of arguments to the process. Must not be nil.
 @param environment a Dictionary, mapping Strings to Strings of the Environment to set in the launched Application process. Must not be nil.
 @param io the output configuration for the launched process.
 @param mode the launch mode to use.
 @return a new Configuration Object with the arguments applied.
 */
- (instancetype)initWithLaunchPath:(NSString *)launchPath arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment io:(FBProcessIO<StdInType, StdOutType, StdErrType> *)io mode:(FBProcessSpawnMode)mode;

/**
 The Binary Path of the process to Launch.
 */
@property (nonatomic, copy, readonly) NSString *launchPath;

/**
 How the process should be launched.
 */
@property (nonatomic, assign, readonly) FBProcessSpawnMode mode;

/**
 The name of the launched process, effectively the argv[0] of the launched process.
 */
@property (nonatomic, copy, readonly) NSString *processName;

@end

NS_ASSUME_NONNULL_END
