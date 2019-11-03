/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
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
