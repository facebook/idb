/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

@class FBSimulatorApplication;
@class FBSimulatorConfiguration;
@class FBSimulatorControlConfiguration;
@class FBSimulatorPool;
@class FBSimulatorSession;

/**
 The Root Class for the FBSimulatorControl Framework.
 */
@interface FBSimulatorControl : NSObject

/**
 Returns a new `FBSimulatorControl` instance.

 @param configuration the Configuration to setup the instance with.
 @returns a new FBSimulatorControl instance.
 */
+ (instancetype)withConfiguration:(FBSimulatorControlConfiguration *)configuration;

/**
 Creates and returns a new FBSimulatorSession instance. Does not launch the Simulator or any Applications.

 @param simulatorConfiguration the Configuration of the Simulator to Launch.
 @param error an outparam for describing any error that occured during the creation of the Session.
 @returns A new `FBSimulatorSession` instance, or nil if an error occured.
 */
- (FBSimulatorSession *)createSessionForSimulatorConfiguration:(FBSimulatorConfiguration *)simulatorConfiguration error:(NSError **)error;

/**
 The Pool that the FBSimulatorControl instance uses.
 */
@property (nonatomic, strong, readonly) FBSimulatorPool *simulatorPool;

/**
 The Configuration that FBSimulatorControl uses.
 */
@property (nonatomic, copy, readwrite) FBSimulatorControlConfiguration *configuration;

@end
