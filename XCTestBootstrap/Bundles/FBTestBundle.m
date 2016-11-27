/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBTestBundle.h"

#import "FBProductBundle+Private.h"
#import "FBTestConfiguration.h"
#import "XCTestBootstrapError.h"

@interface FBTestBundle ()
@property (nonatomic, strong) FBTestConfiguration *configuration;
@end

@implementation FBTestBundle
@end


@interface FBTestBundleBuilder ()
@property (nonatomic, strong) NSUUID *sessionIdentifier;
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *testEnvironment;
@property (nonatomic, copy) NSSet<NSString *> *testsToRun;
@property (nonatomic, copy) NSSet<NSString *> *testsToSkip;
@property (nonatomic, assign) BOOL shouldInitializeForUITesting;
@property (nonatomic, copy) NSString *targetApplicationBundleID;
@property (nonatomic, copy) NSString *targetApplicationPath;
@end

@implementation FBTestBundleBuilder

- (instancetype)withSessionIdentifier:(NSUUID *)sessionIdentifier
{
  self.sessionIdentifier = sessionIdentifier;
  return self;
}

- (instancetype)withTestEnvironment:(NSDictionary<NSString *, NSString *> *)testEnvironment
{
  self.testEnvironment = testEnvironment;
  return self;
}

- (instancetype)withTestsToRun:(NSSet<NSString *> *)testsToRun
{
  self.testsToRun = testsToRun;
  return self;
}

- (instancetype)withTestsToSkip:(NSSet<NSString *> *)testsToSkip
{
  self.testsToSkip = testsToSkip;
  return self;
}

- (instancetype)withUITesting:(BOOL)shouldInitializeForUITesting
{
  self.shouldInitializeForUITesting = shouldInitializeForUITesting;
  return self;
}

- (instancetype)withTargetApplicationBundleID:(NSString *)targetApplicationBundleID
{
  self.targetApplicationBundleID = targetApplicationBundleID;
  return self;
}

- (instancetype)withTargetApplicationPath:(NSString *)targetApplicationPath
{
  self.targetApplicationPath = targetApplicationPath;
  return self;
}

- (Class)productClass
{
  return FBTestBundle.class;
}

- (FBTestBundle *)buildWithError:(NSError **)error
{
  FBTestBundle *testBundle = (FBTestBundle *)[super buildWithError:error];
  if (!testBundle) {
    return nil;
  }
  if (self.sessionIdentifier) {
    NSError *innerError;
    NSString *testConfigurationFileName = [NSString stringWithFormat:@"%@-%@.xctestconfiguration", testBundle.name, self.sessionIdentifier.UUIDString];
    testBundle.configuration =
    [[[[[[[[[[[[FBTestConfigurationBuilder builderWithFileManager:self.fileManager]
      withModuleName:testBundle.name]
      withTestBundlePath:testBundle.path]
      withSessionIdentifier:self.sessionIdentifier]
      withTestEnvironment:self.testEnvironment]
      withTestsToRun:self.testsToRun]
      withTestsToSkip:self.testsToSkip]
      withUITesting:self.shouldInitializeForUITesting]
      withTargetApplicationPath:self.targetApplicationPath]
      withTargetApplicationBundleID:self.targetApplicationBundleID]
      saveAs:[testBundle.path stringByAppendingPathComponent:testConfigurationFileName]]
      buildWithError:&innerError];
    if (!testBundle.configuration) {
      return
      [[[XCTestBootstrapError describe:@"Failed to generate xtestconfiguration"]
        causedBy:innerError]
       fail:error];
    }
  }
  return testBundle;
}

@end
