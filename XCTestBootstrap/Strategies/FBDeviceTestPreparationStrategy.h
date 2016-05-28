/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <XCTestBootstrap/FBXCTestPreparationStrategy.h>
#import "FBCodesignProvider.h"

@protocol FBFileManager;

/**
 Strategy used to run XCTest iOS Devices.
 Loads prepared bundles, then uploads them to device.
 */
@interface FBDeviceTestPreparationStrategy : NSObject <FBXCTestPreparationStrategy>

@property (nonatomic, strong) NSString *workingDirectory;
@property (nonatomic, strong) NSString *pathToXcodePlatformDir;

/**
 Creates and returns a strategy with given parameters

 @param applicationPath path to test runner application
 @param applicationDataPath path to application data bundle (.xcappdata)
 @param testBundlePath path to test bundle (.xctest)
 @param pathToXcodePlatformDir directory which contains platform SDKs within Xcode.app
 @param workingDirectory directory used to prepare all bundles
 @returns Prepared FBLocalDeviceTestRunStrategy
 */
+ (instancetype)strategyWithTestRunnerApplicationPath:(NSString *)applicationPath
                                  applicationDataPath:(NSString *)applicationDataPath
                                       testBundlePath:(NSString *)testBundlePath
                               pathToXcodePlatformDir:(NSString *)pathToXcodePlatformDir
                                     workingDirectory:(NSString *)workingDirectory;

/**
 Creates and returns a strategy with given parameters

 @param applicationPath path to test runner application
 @param applicationDataPath path to application data bundle (.xcappdata)
 @param testBundlePath path to test bundle (.xctest)
 @param pathToXcodePlatformDir directory which contains platform SDKs within Xcode.app
 @param fileManager file manager used to prepare all bundles
 @param workingDirectory directory used to prepare all bundles
 @returns Prepared FBLocalDeviceTestRunStrategy
 */
+ (instancetype)strategyWithTestRunnerApplicationPath:(NSString *)applicationPath
                                  applicationDataPath:(NSString *)applicationDataPath
                                       testBundlePath:(NSString *)testBundlePath
                               pathToXcodePlatformDir:(NSString *)pathToXcodePlatformDir
                                     workingDirectory:(NSString *)workingDirectory
                                          fileManager:(id<FBFileManager>)fileManager;

@end
