/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBTestRunStrategy.h"

#import <XCTestBootstrap/XCTestBootstrap.h>
#import <FBControlCore/FBControlCore.h>

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
  
  NSMutableArray<FBBundleDescriptor *> *additionalApplications = [NSMutableArray arrayWithCapacity:self.configuration.additionalApplicationPaths.count];
  for (NSString *path in self.configuration.additionalApplicationPaths) {
    FBBundleDescriptor *app = [FBBundleDescriptor bundleFromPath:path error:&error];
    if (!app) {
      [self.logger logFormat:@"Failed to open additional application: %@", error];
      return [FBFuture futureWithError:error];
    } else {
      [additionalApplications addObject:app];
    }
  }
  
  return [[self.target
    installApplicationWithPath:testRunnerApp.path]
    onQueue:self.target.workQueue fmap:^(id _) {
      return [self startTestWithTestRunnerApp:testRunnerApp testTargetApp:testTargetApp additionalApplications:additionalApplications];
    }];
}

#pragma mark Private

- (FBFuture<NSNull *> *)startTestWithTestRunnerApp:(FBBundleDescriptor *)testRunnerApp testTargetApp:(FBBundleDescriptor *)testTargetApp additionalApplications:(NSArray<FBBundleDescriptor *> *)additionalApplications
{
  FBProcessOutputConfiguration *outputConfiguration = FBProcessOutputConfiguration.outputToDevNull;
  if (self.configuration.runnerAppLogPath != nil) {
    outputConfiguration = [FBProcessOutputConfiguration configurationWithStdOut:self.configuration.runnerAppLogPath
                                                                         stdErr:self.configuration.runnerAppLogPath
                                                                          error:NULL];
  }
  FBApplicationLaunchConfiguration *appLaunch = [FBApplicationLaunchConfiguration
    configurationWithBundleID:testRunnerApp.identifier
    bundleName:testRunnerApp.identifier
    arguments:@[]
    environment:self.configuration.processUnderTestEnvironment
    output:outputConfiguration
    launchMode:FBApplicationLaunchModeFailIfRunning];

  FBTestLaunchConfiguration *testLaunchConfiguration = [[FBTestLaunchConfiguration
    configurationWithTestBundlePath:self.configuration.testBundlePath]
    withApplicationLaunchConfiguration:appLaunch];

  if (testTargetApp) {
    testLaunchConfiguration = [[[[testLaunchConfiguration
     withTargetApplicationPath:testTargetApp.path]
     withTargetApplicationBundleID:testTargetApp.identifier]
     withTestApplicationDependencies:[self _testApplicationDependenciesWithTestRunnerApp:testRunnerApp testTargetApp:testTargetApp additionalApplications:additionalApplications]]
     withUITesting:YES];
  }

  if (self.configuration.testFilters.count > 0) {
    NSSet<NSString *> *testsToRun = [NSSet setWithArray:self.configuration.testFilters];
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

  return [[[[[runner
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
      
      if (self.configuration.runnerAppLogPath != nil) {
        [self.reporter didSaveRunnerAppLogAtPath:self.configuration.runnerAppLogPath];
      }

      if (self.configuration.testArtifactsFilenameGlobs != nil) {
        [self _saveTestArtifactsOfTestRunnerApp:testRunnerApp withFilenameMatchGlobs:self.configuration.testArtifactsFilenameGlobs];
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
    }];
}

- (NSDictionary<NSString *, NSString *> *)_testApplicationDependenciesWithTestRunnerApp:(FBBundleDescriptor *)testRunnerApp testTargetApp:(FBBundleDescriptor *)testTargetApp additionalApplications:(NSArray<FBBundleDescriptor *> *)additionalApplications
{
  NSMutableArray<FBBundleDescriptor *> *allApplications = [additionalApplications mutableCopy];
  if (testRunnerApp) {
    [allApplications addObject:testRunnerApp];
  }
  if (testTargetApp) {
    [allApplications addObject:testTargetApp];
  }
  NSMutableDictionary<NSString *, NSString *> *testApplicationDependencies = [NSMutableDictionary new];
  for (FBBundleDescriptor *application in allApplications) {
    if (application.path != nil && application.identifier != nil) {
      [testApplicationDependencies setObject:application.path forKey:application.identifier];
    }
  }
  return [testApplicationDependencies copy];
}

// Save test artifacts matches certain filename globs that are populated during test run
// to a temporary folder so it can be obtained by external tools if needed.
- (void)_saveTestArtifactsOfTestRunnerApp:(FBBundleDescriptor *)testRunnerApp withFilenameMatchGlobs:(NSArray<NSString *> *)filenameGlobs
{
  NSArray<FBDiagnostic *> *diagnostics = [[[FBDiagnosticQuery
    filesInApplicationOfBundleID:testRunnerApp.identifier withFilenames:@[] withFilenameGlobs:filenameGlobs]
    run:self.target]
    await:nil];

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
