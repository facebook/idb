/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>
#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

/**
 The BootManager boots iOS Simulators
 */
@interface FBBootManager : NSObject

/**
 The Designated Initializer

 @param logger the logger to us.
 */
+ (instancetype)bootManagerForLogger:(id<FBControlCoreLogger>)logger;

/**
 Boot a target.

 @return a Future that resolves when the target has booted.
 */
- (FBFuture<NSNull *> *)boot:(NSString *)udid;

@end

NS_ASSUME_NONNULL_END
