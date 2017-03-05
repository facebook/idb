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

@implementation FBTestLaunchConfiguration

- (instancetype)initWithTestBundlePath:(NSString *)testBundlePath applicationLaunchConfiguration:(FBApplicationLaunchConfiguration *)applicationLaunchConfiguration testHostPath:(NSString *)testHostPath timeout:(NSTimeInterval)timeout initializeUITesting:(BOOL)initializeUITesting testsToRun:(NSSet<NSString *> *)testsToRun testsToSkip:(NSSet<NSString *> *)testsToSkip targetApplicationBundleID:(NSString *)targetApplicationBundleID targetApplicationPath:(NSString *)targetApplicationPath
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
  _testsToRun = testsToRun;
  _testsToSkip = testsToSkip;
  _targetApplicationBundleID = targetApplicationBundleID;
  _targetApplicationPath = targetApplicationPath;

  return self;
}

+ (instancetype)configurationWithTestBundlePath:(NSString *)testBundlePath
{
  NSParameterAssert(testBundlePath);
  return [[FBTestLaunchConfiguration alloc] initWithTestBundlePath:testBundlePath applicationLaunchConfiguration:nil testHostPath:nil timeout:0 initializeUITesting:NO testsToRun:nil testsToSkip:[NSSet set] targetApplicationBundleID:nil targetApplicationPath:nil];
}

- (instancetype)withApplicationLaunchConfiguration:(FBApplicationLaunchConfiguration *)applicationLaunchConfiguration
{
  return [[FBTestLaunchConfiguration alloc]
    initWithTestBundlePath:self.testBundlePath
    applicationLaunchConfiguration:applicationLaunchConfiguration
    testHostPath:self.testHostPath
    timeout:self.timeout
    initializeUITesting:self.shouldInitializeUITesting
    testsToRun:self.testsToRun
    testsToSkip:self.testsToSkip
    targetApplicationBundleID:self.targetApplicationBundleID
    targetApplicationPath:self.targetApplicationPath];
}

- (instancetype)withTestHostPath:(NSString *)testHostPath
{
  return [[FBTestLaunchConfiguration alloc]
    initWithTestBundlePath:self.testBundlePath
    applicationLaunchConfiguration:self.applicationLaunchConfiguration
    testHostPath:testHostPath
    timeout:self.timeout
    initializeUITesting:self.shouldInitializeUITesting
    testsToRun:self.testsToRun
    testsToSkip:self.testsToSkip
    targetApplicationBundleID:self.targetApplicationBundleID
    targetApplicationPath:self.targetApplicationPath];
}

- (instancetype)withTimeout:(NSTimeInterval)timeout
{
  return [[FBTestLaunchConfiguration alloc]
    initWithTestBundlePath:self.testBundlePath
    applicationLaunchConfiguration:self.applicationLaunchConfiguration
    testHostPath:self.testHostPath
    timeout:timeout
    initializeUITesting:self.shouldInitializeUITesting
    testsToRun:self.testsToRun
    testsToSkip:self.testsToSkip
    targetApplicationBundleID:self.targetApplicationBundleID
    targetApplicationPath:self.targetApplicationPath];
}

- (instancetype)withUITesting:(BOOL)shouldInitializeUITesting
{
  return [[FBTestLaunchConfiguration alloc]
    initWithTestBundlePath:self.testBundlePath
    applicationLaunchConfiguration:self.applicationLaunchConfiguration
    testHostPath:self.testHostPath
    timeout:self.timeout
    initializeUITesting:shouldInitializeUITesting
    testsToRun:self.testsToRun
    testsToSkip:self.testsToSkip
    targetApplicationBundleID:self.targetApplicationBundleID
    targetApplicationPath:self.targetApplicationPath];
}

- (instancetype)withTestsToRun:(NSSet<NSString *> *)testsToRun
{
  return [[FBTestLaunchConfiguration alloc]
    initWithTestBundlePath:self.testBundlePath
    applicationLaunchConfiguration:self.applicationLaunchConfiguration
    testHostPath:self.testHostPath
    timeout:self.timeout
    initializeUITesting:self.shouldInitializeUITesting
    testsToRun:testsToRun
    testsToSkip:self.testsToSkip
    targetApplicationBundleID:self.targetApplicationBundleID
    targetApplicationPath:self.targetApplicationPath];
}

