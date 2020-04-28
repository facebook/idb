/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
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
@property (nonatomic, assign) BOOL shouldInitializeForUITesting;
@property (nonatomic, copy) NSSet<NSString *> *testsToRun;
@property (nonatomic, copy) NSSet<NSString *> *testsToSkip;
@property (nonatomic, copy) NSString *targetApplicationBundleID;
@property (nonatomic, copy) NSString *targetApplicationPath;
@property (nonatomic, copy) NSString *automationFrameworkPath;
@property (nonatomic, assign) BOOL reportActivities;
@end

@implementation FBTestBundleBuilder

- (instancetype)withSessionIdentifier:(NSUUID *)sessionIdentifier
{
  self.sessionIdentifier = sessionIdentifier;
  return self;
}

- (instancetype)withUITesting:(BOOL)shouldInitializeForUITesting
{
  self.shouldInitializeForUITesting = shouldInitializeForUITesting;
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

- (instancetype)withAutomationFrameworkPath:(NSString *)automationFrameworkPath
{
  self.automationFrameworkPath = automationFrameworkPath;
  return self;
}

- (instancetype)withReportActivities:(BOOL)reportActivities
{
  self.reportActivities = reportActivities;
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
    testBundle.configuration = [FBTestConfiguration
      configurationWithFileManager:self.fileManager
      sessionIdentifier:self.sessionIdentifier
      moduleName:testBundle.name
      testBundlePath:testBundle.path
      uiTesting:self.shouldInitializeForUITesting
      testsToRun:self.testsToRun
      testsToSkip:self.testsToSkip
      targetApplicationPath:self.targetApplicationPath
      targetApplicationBundleID:self.targetApplicationBundleID
      automationFrameworkPath:self.automationFrameworkPath
      savePath:[testBundle.path stringByAppendingPathComponent:testConfigurationFileName]
      reportActivities:self.reportActivities
      error:&innerError];

    if (!testBundle.configuration) {
      return [[[XCTestBootstrapError
        describe:@"Failed to generate xtestconfiguration"]
        causedBy:innerError]
        fail:error];
    }
  }
  return testBundle;
}

@end
