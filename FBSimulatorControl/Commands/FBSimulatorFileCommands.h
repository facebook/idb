/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

@class FBSimulator;

@protocol FBSimulatorFileCommandsProtocol <NSObject>

/**
 Returns the File Container for the given container application

 @param bundleID the bundle ID to obtain the container for.
 @param error an error out for any error that occurs
 @return a container if the application exists, nil on error.
 */
- (nullable id<FBContainedFile>)containedFileForApplication:(nonnull NSString *)bundleID error:(NSError * _Nullable * _Nullable)error;

/**
 Returns a Contained File instance for group containers.

 @param error an error out for any error that occurs
 @return a FBContainedFile Instance
 */
- (nullable id<FBContainedFile>)containedFileForGroupContainersWithError:(NSError * _Nullable * _Nullable)error;

/**
 Returns a Contained File instance for application containers

 @param error an error out for any error that occurs
 @return a FBContainedFile Instance
 */
- (nullable id<FBContainedFile>)containedFileForApplicationContainersWithError:(NSError * _Nullable * _Nullable)error;

/**
 Returns the File Container for the root of the simulator

 @return a file container
 */
- (nonnull id<FBContainedFile>)containedFileForRootFilesystem;

@end

// FBSimulatorFileCommands class is now implemented in Swift.
// Note: We intentionally do NOT import the Swift header here because FBSimulator.h
// imports this header before FBSimulatorKeychainCommands.h, and the generated Swift
// header references FBSimulatorKeychainCommandsProtocol. The Swift class is accessible
// through the umbrella header FBSimulatorControl.h instead.
