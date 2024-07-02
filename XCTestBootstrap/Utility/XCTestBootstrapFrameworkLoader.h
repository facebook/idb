/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

/**
 Framework and Class Loading for XCTestBoostrap.
 */
@interface XCTestBootstrapFrameworkLoader : FBControlCoreFrameworkLoader

/**
 All of the Frameworks for XCTestBootstrap.
 */
@property (nonatomic, strong, class, readonly) XCTestBootstrapFrameworkLoader *allDependentFrameworks;

@end
