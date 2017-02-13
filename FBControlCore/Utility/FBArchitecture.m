/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBArchitecture.h"

NSString *const FBArchitectureI386 = @"i386";
NSString *const FBArchitectureX86_64 = @"x86_64";
NSString *const FBArchitectureArmv7 = @"armv7";
NSString *const FBArchitectureArmv7s = @"armv7s";
NSString *const FBArchitectureArm64 = @"arm64";

@implementation FBArchitecture

+ (NSSet<NSString *> *)allArchitectures {
  return [NSSet setWithArray:@[
                               FBArchitectureI386,
                               FBArchitectureX86_64,
                               FBArchitectureArmv7,
                               FBArchitectureArmv7s,
                               FBArchitectureArm64,
                               ]];
}

@end
