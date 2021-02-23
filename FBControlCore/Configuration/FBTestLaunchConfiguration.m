/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBTestLaunchConfiguration.h"

#import "FBCollectionInformation.h"
#import "FBCollectionOperations.h"
#import "FBControlCoreError.h"
#import "FBiOSTarget.h"
#import "FBXCTestCommands.h"
#import "FBXCTestShimConfiguration.h"
#import "FBFuture+Sync.h"

@implementation FBTestLaunchConfiguration

- (instancetype)initWithTestBundlePath:(NSString *)testBundlePath applicationLaunchConfiguration:(FBApplicationLaunchConfiguration *)applicationLaunchConfiguration testHostPath:(NSString *)testHostPath timeout:(NSTimeInterval)timeout initializeUITesting:(BOOL)initializeUITesting useXcodebuild:(BOOL)useXcodebuild testsToRun:(NSSet<NSString *> *)testsToRun testsToSkip:(NSSet<NSString *> *)testsToSkip targetApplicationPath:(NSString *)targetApplicationPath targetApplicationBundleID:(NSString *)targetApplicaitonBundleID xcTestRunProperties:(NSDictionary *)xcTestRunProperties resultBundlePath:(NSString *)resultBundlePath reportActivities:(BOOL)reportActivities coveragePath:(NSString *)coveragePath shims:(FBXCTestShimConfiguration *)shims
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
  _shouldUseXcodebuild = useXcodebuild;
  _testsToRun = testsToRun;
  _testsToSkip = testsToSkip;
  _targetApplicationPath = targetApplicationPath;
  _targetApplicationBundleID = targetApplicaitonBundleID;
  _xcTestRunProperties = xcTestRunProperties;
  _resultBundlePath = resultBundlePath;
  _reportActivities = reportActivities;
  _coveragePath = coveragePath;
  _shims = shims;

  return self;
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
         (self.shims == configuration.shims  || [self.shims isEqual:configuration.shims]) &&
         (self.testHostPath == configuration.testHostPath || [self.testHostPath isEqualToString:configuration.testHostPath]) &&
         (self.targetApplicationBundleID == configuration.targetApplicationBundleID || [self.targetApplicationBundleID isEqualToString:configuration.targetApplicationBundleID]) &&
         (self.targetApplicationPath == configuration.targetApplicationPath || [self.targetApplicationPath isEqualToString:configuration.targetApplicationPath]) &&
         (self.testsToRun == configuration.testsToRun || [self.testsToRun isEqual:configuration.testsToRun]) &&
         (self.testsToSkip == configuration.testsToSkip || [self.testsToSkip isEqual:configuration.testsToSkip]) &&
         self.timeout == configuration.timeout &&
         self.shouldInitializeUITesting == configuration.shouldInitializeUITesting &&
         self.shouldUseXcodebuild == configuration.shouldUseXcodebuild &&
         (self.xcTestRunProperties == configuration.xcTestRunProperties || [self.xcTestRunProperties isEqual:configuration.xcTestRunProperties]) &&
         (self.resultBundlePath == configuration.resultBundlePath || [self.resultBundlePath isEqual:configuration.resultBundlePath]);
}

- (NSUInteger)hash
{
  return self.testBundlePath.hash ^ self.applicationLaunchConfiguration.hash ^ self.testHostPath.hash ^ (unsigned long) self.timeout ^ (unsigned long) self.shouldInitializeUITesting ^ (unsigned long) self.shouldUseXcodebuild ^ self.testsToRun.hash ^ self.testsToSkip.hash ^ self.targetApplicationPath.hash ^ self.targetApplicationBundleID.hash ^ self.xcTestRunProperties.hash ^ self.resultBundlePath.hash ^ self.shims.hash;
}

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"FBTestLaunchConfiguration TestBundlePath %@ | AppConfig %@ | HostPath %@ | UITesting %d | UseXcodebuild %d | TestsToRun %@ | TestsToSkip %@ | Target application path %@ | Target application bundle id %@ xcTestRunProperties %@ | ResultBundlePath %@ Shims %@" ,
    self.testBundlePath,
    self.applicationLaunchConfiguration,
    self.testHostPath,
    self.shouldInitializeUITesting,
    self.shouldUseXcodebuild,
    self.testsToRun,
    self.testsToSkip,
    self.targetApplicationPath,
    self.targetApplicationBundleID,
    self.xcTestRunProperties,
    self.resultBundlePath,
    self.shims
  ];
}

@end
