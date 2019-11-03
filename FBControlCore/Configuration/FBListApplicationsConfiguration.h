/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBiOSTargetFuture.h>

NS_ASSUME_NONNULL_BEGIN

/**
 The Action Type for the Listing of Installed Applications.
 */
extern FBiOSTargetFutureType const FBiOSTargetFutureTypeListApplications;

/**
 The Target Action Class for the Listing of Installed Applications.
 */
@interface FBListApplicationsConfiguration : FBiOSTargetFutureSimple <FBiOSTargetFuture>

@end

NS_ASSUME_NONNULL_END
