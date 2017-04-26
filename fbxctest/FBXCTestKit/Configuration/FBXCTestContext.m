/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBXCTestContext.h"

@implementation FBXCTestContext

+ (instancetype)contextWithReporter:(nullable id<FBXCTestReporter>)reporter logger:(nullable FBXCTestLogger *)logger
{
  return [[self alloc] initWithReporter:reporter logger:logger];
}

- (instancetype)initWithReporter:(nullable id<FBXCTestReporter>)reporter logger:(nullable FBXCTestLogger *)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _reporter = reporter;
  _logger = logger;

  return self;
}

@end
