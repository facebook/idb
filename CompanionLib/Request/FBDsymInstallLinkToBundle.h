/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, FBDsymBundleType) {
  FBDsymBundleTypeXCTest,
  FBDsymBundleTypeApp,
};

/**
 Describes bundle needs to be linked with Dsym
 */
@interface FBDsymInstallLinkToBundle : NSObject

/**
 ID of the bundle the dsym needs to link
 */
@property (nonatomic, copy, readonly) NSString *bundle_id;

/**
 Type of bundle
*/
@property (nonatomic, assign, readonly) FBDsymBundleType bundle_type;

- (instancetype)initWith:(NSString *)bundle_id bundle_type:(FBDsymBundleType)bundle_type;

@end

NS_ASSUME_NONNULL_END
