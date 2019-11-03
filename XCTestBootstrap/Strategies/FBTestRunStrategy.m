/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBTestRunStrategy.h"

#import <XCTestBootstrap/XCTestBootstrap.h>

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
  FBBundleDescriptor *testRunnerApp = [FBBundleDescriptor bundleFromPath:self.configuration.runnerAppPath error:&error];
  if (!testRunnerApp) {
    [self.logger logFormat:@"Failed to open test runner application: %@", error];
    return [FBFuture futureWithError:error];
  }

  FBBundleDescriptor *testTargetApp;
  if (self.configuration.testTargetAppPath) {
    testTargetApp = [FBBundleDescriptor bundleFromPath:self.configuration.testTargetAppPath error:&error];
    if (!testTargetApp) {
      [self.logger logFormat:@"Failed to open test target application: %@", error];
      return [FBFuture futureWithError:error];
    }
  }

  return [[self.target
    installApplicationWithPath:testRunnerApp.path]
    onQueue:self.target.workQueue fmap:^(id _) {
      return [self startTestWithTestRunnerApp:testRunnerApp testTargetApp:testTargetApp];
    }];
}

#pragma mark Private

- (FBFuture<NSNull *> *)startTestWithTestRunnerApp:(FBBundleDescriptor *)testRunnerApp testTargetApp:(FBBundleDescriptor *)testTargetApp
{
  FBApplicationLaunchConfiguration *appLaunch = [FBApplicationLaunchConfiguration
    configurationWithBundleID:testRunnerApp.identifier
    bundleName:testRunnerApp.identifier
    arguments:@[]
    environment:self.configuration.processUnderTestEnvironment
    output:FBProcessOutputConfiguration.outputToDevNull
    launchMode:FBApplicationLaunchModeFailIfRunning];

  FBTestLaunchConfiguration *testLaunchConfiguration = [[FBTestLaunchConfiguration
    configurationWithTestBundlePath:self.configuration.testBundlePath]
    withApplicationLaunchConfiguration:appLaunch];

  if (testTargetApp) {
    testLaunchConfiguration = [[[testLaunchConfiguration
     withTargetApplicationPath:testTargetApp.path]
     withTargetApplicationBundleID:testTargetApp.identifier]
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

  __block id<FBiOSTargetContinuation> tailLogContinuation = nil;

  return [[[[[[runner
    connectAndStart]
    onQueue:self.target.workQueue fmap:^(FBTestManager *manager) {
      FBFuture<id> *startedVideoRecording = self.configuration.videoRecordingPath != nil
        ? (FBFuture<id> *) [self.target startRecordingToFile:self.configuration.videoRecordingPath]
        : (FBFuture<id> *) FBFuture.empty;

      FBFuture<id> *startedTailLog = self.configuration.osLogPath != nil
        ? (FBFuture<id> *) [self _startTailLogToFile:self.configuration.osLogPath]
        : (FBFuture<id> *) FBFuture.empty;

      return [FBFuture futureWithFutures:@[[FBFuture futureWithResult:manager], startedVideoRecording, startedTailLog]];
    }]
    onQueue:self.target.workQueue fmap:^(NSArray<id> *results) {
      FBTestManager *manager = results[0];
      if (results[2] != nil && ![results[2] isEqual:NSNull.null]) {
        tailLogContinuation = results[2];
      }
      return [manager execute];
    }]
    onQueue:self.target.workQueue fmap:^(FBTestManagerResult *result) {
      FBFuture *stoppedVideoRecording = self.configuration.videoRecordingPath != nil
        ? [self.target stopRecording]
        : FBFuture.empty;
      FBFuture *stopTailLog = tailLogContinuation != nil
        ? [tailLogContinuation.completed cancel]
        : FBFuture.empty;
      return [FBFuture futureWithFutures:@[[FBFuture futureWithResult:result], stoppedVideoRecording, stopTailLog]];
    }]
    onQueue:self.target.workQueue fmap:^ FBFuture<NSNull *> * (NSArray<id> *results) {
      FBTestManagerResult *result = results[0];
      if (self.configuration.videoRecordingPath != nil) {
        [self.reporter didRecordVideoAtPath:self.configuration.videoRecordingPath];
      }

      if (self.configuration.osLogPath != nil) {
        [self.reporter didSaveOSLogAtPath:self.configuration.osLogPath];
      }

      if (result.crash) {
        return [[FBXCTestError
          describeFormat:@"The Application Crashed during the Test Run\n%@", result.crash]
          failFuture];
      }
      if (result.error) {
        [self.logger logFormat:@"Failed to execute test bundle %@", result.error];
        return [FBFuture futureWithError:result.error];
      }
      return FBFuture.empty;
    }]
    onQueue:self.target.workQueue chain:^ FBFuture<NSNull *> * (FBFuture<NSNull *> *original) {
      if (!self.configuration.testArtifactsFilenameGlobs) {
        return original;
      }
      return [[self _saveTestArtifactsOfTestRunnerApp:testRunnerApp withFilenameMatchGlobs:self.configuration.testArtifactsFilenameGlobs] chainReplace:original];
    }];
}

// Save test artifacts matches certain filename globs that are populated during test run
// to a temporary folder so it can be obtained by external tools if needed.
- (FBFuture<NSNull *> *)_saveTestArtifactsOfTestRunnerApp:(FBBundleDescriptor *)testRunnerApp withFilenameMatchGlobs:(NSArray<NSString *> *)filenameGlobs
{
  return [[[self.target
    installedApplicationWithBundleID:testRunnerApp.identifier]
    onQueue:self.target.asyncQueue fmap:^ FBFuture<NSNull *> * (FBInstalledApplication *application) {
      NSString *directory = application.dataContainer;
      NSArray<NSString *> *paths = [FBFileFinder recursiveFindByFilenameGlobs:filenameGlobs inDirectory:directory];
      if (paths.count == 0) {
        return FBFuture.empty;
      }

      NSError *error = nil;
      NSURL *tempTestArtifactsPath = [NSURL fileURLWithPath:[NSString pathWithComponents:@[NSTemporaryDirectory(), NSProcessInfo.processInfo.globallyUniqueString, @"test_artifacts"]] isDirectory:YES];
      if (![NSFileManager.defaultManager createDirectoryAtURL:tempTestArtifactsPath withIntermediateDirectories:YES attributes:nil error:&error]) {
        [self.logger logFormat:@"Could not create temporary directory for test artifacts %@", error];
        return FBFuture.empty;
      }

      for (NSString *sourcePath in paths) {
        NSString *testArtifactsFilename = sourcePath.lastPathComponent;
        NSString *destinationPath = [tempTestArtifactsPath.path stringByAppendingPathComponent:testArtifactsFilename];
        if ([NSFileManager.defaultManager copyItemAtPath:sourcePath toPath:destinationPath error:nil]) {
          [self.reporter didCopiedTestArtifact:testArtifactsFilename toPath:destinationPath];
        }
      }
      return FBFuture.empty;
    }]
    onQueue:self.target.asyncQueue handleError:^(NSError *_) {
      return FBFuture.empty;
    }];
}

- (FBFuture *)_startTailLogToFile:(NSString *)logFilePath
{
  NSError *error = nil;
  id<FBDataConsumer> logFileWriter = [FBFileWriter syncWriterForFilePath:logFilePath error:&error];
  if (logFileWriter == nil) {
    [self.logger logFormat:@"Could not create log file at %@: %@", self.configuration.osLogPath, error];
    return FBFuture.empty;
  }

  return [self.target tailLog:@[@"--style", @"syslog", @"--level", @"debug"] consumer:logFileWriter];
}

@end
