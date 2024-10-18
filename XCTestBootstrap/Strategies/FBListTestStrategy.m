/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBListTestStrategy.h"

#import <sys/types.h>
#import <sys/stat.h>

#import <FBControlCore/FBControlCore.h>
#import <XCTestBootstrap/XCTestBootstrap.h>

#import "FBXCTestConstants.h"

@interface FBListTestStrategy ()

@property (nonatomic, strong, readonly) FBListTestConfiguration *configuration;
@property (nonatomic, strong, readonly) id<FBiOSTarget, FBProcessSpawnCommands, FBXCTestExtendedCommands> target;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;

@end

@interface FBListTestStrategy_ReporterWrapped : NSObject <FBXCTestRunner>

@property (nonatomic, strong, readonly) FBListTestStrategy *strategy;
@property (nonatomic, strong, readonly) id<FBXCTestReporter> reporter;

@end

@implementation FBListTestStrategy_ReporterWrapped

- (instancetype)initWithStrategy:(FBListTestStrategy *)strategy reporter:(id<FBXCTestReporter>)reporter
{
    self = [super init];
    if (!self) {
        return nil;
    }

    _strategy = strategy;
    _reporter = reporter;

    return self;
}


- (FBFuture<NSNull *> *)execute
{
  [self.reporter didBeginExecutingTestPlan];

  return [[self.strategy
    listTests]
    onQueue:self.strategy.target.workQueue map:^(NSArray<NSString *> *testNames) {
      for (NSString *testName in testNames) {
        NSRange slashRange = [testName rangeOfString:@"/"];
        NSString *className = [testName substringToIndex:slashRange.location];
        NSString *methodName = [testName substringFromIndex:slashRange.location + 1];
        [self.reporter testCaseDidStartForTestClass:className method:methodName];
        [self.reporter testCaseDidFinishForTestClass:className method:methodName withStatus:FBTestReportStatusPassed duration:0 logs:nil];
      }
      [self.reporter didFinishExecutingTestPlan];

      return NSNull.null;
    }];
}

@end

@implementation FBListTestStrategy

- (instancetype)initWithTarget:(id<FBiOSTarget, FBProcessSpawnCommands, FBXCTestExtendedCommands>)target configuration:(FBListTestConfiguration *)configuration logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
      return nil;
  }

  _target = target;
  _configuration = configuration;
  _logger = logger;

  return self;
}

- (FBFuture<NSArray<NSString *> *> *)listTests
{
  id<FBConsumableBuffer> shimBuffer = FBDataBuffer.consumableBuffer;
  return [[FBFuture
    futureWithFutures:@[
      [self.target extendedTestShim],
      [[FBProcessOutput outputForDataConsumer:shimBuffer] providedThroughFile],
    ]]
    onQueue:self.target.workQueue fmap:^(NSArray<id> *tuple) {
      return [self listTestsWithShimPath:tuple[0] shimOutput:tuple[1] shimBuffer:shimBuffer];
    }];
}

#pragma mark Private

- (FBFuture<NSArray<NSString *> *> *)listTestsWithShimPath:(NSString *)shimPath shimOutput:(id<FBProcessFileOutput>)shimOutput shimBuffer:(id<FBConsumableBuffer>)shimBuffer
{
  id<FBConsumableBuffer> stdOutBuffer = FBDataBuffer.consumableBuffer;
  id<FBDataConsumer> stdOutConsumer = [FBCompositeDataConsumer consumerWithConsumers:@[
    stdOutBuffer,
    [FBLoggingDataConsumer consumerWithLogger:self.logger],
  ]];
  id<FBConsumableBuffer> stdErrBuffer = FBDataBuffer.consumableBuffer;
  id<FBDataConsumer> stdErrConsumer = [FBCompositeDataConsumer consumerWithConsumers:@[
    stdErrBuffer,
    [FBLoggingDataConsumer consumerWithLogger:self.logger],
  ]];

  return [[[FBTemporaryDirectory temporaryDirectoryWithLogger:self.logger] withTemporaryDirectory]
          onQueue:self.target.workQueue pop:^FBFuture *(NSURL *temporaryDirectory) {
    return [[FBOToolDynamicLibs
             findFullPathForSanitiserDyldInBundle:self.configuration.testBundlePath onQueue:self.target.workQueue]
            onQueue:self.target.workQueue fmap:^FBFuture<NSNull *> * (NSArray<NSString *> *libraries){
      NSDictionary<NSString *, NSString *> *environment = [FBListTestStrategy setupEnvironmentWithDylibs:libraries shimPath:shimPath shimOutputFilePath:shimOutput.filePath bundlePath:self.configuration.testBundlePath];

      return [[FBListTestStrategy
               listTestProcessWithTarget:self.target
               configuration:self.configuration
               xctestPath:self.target.xctestPath
               environment:environment
               stdOutConsumer:stdOutConsumer
               stdErrConsumer:stdErrConsumer
               logger:self.logger
               temporaryDirectory:temporaryDirectory]
              onQueue:self.target.workQueue fmap:^(FBFuture<NSNumber *> *exitCode) {
        return [FBListTestStrategy
                launchedProcessWithExitCode:exitCode
                shimOutput:shimOutput
                shimBuffer:shimBuffer
                stdOutBuffer:stdOutBuffer
                stdErrBuffer:stdErrBuffer
                queue:self.target.workQueue];
      }];
    }];
  }];
}

