/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>
#import <FBControlCore/FBiOSTarget.h>

NS_ASSUME_NONNULL_BEGIN

@protocol FBiOSTargetSet;

/**
 Delegate that informs of updates regarding the set of iOS Targets.
 */
@protocol FBiOSTargetSetDelegate

/**
 Called every time an iOS Target is added to the set.

 @param targetInfo the target info.
 @param targetSet the target set.
 */
- (void)targetAdded:(id<FBiOSTargetInfo>)targetInfo inTargetSet:(id<FBiOSTargetSet>)targetSet;

/**
 Called every time an iOS Target is removed from the set.

 @param targetInfo the target info.
 @param targetSet the target set.
 */
- (void)targetRemoved:(id<FBiOSTargetInfo>)targetInfo inTargetSet:(id<FBiOSTargetSet>)targetSet;

/**
 Called every time the target info is change.

 @param targetInfo the target info.
 @param targetSet the target set.
*/
- (void)targetUpdated:(id<FBiOSTargetInfo>)targetInfo inTargetSet:(id<FBiOSTargetSet>)targetSet;

@end

/**
 Common properties of of iOS Target Sets, shared by Simulator & Device Sets.
 */
@protocol FBiOSTargetSet <NSObject>

/**
 The Delegate of the Target Set.
 Used to report updates out.
 */
@property (nonatomic, weak, readwrite) id<FBiOSTargetSetDelegate> delegate;

/**
 Obtains all current targets infos within a set.
 */
@property (nonatomic, copy, readonly) NSArray<id<FBiOSTargetInfo>> *allTargetInfos;

/**
 Fetches a Target with by a UDID.

 @param udid the UDID of the Device to Fetch.
 @return a Target with the specified UDID, if one exists.
 */
- (nullable id<FBiOSTargetInfo>)targetWithUDID:(NSString *)udid;

@end

NS_ASSUME_NONNULL_END
