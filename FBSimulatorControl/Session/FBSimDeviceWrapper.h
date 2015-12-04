/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

@protocol FBProcessInfo;
@class SimDevice;
@class FBProcessQuery;

/**
 Augments SimDevice.
 */
@interface FBSimDeviceWrapper : NSObject

/**
 Creates a SimDevice Wrapper.

 @param device the device to wrap
 @param processQuery the Process Query to obtain process information.
 @return a new SimDevice wrapper.
 */
+ (instancetype)withSimDevice:(SimDevice *)device processQuery:(FBProcessQuery *)processQuery;

/**
 Boots an Application, timing out if CoreSimulator gets stuck in a semaphore.

 @param appID the Application ID to use.
 @param options the Options to use in the launch.
 @param error an error out for any error that occured.
 @return the Process Identifier of the launched process, -1 otherwise.
 */
- (id<FBProcessInfo>)launchApplicationWithID:(NSString *)appID options:(NSDictionary *)options error:(NSError **)error;

/**
 Installs an Application, timing out if CoreSimulator gets stuck in a semaphore.

 @param appURL the Application URL to use.
 @param options the Options to use in the launch.
 @param error an error out for any error that occured.
 @return YES if the Application was installed successfully, NO otherwise.
 */
- (BOOL)installApplication:(NSURL *)appURL withOptions:(NSDictionary *)options error:(NSError **)error;

/**
 Spawns a binary, timing out if CoreSimulator gets stuck in a semaphore.

 @param launchPath the path to the binary.
 @param options the Options to use in the launch.
 @param terminationHandler ?????
 @param error an error out for any error that occured.
 @return the Process Identifier of the launched process, -1 otherwise.
 */
- (id<FBProcessInfo>)spawnWithPath:(NSString *)launchPath options:(NSDictionary *)options terminationHandler:(id)terminationHandler error:(NSError **)error;

@end
