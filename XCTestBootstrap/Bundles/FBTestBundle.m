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
@property (nonatomic, assign) BOOL shouldInitializeForUITesting;
@property (nonatomic, copy) NSSet<NSString *> *testsToRun;
@property (nonatomic, copy) NSSet<NSString *> *testsToSkip;
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
    [[[[[[[[[FBTestConfigurationBuilder builderWithFileManager:self.fileManager]
      withModuleName:testBundle.name]
      withSessionIdentifier:self.sessionIdentifier]
      withTestBundlePath:testBundle.path]
      withUITesting:self.shouldInitializeForUITesting]
      withTestsToRun:self.testsToRun]
      withTestsToSkip:self.testsToSkip]
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
