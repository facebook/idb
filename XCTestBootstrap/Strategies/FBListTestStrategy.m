/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBListTestStrategy.h"

#import <sys/types.h>
#import <sys/stat.h>

#import <FBControlCore/FBControlCore.h>
#import <XCTestBootstrap/XCTestBootstrap.h>

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


- (BOOL)executeWithError:(NSError **)error
{
  [self.reporter didBeginExecutingTestPlan];

  NSTimeInterval timeout = FBControlCoreGlobalConfiguration.slowTimeout;
  NSArray<NSString *> *testNames = [self.strategy listTestsWithTimeout:timeout error:error];
  if (!testNames) {
    return NO;
  }
  for (NSString *testName in testNames) {
    NSRange slashRange = [testName rangeOfString:@"/"];
    NSString *className = [testName substringToIndex:slashRange.location];
    NSString *methodName = [testName substringFromIndex:slashRange.location + 1];
    [self.reporter testCaseDidStartForTestClass:className method:methodName];
    [self.reporter testCaseDidFinishForTestClass:className method:methodName withStatus:FBTestReportStatusPassed duration:0];
  }

  [self.reporter didFinishExecutingTestPlan];
  return YES;
}

@end

@interface FBListTestStrategy ()

@property (nonatomic, strong, readonly) id<FBXCTestProcessExecutor> executor;
@property (nonatomic, strong, readonly) FBListTestConfiguration *configuration;
@property (nonatomic, strong, readonly) id<FBControlCoreLogger> logger;

@end

@implementation FBListTestStrategy

+ (instancetype)strategyWithExecutor:(id<FBXCTestProcessExecutor>)executor configuration:(FBListTestConfiguration *)configuration logger:(id<FBControlCoreLogger>)logger
{
  return [[self alloc] initWithExecutor:executor configuration:configuration logger:logger];
}

- (instancetype)initWithExecutor:(id<FBXCTestProcessExecutor>)executor configuration:(FBListTestConfiguration *)configuration logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _executor = executor;
  _configuration = configuration;
  _logger = logger;

  return self;
}

- (nullable NSArray<NSString *> *)listTestsWithTimeout:(NSTimeInterval)timeout error:(NSError **)error
{
  NSString *xctestPath = self.configuration.destination.xctestPath;
  NSString *otestQueryPath = self.executor.queryShimPath;
  NSString *otestQueryOutputPath = [self.configuration.workingDirectory stringByAppendingPathComponent:@"query-output-pipe"];

  if (mkfifo([otestQueryOutputPath UTF8String], S_IWUSR | S_IRUSR) != 0) {
    NSError *posixError = [[NSError alloc] initWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
    return [[[FBXCTestError
      describeFormat:@"Failed to create a named pipe %@", otestQueryOutputPath]
      causedBy:posixError]
      fail:error];
  }

  NSArray<NSString *> *arguments = @[@"-XCTest", @"All", self.configuration.testBundlePath];
  NSDictionary<NSString *, NSString *> *environment = @{
    @"DYLD_INSERT_LIBRARIES": otestQueryPath,
    @"OTEST_QUERY_OUTPUT_FILE": otestQueryOutputPath,
    @"OtestQueryBundlePath": self.configuration.testBundlePath,
  };
  FBXCTestProcess *process = [FBXCTestProcess
    processWithLaunchPath:xctestPath
    arguments:arguments
    environment:environment
    waitForDebugger:NO
    stdOutReader:FBFileWriter.nullWriter
    stdErrReader:FBFileWriter.nullWriter
    executor:self.executor];

  // Start the process.
  pid_t processIdentifier = [process startWithError:error];
  if (!processIdentifier) {
    return nil;
  }
  FBAccumilatingFileConsumer *consumer = [FBAccumilatingFileConsumer new];
  FBFileReader *reader = [FBFileReader readerWithFilePath:otestQueryOutputPath consumer:consumer error:error];
  if (![reader startReadingWithError:error]) {
    return nil;
  }

  // Wait for the subprocess to terminate.
  // Then make sure that the file has finished being read.
  NSError *innerError = nil;
  BOOL completedSuccessfully = [process waitForCompletionWithTimeout:timeout error:&innerError];
  if (![reader stopReadingWithError:error]) {
    return nil;
  }
  if (!completedSuccessfully) {
    return [[[FBXCTestError
      describeFormat:@"Waited %f seconds for list-test task to terminate", timeout]
      causedBy:innerError]
      fail:error];
  }

  NSString *output = [[NSString alloc] initWithData:consumer.data encoding:NSUTF8StringEncoding];
  NSArray<NSString *> *lines = [output componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
  NSMutableArray<NSString *> *testNames = [NSMutableArray array];

  for (NSString *line in lines) {
    if (line.length == 0) {
      // Ignore empty lines
      continue;
    }
    NSRange slashRange = [line rangeOfString:@"/"];
    if (slashRange.length == 0) {
      return [[FBXCTestError
        describeFormat:@"Received unexpected test name from shim: %@", line]
        fail:error];
    }
    [testNames addObject:line];
  }
  return [testNames copy];
}

- (id<FBXCTestRunner>)wrapInReporter:(id<FBXCTestReporter>)reporter
{
  return [[FBListTestStrategy_ReporterWrapped alloc] initWithStrategy:self reporter:reporter];
}

@end
