/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBTestRunStrategy.h"

#import <XCTestBootstrap/XCTestBootstrap.h>

static const NSTimeInterval ApplicationTestDefaultTimeout = 4000;

@interface FBTestRunStrategy ()

@property (nonatomic, strong, readonly) id<FBiOSTarget> target;
@property (nonatomic, strong, readonly) FBTestManagerTestConfiguration *configuration;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;
@property (nonatomic, strong, readonly) id<FBXCTestReporter> reporter;
@property (nonatomic, strong, readonly) Class<FBXCTestPreparationStrategy> testPreparationStrategyClass;
@end

@implementation FBTestRunStrategy

+ (instancetype)strategyWithTarget:(id<FBiOSTarget>)target configuration:(FBTestManagerTestConfiguration *)configuration reporter:(id<FBXCTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger testPreparationStrategyClass:(Class<FBXCTestPreparationStrategy>)testPreparationStrategyClass
{
  return [[self alloc] initWithTarget:target configuration:configuration reporter:reporter logger:logger testPreparationStrategyClass:testPreparationStrategyClass];
}

- (instancetype)initWithTarget:(id<FBiOSTarget>)target configuration:(FBTestManagerTestConfiguration *)configuration reporter:(id<FBXCTestReporter>)reporter logger:(id<FBControlCoreLogger>)logger testPreparationStrategyClass:(Class<FBXCTestPreparationStrategy>)testPreparationStrategyClass
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _target = target;
  _configuration = configuration;
  _reporter = reporter;
  _logger = logger;
  _testPreparationStrategyClass = testPreparationStrategyClass;
  return self;
}

#pragma mark FBXCTestRunner

- (FBFuture<NSNull *> *)execute
{
  NSError *error = nil;
  FBApplicationBundle *testRunnerApp = [FBApplicationBundle applicationWithPath:self.configuration.runnerAppPath error:&error];
  if (!testRunnerApp) {
    [self.logger logFormat:@"Failed to open test runner application: %@", error];
    return [FBFuture futureWithError:error];
  }

  FBApplicationBundle *testTargetApp;
  if (self.configuration.testTargetAppPath) {
    testTargetApp = [FBApplicationBundle applicationWithPath:self.configuration.testTargetAppPath error:&error];
    if (!testTargetApp) {
      [self.logger logFormat:@"Failed to open test target application: %@", error];
      return [FBFuture futureWithError:error];
    }
  }

  return [[[self.target
    installApplicationWithPath:testRunnerApp.path]
    onQueue:self.target.workQueue fmap:^(id _) {
      return [self startTestWithTestRunnerApp:testRunnerApp testTargetApp:testTargetApp];
    }]
    timeout:ApplicationTestDefaultTimeout waitingFor:@"Test Execution to start"];
}

#pragma mark Private

