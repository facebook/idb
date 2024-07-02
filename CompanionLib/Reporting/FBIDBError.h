/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>
#import <FBControlCore/FBControlCoreError.h>

NS_ASSUME_NONNULL_BEGIN

/**
 The Error Domain for idb.
 */
extern NSString *const FBIDBErrorDomain;

/**
 Helpers for constructing Errors representing errors in idb & adding additional diagnosis.
 */
@interface FBIDBError : FBControlCoreError

@end

NS_ASSUME_NONNULL_END
