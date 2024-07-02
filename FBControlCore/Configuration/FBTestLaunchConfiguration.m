/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
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

- (instancetype)initWithTestBundle:(FBBundleDescriptor *)testBundle applicationLaunchConfiguration:(FBApplicationLaunchConfiguration *)applicationLaunchConfiguration testHostBundle:(nullable FBBundleDescriptor *)testHostBundle timeout:(NSTimeInterval)timeout initializeUITesting:(BOOL)initializeUITesting useXcodebuild:(BOOL)useXcodebuild testsToRun:(NSSet<NSString *> *)testsToRun testsToSkip:(NSSet<NSString *> *)testsToSkip targetApplicationBundle:(nullable FBBundleDescriptor *)targetApplicationBundle xcTestRunProperties:(NSDictionary *)xcTestRunProperties resultBundlePath:(NSString *)resultBundlePath reportActivities:(BOOL)reportActivities coverageDirectoryPath:(NSString *)coverageDirectoryPath enableContinuousCoverageCollection:(BOOL)enableContinuousCoverageCollection logDirectoryPath:(nullable NSString *)logDirectoryPath reportResultBundle:(BOOL)reportResultBundle
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _testBundle = testBundle;
  _applicationLaunchConfiguration = applicationLaunchConfiguration;
  _testHostBundle = testHostBundle;
  _timeout = timeout;
  _shouldInitializeUITesting = initializeUITesting;
  _shouldUseXcodebuild = useXcodebuild;
  _testsToRun = testsToRun;
  _testsToSkip = testsToSkip;
  _targetApplicationBundle = targetApplicationBundle;
  _xcTestRunProperties = xcTestRunProperties;
  _resultBundlePath = resultBundlePath;
  _reportActivities = reportActivities;
  _coverageDirectoryPath = coverageDirectoryPath;
  _shouldEnableContinuousCoverageCollection = enableContinuousCoverageCollection;
  _logDirectoryPath = logDirectoryPath;
  _reportResultBundle = reportResultBundle;

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

  return (self.testBundle == configuration.testBundle || [self.testBundle isEqualTo:configuration.testBundle]) &&
         (self.applicationLaunchConfiguration == configuration.applicationLaunchConfiguration  || [self.applicationLaunchConfiguration isEqual:configuration.applicationLaunchConfiguration]) &&
         (self.testHostBundle == configuration.testHostBundle || [self.testHostBundle isEqual:configuration.testHostBundle]) &&
         (self.targetApplicationBundle == configuration.targetApplicationBundle || [self.targetApplicationBundle isEqual:configuration.targetApplicationBundle]) &&
         (self.testsToRun == configuration.testsToRun || [self.testsToRun isEqual:configuration.testsToRun]) &&
         (self.testsToSkip == configuration.testsToSkip || [self.testsToSkip isEqual:configuration.testsToSkip]) &&
         self.timeout == configuration.timeout &&
         self.shouldInitializeUITesting == configuration.shouldInitializeUITesting &&
         self.shouldUseXcodebuild == configuration.shouldUseXcodebuild &&
         (self.xcTestRunProperties == configuration.xcTestRunProperties || [self.xcTestRunProperties isEqual:configuration.xcTestRunProperties]) &&
         (self.resultBundlePath == configuration.resultBundlePath || [self.resultBundlePath isEqual:configuration.resultBundlePath]) &&
         (self.coverageDirectoryPath == configuration.coverageDirectoryPath || [self.coverageDirectoryPath isEqualToString:configuration.coverageDirectoryPath]) &&
         (self.shouldEnableContinuousCoverageCollection == configuration.shouldEnableContinuousCoverageCollection) &&
         (self.logDirectoryPath == configuration.logDirectoryPath || [self.logDirectoryPath isEqualToString:configuration.logDirectoryPath]) &&
         self.reportResultBundle == configuration.reportResultBundle;
}

- (NSUInteger)hash
{
  return self.testBundle.hash ^ self.applicationLaunchConfiguration.hash ^ self.testHostBundle.hash ^ (unsigned long) self.timeout ^ (unsigned long) self.shouldInitializeUITesting ^ (unsigned long) self.shouldUseXcodebuild ^ self.testsToRun.hash ^ self.testsToSkip.hash ^ self.targetApplicationBundle.hash ^ self.xcTestRunProperties.hash ^ self.resultBundlePath.hash ^ self.coverageDirectoryPath.hash ^ (unsigned long) self.shouldEnableContinuousCoverageCollection ^ self.logDirectoryPath.hash;
}

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"FBTestLaunchConfiguration TestBundle %@ | AppConfig %@ | HostBundle %@ | UITesting %d | UseXcodebuild %d | TestsToRun %@ | TestsToSkip %@ | Target application bundle %@ xcTestRunProperties %@ | ResultBundlePath %@ | CoverageDirPath %@ | EnableContinuousCoverageCollection %d | LogDirectoryPath %@ | ReportResultBundle %d" ,
    self.testBundle,
    self.applicationLaunchConfiguration,
    self.testHostBundle,
    self.shouldInitializeUITesting,
    self.shouldUseXcodebuild,
    self.testsToRun,
    self.testsToSkip,
    self.targetApplicationBundle,
    self.xcTestRunProperties,
    self.resultBundlePath,
    self.coverageDirectoryPath,
    self.shouldEnableContinuousCoverageCollection,
    self.logDirectoryPath,
    self.reportResultBundle
  ];
}

@end
