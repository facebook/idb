/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

@class FBSimulatorSet;
@class FBDeviceSet;

/**
 A component that is repsonsible for notifying of updates to changes in the availability of iOS Targets.
 */
@interface FBiOSTargetStateChangeNotifier : NSObject

#pragma mark Initializers

/**
 A notifier that writes state updates to a file.
 The current set of targets is updated and the data is stored as an JSON array.

 @param filePath the filepath to write the updates to.
 @param targetSets the FBiOSTargetSets to monitor
 @param logger the logger to log to.
 @return a future that resolves when the notifier is created.
 */
+ (nonnull FBFuture<FBiOSTargetStateChangeNotifier *> *)notifierToFilePath:(nonnull NSString *)filePath withTargetSets:(nonnull NSArray<id<FBiOSTargetSet>> *)targetSets logger:(nonnull id<FBControlCoreLogger>)logger;

/**
 A notifier that writes state updates to stdout

 @param targetSets the FBiOSTargetSets to monitor
 @param logger the logger to log to.
 */
+ (nonnull FBFuture<FBiOSTargetStateChangeNotifier *> *)notifierToStdOutWithTargetSets:(nonnull NSArray<id<FBiOSTargetSet>> *)targetSets logger:(nonnull id<FBControlCoreLogger>)logger;

#pragma mark Public Methods

/**
 Start the Notifier. Will also first report the initial state of the provided sets.

 @return a Future that resolves when the notifier has started
 */
- (nonnull FBFuture<NSNull *> *)startNotifier;

#pragma mark Properties

/**
 A Future that resolves when the notifier has stopped notifying.
*/
@property (nonnull, nonatomic, readonly, strong) FBFuture<NSNull *> *notifierDone;

@end
