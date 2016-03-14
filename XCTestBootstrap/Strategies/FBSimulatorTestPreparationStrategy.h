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

@protocol FBFileManager;

/**
 Strategy used to run XCTest with simulators
 It will copy test bundle to workingDirectory and add .xctestconfiguration
 */
@interface FBSimulatorTestPreparationStrategy : NSObject <FBXCTestPreparationStrategy>

/**
 Creates and returns a strategy with given paramenters

 @param applicationPath path to tested application (.app)
 @param testBundlePath path to test bundle (.xctest)
 @param workingDirectory directory used to prepare all bundles
 @returns Prepared FBSimulatorTestRunStrategy
 */
+ (instancetype)strategyWithApplicationPath:(NSString *)applicationPath
                             testBundlePath:(NSString *)testBundlePath
                           workingDirectory:(NSString *)workingDirectory;

/**
 Creates and returns a strategy with given paramenters

 @param applicationPath path to tested application (.app)
 @param testBundlePath path to test bundle (.xctest)
 @param workingDirectory directory used to prepare all bundles
 @param fileManager file manager used to prepare all bundles
 @returns Prepared FBSimulatorTestRunStrategy
 */
+ (instancetype)strategyWithApplicationPath:(NSString *)applicationPath
                             testBundlePath:(NSString *)testBundlePath
                           workingDirectory:(NSString *)workingDirectory
                                fileManager:(id<FBFileManager>)fileManager;

@end
