/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBSimulatorControl/FBInteraction.h>

@class FBAgentLaunchConfiguration;
@class FBApplicationLaunchConfiguration;
@class FBSimulator;
@class FBSimulatorApplication;
@class FBSimulatorBinary;
@class FBSimulatorSession;
@class FBSimulatorSessionLifecycle;
@protocol FBSimulatorWindowTilingStrategy;

/**
 The Concrete Interactions for a Simulator Session.
 Successive applications of interactions will occur in the order that they are sequenced.
 Interactions have no effect until `performInteractionWithError:` is called.
 */
@interface FBSimulatorSessionInteraction : FBInteraction

/**
 Creates a new instance of the Interaction Builder.
 */
+ (instancetype)builderWithSession:(FBSimulatorSession *)session;

/**
 Boots the simulator.
 */
- (instancetype)bootSimulator;

/**
 Tiles the Simulator according to the 'tilingStrategy'.
 */
- (instancetype)tileSimulator:(id<FBSimulatorWindowTilingStrategy>)tilingStrategy;

/**
 Tiles the Simulator according to the occlusion other Simulators.
 */
- (instancetype)tileSimulator;

/**
 Records Video of the Simulator, until the Session is terminated.
 */
- (instancetype)recordVideo;

/**
 Uploads photos to the Camera Roll of the Simulator

 @param photoPaths photoPaths an NSArray<NSString *> of File Paths for the Photos to Upload.
 */
- (instancetype)uploadPhotos:(NSArray *)photoPaths;

/**
 Uploads videos to the Camera Roll of the Simulator

 @param videoPaths an NSArray<NSString *> of File Paths for the Videos to Upload.
 */
- (instancetype)uploadVideos:(NSArray *)videoPaths;

/**
 Installs the given Application.
 */
- (instancetype)installApplication:(FBSimulatorApplication *)application;

/**
 Launches the Application with the given Configuration.
 */
- (instancetype)launchApplication:(FBApplicationLaunchConfiguration *)appLaunch;

/**
 Unix Signals the Application.
 */
- (instancetype)signal:(int)signal application:(FBSimulatorApplication *)application;

/**
 Kills the provided Application.
 */
- (instancetype)killApplication:(FBSimulatorApplication *)application;

/**
 Launches the provided Agent with the given Configuration.
 */
- (instancetype)launchAgent:(FBAgentLaunchConfiguration *)agentLaunch;

/**
 Launches the provided Agent.
 */
- (instancetype)killAgent:(FBSimulatorBinary *)agent;

/**
 Opens the provided URL on the Device
 */
- (instancetype)openURL:(NSURL *)url;

@end
