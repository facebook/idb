/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

@class FBSimulator;

@protocol FBSimulatorFileCommands <NSObject>

/**
 Returns the File Container for the given container application
 
 @param bundleID the bundle ID to obtain the container for.
 @param error an error out for any error that occurs
 @return a container if the application exists, nil on error.
 */
- (nullable id<FBContainedFile>)containedFileForApplication:(NSString *)bundleID error:(NSError **)error;

/**
 Returns the File Container for the root of the simulator
 
 @return a file container
 */
- (id<FBContainedFile>)containedFileForRootFilesystem;

@end

/**
 An implementation of FBFileCommands for Simulators
 */
@interface FBSimulatorFileCommands : NSObject <FBFileCommands, FBSimulatorFileCommands, FBiOSTargetCommand>

@end

NS_ASSUME_NONNULL_END
