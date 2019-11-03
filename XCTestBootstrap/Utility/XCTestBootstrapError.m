/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "XCTestBootstrapError.h"

NSString *const XCTestBootstrapErrorDomain = @"com.facebook.XCTestBootstrap";

const NSInteger XCTestBootstrapErrorCodeStartupFailure = 0x3;
const NSInteger XCTestBootstrapErrorCodeLostConnection = 0x4;
const NSInteger XCTestBootstrapErrorCodeStartupTimeout = 0x5;

@implementation XCTestBootstrapError

- (instancetype)init
{
  self = [super init];
  if (!self) {
    return nil;
  }

  [self inDomain:XCTestBootstrapErrorDomain];

  return self;
}

@end

NSString *const FBTestErrorDomain = @"com.facebook.FBTestError";

@implementation FBXCTestError

- (instancetype)init
{
  self = [super init];
  if (self) {
    [self inDomain:FBTestErrorDomain];
  }
  return self;
}

@end
