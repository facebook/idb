/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>
#import <XCTestBootstrap/FBXCTestPreparationStrategy.h>

@class FBTestLaunchConfiguration;
@class FBXCTestShimConfiguration;

@protocol FBFileManager;
@protocol FBCodesignProvider;

/**
 Strategy used to run XCTest with MacOSX.
 It will copy the Test Bundle to a working directory and update with an appropriate xctestconfiguration.
 */

@interface FBMacTestPreparationStrategy : NSObject <FBXCTestPreparationStrategy>

/**
 Creates and returns a Strategy strategyWith given paramenters.
 Will use default implementations of the File Manager and Codesign.

 @param testLaunchConfiguration configuration used to launch test.
 @param workingDirectory directory used to prepare all bundles.
 @return A new FBSimulatorTestRunStrategy Instance.
 */
+ (instancetype)strategyWithTestLaunchConfiguration:(FBTestLaunchConfiguration *)testLaunchConfiguration
                                   workingDirectory:(NSString *)workingDirectory;

/**
 Creates and returns a Strategy strategyWith given paramenters.

 @param testLaunchConfiguration configuration used to launch test.
 @param shims shim configuration
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
