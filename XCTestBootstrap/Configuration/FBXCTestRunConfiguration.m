/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBXCTestRunConfiguration.h"

#import <DVTFoundation/DVTFilePath.h>
#import <IDEFoundation/IDETestRunSpecification.h>
#import <IDEFoundation/IDERunnable.h>

#import <objc/runtime.h>

@interface FBXCTestRunConfiguration ()

@property (nonatomic, copy) NSString *testRunConfigurationPath;

@property (nonatomic, copy, readwrite, nullable) NSString *testHostPath;
@property (nonatomic, copy, readwrite, nullable) NSString *testBundlePath;
@property (nonatomic, copy, readwrite) NSArray<NSString *> *arguments;
@property (nonatomic, copy, readwrite) NSDictionary<NSString *, NSString *> *environment;
@property (nonatomic, copy, readwrite) NSSet<NSString *> *testsToSkip;
@property (nonatomic, copy, readwrite) NSSet<NSString *> *testsToRun;

@end

@implementation FBXCTestRunConfiguration

+ (instancetype)withTestRunConfigurationAtPath:(NSString *)testRunConfigurationPath
{
  return [[self alloc] initWithTestRunConfigurationPath:testRunConfigurationPath];
}

- (instancetype)initWithTestRunConfigurationPath:(NSString *)testRunConfigurationPath
{
  NSParameterAssert(testRunConfigurationPath);

  self = [super init];
  if (!self) {
    return nil;
  }

  _testRunConfigurationPath = [testRunConfigurationPath copy];

  return self;
}

- (instancetype)buildWithError:(NSError **)error;
{
  // TODO: <plu> We need to make sure that the frameworks are loaded here already.
  DVTFilePath *path = [objc_lookUpClass("DVTFilePath") filePathForPathString:self.testRunConfigurationPath];
  // TODO: <plu> Investigate why here this weird type of dictionary is coming back.
  IDETestRunSpecification *testRunSpecification = [[[objc_lookUpClass("IDETestRunSpecification") testRunSpecificationsAtFilePath:path workspace:nil error:error] allValues] firstObject];
  if (*error) {
    return nil;
  }

  // TODO: <plu> To avoid valueForKeyPath here we should probably also dump IDEPathRunnable and everything that gets pulled by it.
  self.testHostPath = [testRunSpecification.testHostRunnable valueForKeyPath:@"filePath.pathString"];
  self.testBundlePath = testRunSpecification.testBundleFilePath.pathString;
  self.arguments = testRunSpecification.commandLineArguments ?: @[];
  self.environment = testRunSpecification.environmentVariables ?: @{};
  self.testsToSkip = testRunSpecification.testIdentifiersToSkip ?: [NSSet set];
  self.testsToRun = testRunSpecification.testIdentifiersToRun ?: [NSSet set];

  return self;
}

@end
