/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

/**
 A component that is repsonsible for notifying of updates to changes in the availability of iOS Targets.
 */
@interface FBiOSTargetStateChangeNotifier : NSObject

#pragma mark Initializers

/**
 The designated initializer.

 @param consumer the consumer to write updates to.
 @param logger the logger to log to.
 @return a new notifier instance.
 */
+ (instancetype)notifierWithConsumer:(id<FBDataConsumer>)consumer notifierForLogger:(id<FBControlCoreLogger>)logger;

/**
 A notifier that writes to stdout.

 @param logger the logger to log to.
 @return a new notifier instance.
 */
+ (instancetype)stdoutNotifierWithLogger:(id<FBControlCoreLogger>)logger;

#pragma mark Public Methods

/**
 Start the Notifier.

 @return a Future that resolves when the notifier has started. The result of the Future is a Future that resolves when the notifier finishes notifying.
 */
- (FBFuture<FBFuture<NSNull *> *> *)startNotifier;

@end

NS_ASSUME_NONNULL_END
