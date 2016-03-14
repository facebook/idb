// Copyright 2004-present Facebook. All Rights Reserved.

#import <XCTestBootstrap/FBXCTestPreparationStrategy.h>

@protocol FBFileManager;

/**
 Strategy used to run XCTest with CTScan devices
 It will load already prepared bundles and upload them to device
 */
@interface FBDeviceTestPreparationStrategy : NSObject <FBXCTestPreparationStrategy>

/**
 Creates and returns a strategy with given paramenters

 @param applicationPath path to tested application (.app)
 @param applicationDataPath path to application data bundle (.xcappdata)
 @param testBundlePath path to test bundle (.xctest)
 @returns Prepared FBLocalDeviceTestRunStrategy
 */
+ (instancetype)strategyWithApplicationPath:(NSString *)applicationPath
                        applicationDataPath:(NSString *)applicationDataPath
                             testBundlePath:(NSString *)testBundlePath;

/**
 Creates and returns a strategy with given paramenters

 @param applicationPath path to tested application (.app)
 @param applicationDataPath path to application data bundle (.xcappdata)
 @param testBundlePath path to test bundle (.xctest)
 @param fileManager file manager used to prepare all bundles
 @returns Prepared FBLocalDeviceTestRunStrategy
 */
+ (instancetype)strategyWithApplicationPath:(NSString *)applicationPath
                        applicationDataPath:(NSString *)applicationDataPath
                             testBundlePath:(NSString *)testBundlePath
                                fileManager:(id<FBFileManager>)fileManager;

@end
