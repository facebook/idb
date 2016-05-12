/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "XCTestBootstrapError.h"

NSString *const XCTestBootstrapErrorDomain = @"com.facebook.XCTestBootstrap";

const NSInteger XCTestBootstrapErrorCodeStartupFailure = 0x3;
const NSInteger XCTestBootstrapErrorCodeLostConnection = 0x4;

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