- (FBFuture<NSNull *> *)startTestWithTestRunnerApp:(FBApplicationBundle *)testRunnerApp testTargetApp:(FBApplicationBundle *)testTargetApp
{
  FBApplicationLaunchConfiguration *appLaunch = [FBApplicationLaunchConfiguration
    configurationWithApplication:testRunnerApp
    arguments:@[]
    environment:self.configuration.processUnderTestEnvironment
    waitForDebugger:NO
    output:FBProcessOutputConfiguration.outputToDevNull];

  FBTestLaunchConfiguration *testLaunchConfiguration = [[FBTestLaunchConfiguration
    configurationWithTestBundlePath:self.configuration.testBundlePath]
    withApplicationLaunchConfiguration:appLaunch];

  if (testTargetApp) {
    testLaunchConfiguration = [[[testLaunchConfiguration
     withTargetApplicationPath:testTargetApp.path]
     withTargetApplicationBundleID:testTargetApp.bundleID]
     withUITesting:YES];
  }

  if (self.configuration.testFilter != nil) {
    NSSet<NSString *> *testsToRun = [NSSet setWithObject:self.configuration.testFilter];
    testLaunchConfiguration = [testLaunchConfiguration withTestsToRun:testsToRun];
  }

  id<FBXCTestPreparationStrategy> testPreparationStrategy = [self.testPreparationStrategyClass
    strategyWithTestLaunchConfiguration:testLaunchConfiguration
    workingDirectory:[self.configuration.workingDirectory stringByAppendingPathComponent:@"tmp"]];

  FBManagedTestRunStrategy *runner = [FBManagedTestRunStrategy
    strategyWithTarget:self.target
    configuration:testLaunchConfiguration
    reporter:[FBXCTestReporterAdapter adapterWithReporter:self.reporter]
    logger:self.target.logger
    testPreparationStrategy:testPreparationStrategy];

  return [[[[[runner
    connectAndStart]
    onQueue:self.target.workQueue fmap:^(FBTestManager *manager) {
      FBFuture *startedVideoRecording = self.configuration.videoRecordingPath != nil
        ? [self.target startRecordingToFile:self.configuration.videoRecordingPath]
        : [FBFuture futureWithResult:NSNull.null];
      return [FBFuture futureWithFutures:@[[FBFuture futureWithResult:manager], startedVideoRecording]];
    }]
    onQueue:self.target.workQueue fmap:^(NSArray<id> *results) {
      FBTestManager *manager = results[0];
      return [manager execute];
    }]
    onQueue:self.target.workQueue fmap:^(FBTestManagerResult *result) {
      FBFuture *stoppedVideoRecording = self.configuration.videoRecordingPath != nil
      ? [self.target stopRecording]
      : [FBFuture futureWithResult:NSNull.null];
      return [FBFuture futureWithFutures:@[[FBFuture futureWithResult:result], stoppedVideoRecording]];
    }]
    onQueue:self.target.workQueue fmap:^(NSArray<id> *results) {
      FBTestManagerResult *result = results[0];
      if (self.configuration.videoRecordingPath != nil) {
        [self.reporter didRecordVideoAtPath:self.configuration.videoRecordingPath];
      }

      if (self.configuration.testArtifactsFilenameGlobs != nil) {
        [self _saveTestArtifactsOfTestRunnerApp:testRunnerApp withFilenameMatchGlobs:self.configuration.testArtifactsFilenameGlobs];
      }

      if (result.crashDiagnostic) {
        return [[FBXCTestError
          describeFormat:@"The Application Crashed during the Test Run\n%@", result.crashDiagnostic.asString]
          failFuture];
      }
      if (result.error) {
        [self.logger logFormat:@"Failed to execute test bundle %@", result.error];
        return [FBFuture futureWithError:result.error];
      }
      return [FBFuture futureWithResult:NSNull.null];
    }];
}

// Save test artifacts matches certain filename globs that are populated during test run
// to a temporary folder so it can be obtained by external tools if needed.
- (void)_saveTestArtifactsOfTestRunnerApp:(FBApplicationBundle *)testRunnerApp withFilenameMatchGlobs:(NSArray<NSString *> *)filenameGlobs
{
  NSArray<FBDiagnostic *> *diagnostics = [self.target.diagnostics perform:[FBDiagnosticQuery filesInApplicationOfBundleID:testRunnerApp.bundleID withFilenames:@[] withFilenameGlobs:filenameGlobs]];

  if ([diagnostics count] == 0) {
    return;
  }

  NSURL *tempTestArtifactsPath = [NSURL fileURLWithPath:[NSString pathWithComponents:@[NSTemporaryDirectory(), NSProcessInfo.processInfo.globallyUniqueString, @"test_artifacts"]] isDirectory:YES];

  NSError *error = nil;
  if (![NSFileManager.defaultManager createDirectoryAtURL:tempTestArtifactsPath withIntermediateDirectories:YES attributes:nil error:&error]) {
    [self.logger logFormat:@"Could not create temporary directory for test artifacts %@", error];
    return;
  }

  for (FBDiagnostic *diagnostic in diagnostics) {
    NSString *testArtifactsFilename = diagnostic.asPath.lastPathComponent;
    NSString *outputPath = [tempTestArtifactsPath.path stringByAppendingPathComponent:testArtifactsFilename];
    if ([diagnostic writeOutToFilePath:outputPath error:nil]) {
      [self.reporter didCopiedTestArtifact:testArtifactsFilename toPath:outputPath];
    }
  }
}

@end
