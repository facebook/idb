/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "NSError+XCTestBootstrap.h"

NSString *const XCTestBootstrapErrorDomain = @"com.facebook.XCTestBootstrap";

@implementation NSError (XCTestBootstrap)

+ (instancetype)XCTestBootstrapErrorWithDescription:(NSString *)description
{
  return [NSError
    errorWithDomain:XCTestBootstrapErrorDomain
    code:XCTestBootstrapErrorCodeGeneral
    userInfo:@{ NSLocalizedDescriptionKey : description}];
}

@end