+ (NSDictionary<NSString *, NSString *> *)setupEnvironmentWithDylibs:(NSArray *)libraries shimPath:(NSString *)shimPath shimOutputFilePath:(NSString *)shimOutputFilePath bundlePath:(NSString *)bundlePath
{
  NSMutableArray *librariesWithShim = [NSMutableArray arrayWithObject:shimPath];
  [librariesWithShim addObjectsFromArray:libraries];
  NSDictionary<NSString *, NSString *> *environment = @{
    @"DYLD_INSERT_LIBRARIES": [librariesWithShim componentsJoinedByString:@":"],
    @"TEST_SHIM_OUTPUT_PATH": shimOutputFilePath,
    @"TEST_SHIM_BUNDLE_PATH": bundlePath,
  };

  return environment;
}

+ (FBFuture<NSArray<NSString *> *> *)launchedProcessWithExitCode:(FBFuture<NSNumber *> *)exitCode shimOutput:(id<FBProcessFileOutput>)shimOutput shimBuffer:(id<FBConsumableBuffer>)shimBuffer stdOutBuffer:(id<FBConsumableBuffer>)stdOutBuffer stdErrBuffer:(id<FBConsumableBuffer>)stdErrBuffer queue:(dispatch_queue_t)queue
{
  return [[[shimOutput
    startReading]
    onQueue:queue fmap:^(id _) {
      return [FBListTestStrategy
        onQueue:queue
        confirmExit:exitCode
        closingOutput:shimOutput
        shimBuffer:shimBuffer
        stdOutBuffer:stdOutBuffer
        stdErrBuffer:stdErrBuffer];
    }]
    onQueue:queue fmap:^(id _) {
      NSError *error = nil;
      NSArray<NSDictionary<NSString *, NSString *> *> *tests = [NSJSONSerialization JSONObjectWithData:shimBuffer.data options:0 error:&error];
      if (!tests) {
        NSLog(@"Shimulator buffer data (should contain test information): %@", shimBuffer.data);
        return [FBFuture futureWithError:error];
      }
      NSMutableArray<NSString *> *testNames = [NSMutableArray array];
      for (NSDictionary<NSString *, NSString *> * test in tests) {
        NSString *testName = test[kReporter_ListTest_LegacyTestNameKey];
        if (![testName isKindOfClass:NSString.class]) {
          return [[FBXCTestError
            describeFormat:@"Received unexpected test name from shim: %@", testName]
            failFuture];
        }
        [testNames addObject:testName];
      }
      return [FBFuture futureWithResult:[testNames copy]];
    }];
}

+ (FBFuture<NSNull *> *)onQueue:(dispatch_queue_t)queue confirmExit:(FBFuture<NSNumber *> *)exitCode closingOutput:(id<FBProcessFileOutput>)output shimBuffer:(id<FBConsumableBuffer>)shimBuffer stdOutBuffer:(id<FBConsumableBuffer>)stdOutBuffer stdErrBuffer:(id<FBConsumableBuffer>)stdErrBuffer
{
  return [exitCode
    onQueue:queue fmap:^(NSNumber *exitCodeNumber) {
      int exitCodeValue = exitCodeNumber.intValue;
      NSString *descriptionOfFailingExit = [FBXCTestProcess describeFailingExitCode:exitCodeValue];
      if (descriptionOfFailingExit) {
        NSString *stdErrReversed = [stdErrBuffer.lines.reverseObjectEnumerator.allObjects componentsJoinedByString:@"\n"];
        return [[XCTestBootstrapError
          describeFormat:@"Listing of tests failed due to xctest binary exiting with non-zero exit code %d [%@]: %@", exitCodeValue, descriptionOfFailingExit, stdErrReversed]
          failFuture];
      }
      return [FBFuture futureWithFutures:@[
        [output stopReading],
        [shimBuffer finishedConsuming],
      ]];
    }];
}

