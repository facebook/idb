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

/**
 Represents a failable transaction involving a Simulator.
 */
@protocol FBInteraction <NSObject>

/**
 Perform the given interaction.

 @param error an errorOut if any ocurred.
 @returns YES if the interaction succeeded, NO otherwise.
 */
- (BOOL)performInteractionWithError:(NSError **)error;

@end

/**
 Overridable class for providing an interaction-based API.
 */
@interface FBInteraction : NSObject <FBInteraction>

/**
 Retries the last chained interaction by `retries`, if it fails.
 */
- (instancetype)retry:(NSUInteger)retries;

/**
 Ignores any failure that occurs in the last interaction if any occured.
 */
- (instancetype)ignoreFailure;

@end
