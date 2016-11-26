/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBTestLaunchConfiguration.h"

#import <FBControlCore/FBControlCore.h>

#import "FBTestManagerTestReporter.h"

@implementation FBTestLaunchConfiguration

- (instancetype)initWithTestBundlePath:(NSString *)testBundlePath applicationLaunchConfiguration:(FBApplicationLaunchConfiguration *)applicationLaunchConfiguration testHostPath:(NSString *)testHostPath timeout:(NSTimeInterval)timeout initializeUITesting:(BOOL)initializeUITesting testsToSkip:(NSSet<NSString *> *)testsToSkip testsToRun:(NSSet<NSString *> *)testsToRun targetApplicationPath:(NSString *)targetApplicationPath targetApplicationBundleID:(NSString *)targetApplicationBundleID
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _testBundlePath = testBundlePath;
  _applicationLaunchConfiguration = applicationLaunchConfiguration;
  _testHostPath = testHostPath;
  _timeout = timeout;
  _shouldInitializeUITesting = initializeUITesting;
  _testsToSkip = testsToSkip ?: [NSSet set];
  _testsToRun = testsToRun ?: [NSSet set];
  _targetApplicationPath = targetApplicationPath;
  _targetApplicationBundleID = targetApplicationBundleID;

  return self;
}

+ (instancetype)configurationWithTestBundlePath:(NSString *)testBundlePath
{
  NSParameterAssert(testBundlePath);
  return [[FBTestLaunchConfiguration alloc] initWithTestBundlePath:testBundlePath applicationLaunchConfiguration:nil testHostPath:nil timeout:0 initializeUITesting:NO testsToSkip:nil testsToRun:nil targetApplicationPath:nil targetApplicationBundleID:nil];
}

- (instancetype)withApplicationLaunchConfiguration:(FBApplicationLaunchConfiguration *)applicationLaunchConfiguration
{
  return [[FBTestLaunchConfiguration alloc]
    initWithTestBundlePath:self.testBundlePath
    applicationLaunchConfiguration:applicationLaunchConfiguration
    testHostPath:self.testHostPath
    timeout:self.timeout
    initializeUITesting:self.shouldInitializeUITesting
    testsToSkip:self.testsToSkip
    testsToRun:self.testsToRun
    targetApplicationPath:self.targetApplicationPath
    targetApplicationBundleID:self.targetApplicationBundleID];
}

- (instancetype)withTestHostPath:(NSString *)testHostPath
{
  return [[FBTestLaunchConfiguration alloc]
    initWithTestBundlePath:self.testBundlePath
    applicationLaunchConfiguration:self.applicationLaunchConfiguration
    testHostPath:testHostPath
    timeout:self.timeout
    initializeUITesting:self.shouldInitializeUITesting
    testsToSkip:self.testsToSkip
    testsToRun:self.testsToRun
    targetApplicationPath:self.targetApplicationPath
    targetApplicationBundleID:self.targetApplicationBundleID];
}

- (instancetype)withTimeout:(NSTimeInterval)timeout
{
  return [[FBTestLaunchConfiguration alloc]
    initWithTestBundlePath:self.testBundlePath
    applicationLaunchConfiguration:self.applicationLaunchConfiguration
    testHostPath:self.testHostPath
    timeout:timeout
    initializeUITesting:self.shouldInitializeUITesting
    testsToSkip:self.testsToSkip
    testsToRun:self.testsToRun
    targetApplicationPath:self.targetApplicationPath
    targetApplicationBundleID:self.targetApplicationBundleID];
}

- (instancetype)withUITesting:(BOOL)shouldInitializeUITesting
{
  return [[FBTestLaunchConfiguration alloc]
    initWithTestBundlePath:self.testBundlePath
    applicationLaunchConfiguration:self.applicationLaunchConfiguration
    testHostPath:self.testHostPath
    timeout:self.timeout
    initializeUITesting:shouldInitializeUITesting
    testsToSkip:self.testsToSkip
    testsToRun:self.testsToRun
    targetApplicationPath:self.targetApplicationPath
    targetApplicationBundleID:self.targetApplicationBundleID];
}

