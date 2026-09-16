/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
void FBHealthSetClassLookupForTesting(Class _Nullable (^_Nullable lookup)(NSString *name));
NS_ASSUME_NONNULL_END
