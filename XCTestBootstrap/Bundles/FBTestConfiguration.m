/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBTestConfiguration.h"

#import <FBControlCore/FBControlCore.h>

#import <XCTest/XCTestConfiguration.h>

#import <objc/runtime.h>

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"

@implementation FBTestConfiguration

+ (nullable instancetype)configurationWithFileManager:(id<FBFileManager>)fileManager sessionIdentifier:(NSUUID *)sessionIdentifier moduleName:(NSString *)moduleName testBundlePath:(NSString *)testBundlePath uiTesting:(BOOL)uiTesting testsToRun:(nullable NSSet<NSString *> *)testsToRun testsToSkip:(nullable NSSet<NSString *> *)testsToSkip targetApplicationPath:(nullable NSString *)targetApplicationPath targetApplicationBundleID:(nullable NSString *)targetApplicationBundleID automationFrameworkPath:(nullable NSString *)automationFrameworkPath savePath:(NSString *)savePath reportActivities:(BOOL)reportActivities error:(NSError **)error
{
  XCTestConfiguration *testConfiguration = [objc_lookUpClass("XCTestConfiguration") new];
  testConfiguration.sessionIdentifier = sessionIdentifier;
  testConfiguration.testBundleURL = (testBundlePath ? [NSURL fileURLWithPath:testBundlePath] : nil);
  testConfiguration.treatMissingBaselinesAsFailures = NO;
  testConfiguration.productModuleName = moduleName;
  testConfiguration.reportResultsToIDE = YES;
  testConfiguration.testsMustRunOnMainThread = uiTesting;
  testConfiguration.initializeForUITesting = uiTesting;
  testConfiguration.testsToRun = testsToRun;
  testConfiguration.testsToSkip = testsToSkip;
  testConfiguration.targetApplicationPath = targetApplicationPath;
  testConfiguration.targetApplicationBundleID = targetApplicationBundleID;
  testConfiguration.automationFrameworkPath = automationFrameworkPath;
  testConfiguration.reportActivities = reportActivities;
  NSData *data = [NSKeyedArchiver archivedDataWithRootObject:testConfiguration];
  if (![fileManager writeData:data toFile:savePath options:NSDataWritingAtomic error:error]) {
    return nil;
  }
  return [self configurationWithSessionIdentifier:sessionIdentifier moduleName:moduleName testBundlePath:testBundlePath path:savePath uiTesting:uiTesting];
}

+ (instancetype)configurationWithSessionIdentifier:(NSUUID *)sessionIdentifier moduleName:(NSString *)moduleName testBundlePath:(NSString *)testBundlePath path:(NSString *)path uiTesting:(BOOL)uiTesting
{
  return [[self alloc]
    initWithSessionIdentifier:sessionIdentifier
    moduleName:moduleName
    testBundlePath:testBundlePath
    path:path
    uiTesting:uiTesting];
}

- (instancetype)initWithSessionIdentifier:(NSUUID *)sessionIdentifier moduleName:(NSString *)moduleName testBundlePath:(NSString *)testBundlePath path:(NSString *)path uiTesting:(BOOL)uiTesting
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _sessionIdentifier = sessionIdentifier;
  _moduleName = moduleName;
  _testBundlePath = testBundlePath;
  _path = path;
  _shouldInitializeForUITesting = uiTesting;

  return self;
}

@end

#pragma GCC diagnostic pop
