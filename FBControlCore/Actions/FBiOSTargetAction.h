/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBJSONConversion.h>

NS_ASSUME_NONNULL_BEGIN

@protocol FBiOSTarget;
@protocol FBTerminationHandle;

/**
 An extensible string enum representing an Action Type.
 */
typedef NSString *FBiOSTargetActionType NS_EXTENSIBLE_STRING_ENUM;

/**
 A Protocol that defines a fully serializable action that can be performed on an FBiOSTarget Instance.
 */
@protocol FBiOSTargetAction <NSObject, FBJSONSerializable, FBJSONDeserializable>

/**
 The Action Type of the Reciever.
 */
@property (nonatomic, class, copy, readonly) FBiOSTargetActionType actionType;

/**
 Runs the Action.

 @param target the target to run against.
 @param handleOut an outparam for the termination handle return value.
 @param error an error out for any error that occurs.
 */
- (BOOL)runWithTarget:(id<FBiOSTarget>)target handle:(id<FBTerminationHandle> _Nullable*_Nullable)handleOut error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
