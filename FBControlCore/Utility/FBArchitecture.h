/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString *const FBArchitectureI386;
extern NSString *const FBArchitectureX86_64;
extern NSString *const FBArchitectureArmv7;
extern NSString *const FBArchitectureArmv7s;
extern NSString *const FBArchitectureArm64;

/**
 Provides known Instruction Set Architectures.
 */
@interface FBArchitecture : NSObject

/**
 Provides string representation of all known Architectures.
 */
+ (NSSet<NSString *> *)allArchitectures;

@end

NS_ASSUME_NONNULL_END
