/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <XCTestBootstrap/FBXCTestPreparationStrategy.h>

NS_ASSUME_NONNULL_BEGIN

@class FBTestLaunchConfiguration;
@class FBXCTestShimConfiguration;

@protocol FBFileManager;
@protocol FBCodesignProvider;

/**
 Strategy used to run XCTest with Simulators.
 It will copy the Test Bundle to a working directory and update with an appropriate xctestconfiguration.
 */
@interface FBSimulatorTestPreparationStrategy : NSObject <FBXCTestPreparationStrategy>

#pragma mark Initializers

/**
 Creates and returns a Strategy strategyWith given paramenters.

 @param testLaunchConfiguration configuration used to launch test.
 @param workingDirectory directory used to prepare all bundles.
 @param fileManager file manager used to prepare all bundles.
 @param codesign a codesign provider
 @return A new FBSimulatorTestRunStrategy Instance.
 */
+ (instancetype)strategyWithTestLaunchConfiguration:(FBTestLaunchConfiguration *)testLaunchConfiguration
                                              shims:(FBXCTestShimConfiguration *)shims
                                   workingDirectory:(NSString *)workingDirectory
                                        fileManager:(id<FBFileManager>)fileManager
                                           codesign:(id<FBCodesignProvider>)codesign;

@end

NS_ASSUME_NONNULL_END
