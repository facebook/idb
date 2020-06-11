/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

@protocol FBJSONSerializable, FBJSONDeserializable;

/**
 A value type that holds values for serializing a target information in idb
 */
@interface FBiOSTargetDescription : NSObject <FBJSONSerializable, NSCopying>

/**
 The Designated Initializer.

 @param target the target to construct an update for.
 @return a new Target Update
 */
- (instancetype)initWithTarget:(id<FBiOSTargetInfo>)target;

/**
 The UDID of the Target.
*/
@property (nonatomic, copy, readonly) NSString *udid;

@end
