/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

/**
 Provides known Instruction Set Architectures.
 */
typedef NSString *FBArchitecture NS_STRING_ENUM;

extern FBArchitecture _Nonnull const FBArchitectureI386;
extern FBArchitecture _Nonnull const FBArchitectureX86_64;
extern FBArchitecture _Nonnull const FBArchitectureArmv7;
extern FBArchitecture _Nonnull const FBArchitectureArmv7s;
extern FBArchitecture _Nonnull const FBArchitectureArm64;
extern FBArchitecture _Nonnull const FBArchitectureArm64e;