- (instancetype)withTestsToSkip:(NSSet<NSString *> *)testsToSkip
{
  return [[FBTestLaunchConfiguration alloc]
    initWithTestBundlePath:self.testBundlePath
    applicationLaunchConfiguration:self.applicationLaunchConfiguration
    testHostPath:self.testHostPath
    timeout:self.timeout
    initializeUITesting:self.shouldInitializeUITesting
    testsToSkip:testsToSkip
    testsToRun:self.testsToRun
    targetApplicationPath:self.targetApplicationPath
    targetApplicationBundleID:self.targetApplicationBundleID];
}

- (instancetype)withTestsToRun:(NSSet<NSString *> *)testsToRun
{
  return [[FBTestLaunchConfiguration alloc]
    initWithTestBundlePath:self.testBundlePath
    applicationLaunchConfiguration:self.applicationLaunchConfiguration
    testHostPath:self.testHostPath
    timeout:self.timeout
    initializeUITesting:self.shouldInitializeUITesting
    testsToSkip:self.testsToSkip
    testsToRun:testsToRun
    targetApplicationPath:self.targetApplicationPath
    targetApplicationBundleID:self.targetApplicationBundleID];
}

- (instancetype)withTargetApplicationPath:(NSString *)targetApplicationPath
{
  return [[FBTestLaunchConfiguration alloc]
    initWithTestBundlePath:self.testBundlePath
    applicationLaunchConfiguration:self.applicationLaunchConfiguration
    testHostPath:self.testHostPath
    timeout:self.timeout
    initializeUITesting:self.shouldInitializeUITesting
    testsToSkip:self.testsToSkip
    testsToRun:self.testsToRun
    targetApplicationPath:targetApplicationPath
    targetApplicationBundleID:self.targetApplicationBundleID];
}

- (instancetype)withTargetApplicationBundleID:(NSString *)targetApplicationBundleID
{
  return [[FBTestLaunchConfiguration alloc]
    initWithTestBundlePath:self.testBundlePath
    applicationLaunchConfiguration:self.applicationLaunchConfiguration
    testHostPath:self.testHostPath
    timeout:self.timeout
    initializeUITesting:self.shouldInitializeUITesting
    testsToSkip:self.testsToSkip
    testsToRun:self.testsToRun
    targetApplicationPath:self.targetApplicationPath
    targetApplicationBundleID:targetApplicationBundleID];
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  return self;
}

#pragma mark NSObject

- (BOOL)isEqual:(FBTestLaunchConfiguration *)configuration
{
  if (![configuration isKindOfClass:self.class]) {
    return NO;
  }

  return (self.testBundlePath == configuration.testBundlePath || [self.testBundlePath isEqualToString:configuration.testBundlePath]) &&
         (self.applicationLaunchConfiguration == configuration.applicationLaunchConfiguration  || [self.applicationLaunchConfiguration isEqual:configuration.applicationLaunchConfiguration]) &&
         (self.testHostPath == configuration.testHostPath || [self.testHostPath isEqualToString:configuration.testHostPath]) &&
         (self.testsToSkip == configuration.testsToSkip || [self.testsToSkip isEqualToSet:configuration.testsToSkip]) &&
         (self.testsToRun == configuration.testsToRun || [self.testsToRun isEqualToSet:configuration.testsToRun]) &&
         self.timeout == configuration.timeout &&
         self.shouldInitializeUITesting == configuration.shouldInitializeUITesting;
}

- (NSUInteger)hash
{
  return self.testBundlePath.hash ^ self.applicationLaunchConfiguration.hash ^ self.testsToSkip.hash ^ self.testsToRun.hash ^ self.testHostPath.hash ^ (unsigned long) self.timeout ^ (unsigned long) self.shouldInitializeUITesting;
}

#pragma mark FBDebugDescribeable

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"FBTestLaunchConfiguration TestBundlePath %@ | AppConfig %@ | HostPath %@ | UITesting %d",
    self.testBundlePath,
    self.applicationLaunchConfiguration,
    self.testHostPath,
    self.shouldInitializeUITesting
  ];
}

- (NSString *)shortDescription
{
  return [self description];
}

- (NSString *)debugDescription
{
  return [self description];
}

#pragma mark FBJSONSerializable

- (NSDictionary *)jsonSerializableRepresentation
{
  return @{
    @"test_bundle_path" : self.testBundlePath ?: NSNull.null,
    @"test_app_bundle_id" : self.applicationLaunchConfiguration ?: NSNull.null,
    @"test_host_path" : self.testHostPath ?: NSNull.null,
    @"tests_to_skip": self.testsToSkip.allObjects,
    @"tests_to_run": self.testsToRun.allObjects,
  };
}

@end
