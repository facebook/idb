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

@interface FBListTestStrategy ()

@property (nonatomic, strong, readonly) FBListTestConfiguration *configuration;
@property (nonatomic, strong, readonly) id<FBXCTestReporter> reporter;

@end

@implementation FBListTestStrategy

+ (instancetype)macOSStrategyWithConfiguration:(FBListTestConfiguration *)configuration reporter:(id<FBXCTestReporter>)reporter
{
  return [[self alloc] initWithConfiguration:configuration reporter:reporter];
}

- (instancetype)initWithConfiguration:(FBListTestConfiguration *)configuration reporter:(id<FBXCTestReporter>)reporter
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _configuration = configuration;
  _reporter = reporter;

  return self;
}

- (BOOL)executeWithError:(NSError **)error
{
  [self.reporter didBeginExecutingTestPlan];

  NSString *xctestPath = self.configuration.destination.xctestPath;
  NSString *otestQueryPath = self.configuration.shims.macOtestQueryPath;
  NSString *otestQueryOutputPath = [self.configuration.workingDirectory stringByAppendingPathComponent:@"query-output-pipe"];

  if (mkfifo([otestQueryOutputPath UTF8String], S_IWUSR | S_IRUSR) != 0) {
    NSError *posixError = [[NSError alloc] initWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
    return [[[FBXCTestError describeFormat:@"Failed to create a named pipe %@", otestQueryOutputPath] causedBy:posixError] failBool:error];
  }

  NSArray<NSString *> *arguments = @[@"-XCTest", @"All", self.configuration.testBundlePath];
  NSDictionary<NSString *, NSString *> *environment = @{
    @"DYLD_INSERT_LIBRARIES": otestQueryPath,
    @"OTEST_QUERY_OUTPUT_FILE": otestQueryOutputPath,
    @"OtestQueryBundlePath": self.configuration.testBundlePath,
  };

  FBTask *task = [[[[[FBTaskBuilder
    withLaunchPath:xctestPath]
    withArguments:arguments]
    withEnvironmentAdditions:environment]
    build]
    startAsynchronously];

  FBAccumilatingFileConsumer *consumer = [FBAccumilatingFileConsumer new];
  FBFileReader *reader = [FBFileReader readerWithFilePath:otestQueryOutputPath consumer:consumer error:error];
  if (![reader startReadingWithError:error]) {
    return NO;
  }

  // Wait for the subprocess to terminate.
  // Then make sure that the file has finished being read.
  NSTimeInterval timeout = FBControlCoreGlobalConfiguration.slowTimeout;
  NSError *innerError = nil;
  BOOL waitSuccess = [task waitForCompletionWithTimeout:timeout error:&innerError];
  if (![reader stopReadingWithError:error]) {
    return NO;
  }

  if (!waitSuccess) {
    return [[[FBXCTestError
      describeFormat:@"Waited %f seconds for list-test task to terminate", timeout]
      causedBy:innerError]
      failBool:error];
  }
  if (!task.wasSuccessful) {
    return [[[FBXCTestError
      describeFormat:@"The Listing of Tests Failed: %@", task.error.localizedDescription]
      causedBy:task.error]
      failBool:error];
  }

  NSArray<NSString *> *testNames = [NSJSONSerialization JSONObjectWithData:consumer.data options:0 error:error];
  if (testNames == nil) {
    return NO;
  }
  for (NSString *testName in testNames) {
    NSRange slashRange = [testName rangeOfString:@"/"];
    if (slashRange.length == 0) {
      return [[FBXCTestError describeFormat:@"Received unexpected test name from xctool: %@", testName] failBool:error];
    }
    NSString *className = [testName substringToIndex:slashRange.location];
    NSString *methodName = [testName substringFromIndex:slashRange.location + 1];
    [self.reporter testCaseDidStartForTestClass:className method:methodName];
    [self.reporter testCaseDidFinishForTestClass:className method:methodName withStatus:FBTestReportStatusPassed duration:0];
  }

  [self.reporter didFinishExecutingTestPlan];

  return YES;
}

@end