+ (FBFuture<FBFuture<NSNumber *> *> *)listTestProcessWithTarget:(id<FBiOSTarget, FBProcessSpawnCommands>)target configuration:(FBListTestConfiguration *)configuration xctestPath:(NSString *)xctestPath environment:(NSDictionary<NSString *, NSString *> *)environment stdOutConsumer:(id<FBDataConsumer>)stdOutConsumer stdErrConsumer:(id<FBDataConsumer>)stdErrConsumer logger:(id<FBControlCoreLogger>)logger temporaryDirectory: (NSURL *)temporaryDirectory
{
  NSString *launchPath = xctestPath;
  NSTimeInterval timeout = configuration.testTimeout;


  FBProcessIO *io = [[FBProcessIO alloc] initWithStdIn:nil stdOut:[FBProcessOutput outputForDataConsumer:stdOutConsumer] stdErr:[FBProcessOutput outputForDataConsumer:stdErrConsumer]];
  // List test for app test bundle, so we use app binary instead of xctest to load test bundle.
  if ([FBBundleDescriptor isApplicationAtPath:configuration.runnerAppPath]) {
    // Since we're loading the test bundle in app binary's process without booting a simulator,
    // testing frameworks like XCTest.framework and XCTAutomationSupport.framework won't be available.
    // (They are available in iOS simulator's runtime). To fix this, we could add the paths of those
    // frameworks (developer library version) to `DYLD_FALLBACK_FRAMEWORK_PATH` to meet the dependency
    // requirements of loading test bundle.
    NSString *developerLibraryPath =
    [FBXcodeConfiguration.developerDirectory
     stringByAppendingPathComponent:@"Platforms/iPhoneSimulator.platform/Developer/Library"];

    NSArray<NSString *> *testFrameworkPaths = @[
      [developerLibraryPath stringByAppendingPathComponent:@"Frameworks"],
      [developerLibraryPath stringByAppendingPathComponent:@"PrivateFrameworks"],
    ];

    NSMutableDictionary *environmentVariables = environment.mutableCopy;
    [environmentVariables addEntriesFromDictionary:@{
      @"DYLD_FALLBACK_FRAMEWORK_PATH" : [testFrameworkPaths componentsJoinedByString:@":"],
      @"DYLD_FALLBACK_LIBRARY_PATH" : [testFrameworkPaths componentsJoinedByString:@":"],
    }];
    environment = environmentVariables.copy;

    FBBundleDescriptor *appBundle = [FBBundleDescriptor bundleFromPath:configuration.runnerAppPath error:nil];
    launchPath = appBundle.binary.path;
    FBProcessSpawnConfiguration *spawnConfiguration = [[FBProcessSpawnConfiguration alloc] initWithLaunchPath:launchPath arguments:@[] environment:environment io:io mode:FBProcessSpawnModeDefault];
    return [FBListTestStrategy listTestProcessWithSpawnConfiguration:spawnConfiguration onTarget:target timeout:timeout logger:logger];

  } else {
    FBProcessSpawnConfiguration *spawnConfiguration = [[FBProcessSpawnConfiguration alloc] initWithLaunchPath:launchPath arguments:@[] environment:environment io:io mode:FBProcessSpawnModeDefault];
    FBArchitectureProcessAdapter *adapter = [[FBArchitectureProcessAdapter alloc] init];

    // Note process adapter may change process configuration launch binary path if it decided to isolate desired arch.
    // For more information look at `FBArchitectureProcessAdapter` docs.
    return [[adapter adaptProcessConfiguration:spawnConfiguration toAnyArchitectureIn:configuration.architectures queue:target.workQueue temporaryDirectory:temporaryDirectory]
            onQueue:target.workQueue fmap:^FBFuture *(FBProcessSpawnConfiguration *mappedConfiguration) {
      return [FBListTestStrategy listTestProcessWithSpawnConfiguration:mappedConfiguration onTarget:target timeout:timeout logger:logger];
    }];
  }
}

+(FBFuture<FBFuture<NSNumber *> *> *)listTestProcessWithSpawnConfiguration:(FBProcessSpawnConfiguration *)spawnConfiguration onTarget:(id<FBiOSTarget, FBProcessSpawnCommands>)target timeout:(NSTimeInterval )timeout logger:(id<FBControlCoreLogger>)logger
{
  return [[target launchProcess:spawnConfiguration] onQueue:target.workQueue map:^id _Nonnull(FBProcess * _Nonnull process) {
    return [FBXCTestProcess ensureProcess:process completesWithin:timeout crashLogCommands:nil queue:target.workQueue logger:logger];
  }];
}

- (id<FBXCTestRunner>)wrapInReporter:(id<FBXCTestReporter>)reporter
{
  return [[FBListTestStrategy_ReporterWrapped alloc] initWithStrategy:self reporter:reporter];
}

@end
