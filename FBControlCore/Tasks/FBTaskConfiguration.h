/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBProcessLaunchConfiguration.h>

NS_ASSUME_NONNULL_BEGIN

@class FBProcessIO;

@protocol FBControlCoreLogger;

/**
 A Configuration for an FBTask.
 */
@interface FBTaskConfiguration : FBProcessLaunchConfiguration

/**
 Creates a Task Configuration with the provided parameters.
 */
- (instancetype)initWithLaunchPath:(NSString *)launchPath arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment io:(FBProcessIO *)io;

/**
 The Launch Path of the Process to launch.
 */
@property (nonatomic, copy, readonly) NSString *launchPath;

@end

NS_ASSUME_NONNULL_END
