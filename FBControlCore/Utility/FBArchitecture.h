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

/**
 Provides known Instruction Set Architectures.
 */
typedef NSString *FBArchitecture NS_STRING_ENUM;

extern FBArchitecture const FBArchitectureI386;
extern FBArchitecture const FBArchitectureX86_64;
extern FBArchitecture const FBArchitectureArmv7;
extern FBArchitecture const FBArchitectureArmv7s;
extern FBArchitecture const FBArchitectureArm64;

NS_ASSUME_NONNULL_END
