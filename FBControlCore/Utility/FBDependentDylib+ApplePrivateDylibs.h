/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <FBControlCore/FBDependentDylib.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Creates FBDependentDylib that represents private Apple dylibs that are
 required by ControlCore.
 */
@interface FBDependentDylib (ApplePrivateDylibs)

/**
 Swift dylibs required by some versions of Xcode.
 */
+ (NSArray<FBDependentDylib *> *)SwiftDylibs;

@end

NS_ASSUME_NONNULL_END
