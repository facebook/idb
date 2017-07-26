/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "XCTestBootstrapFrameworkLoader.h"

@implementation XCTestBootstrapFrameworkLoader

#pragma mark Initializers

+ (instancetype)allDependentFrameworks
{
  static dispatch_once_t onceToken;
  static XCTestBootstrapFrameworkLoader *loader;
  dispatch_once(&onceToken, ^{
    loader = [XCTestBootstrapFrameworkLoader loaderWithName:@"XCTestBootstrap" frameworks:@[
      FBWeakFramework.DTXConnectionServices,
      FBWeakFramework.XCTest,
    ]];
  });
  return loader;
}

@end
