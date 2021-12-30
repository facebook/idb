/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

/**
 A value type that holds values for serializing a target information in idb
 */
@interface FBiOSTargetDescription : NSObject <FBiOSTargetInfo, NSCopying>

/**
 The Designated Initializer.

 @param target the target to construct an update for.
 @return a new Target Update
 */
- (instancetype)initWithTarget:(id<FBiOSTargetInfo>)target;

/**
 A JSON Dictionary representing the target description.
 */
@property (nonatomic, copy, readonly) NSDictionary<NSString *, id> *asJSON;

@end