- (instancetype)withTestsToSkip:(NSSet<NSString *> *)testsToSkip
{
  return [[FBTestLaunchConfiguration alloc]
    initWithTestBundlePath:self.testBundlePath
    applicationLaunchConfiguration:self.applicationLaunchConfiguration
    testHostPath:self.testHostPath
    timeout:self.timeout
    initializeUITesting:self.shouldInitializeUITesting
    testsToRun:self.testsToRun
    testsToSkip:testsToSkip
    targetApplicationBundleID:self.targetApplicationBundleID
    targetApplicationPath:self.targetApplicationPath];
}

- (instancetype)withUITestingTargetApplicationBundleID:(NSString *)targetApplicationBundleID
{
  return [[FBTestLaunchConfiguration alloc]
    initWithTestBundlePath:self.testBundlePath
    applicationLaunchConfiguration:self.applicationLaunchConfiguration
    testHostPath:self.testHostPath
    timeout:self.timeout
    initializeUITesting:self.shouldInitializeUITesting
    testsToRun:self.testsToRun
    testsToSkip:self.testsToSkip
    targetApplicationBundleID:targetApplicationBundleID
    targetApplicationPath:self.targetApplicationPath];
}

- (instancetype)withUITestingTargetApplicationPath:(NSString *)targetApplicationPath
{
  return [[FBTestLaunchConfiguration alloc]
    initWithTestBundlePath:self.testBundlePath
    applicationLaunchConfiguration:self.applicationLaunchConfiguration
    testHostPath:self.testHostPath
    timeout:self.timeout
    initializeUITesting:self.shouldInitializeUITesting
    testsToRun:self.testsToRun
    testsToSkip:self.testsToSkip
    targetApplicationBundleID:self.targetApplicationBundleID
    targetApplicationPath:targetApplicationPath];
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
         (self.testsToRun == configuration.testsToRun || [self.testsToRun isEqual:configuration.testsToRun]) &&
         (self.testsToSkip == configuration.testsToSkip || [self.testsToSkip isEqual:configuration.testsToSkip]) &&
         (self.targetApplicationBundleID == configuration.targetApplicationBundleID || [self.targetApplicationBundleID isEqualToString:configuration.targetApplicationBundleID]) &&
         (self.targetApplicationPath == configuration.targetApplicationPath || [self.targetApplicationPath isEqualToString:configuration.targetApplicationPath]) &&
         self.timeout == configuration.timeout &&
         self.shouldInitializeUITesting == configuration.shouldInitializeUITesting;
}

- (NSUInteger)hash
{
  return self.testBundlePath.hash ^ self.applicationLaunchConfiguration.hash ^ self.testHostPath.hash ^ (unsigned long) self.timeout ^ (unsigned long) self.shouldInitializeUITesting ^ self.testsToRun.hash ^ self.testsToSkip.hash ^ self.targetApplicationBundleID.hash ^ self.targetApplicationPath.hash;
}

#pragma mark FBDebugDescribeable

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"FBTestLaunchConfiguration TestBundlePath %@ | AppConfig %@ | HostPath %@ | UITesting %d | TestsToRun %@ | TestsToSkip %@ | TargetApplicationBundleID %@ | TargetApplicationPath %@",
    self.testBundlePath,
    self.applicationLaunchConfiguration,
    self.testHostPath,
    self.shouldInitializeUITesting,
    self.testsToRun,
    self.testsToSkip,
    self.targetApplicationBundleID,
    self.targetApplicationPath
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
    @"tests_to_run" : self.testsToRun.allObjects ?: NSNull.null,
    @"tests_to_skip" : self.testsToSkip.allObjects ?: NSNull.null,
    @"target_application_bundle_id" : self.targetApplicationBundleID ?: NSNull.null,
    @"target_application_path" : self.targetApplicationPath ?: NSNull.null
  };
}

@end
