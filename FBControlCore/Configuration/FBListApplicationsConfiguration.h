/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBiOSTargetAction.h>

NS_ASSUME_NONNULL_BEGIN

/**
 The Action Type for the Listing of Installed Applications.
 */
extern FBiOSTargetActionType const FBiOSTargetActionTypeListApplications;

/**
 The Target Action Class for the Listing of Installed Applications.
 */
@interface FBListApplicationsConfiguration : FBiOSTargetActionSimple <FBiOSTargetFuture>

@end

NS_ASSUME_NONNULL_END
