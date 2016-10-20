/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBListTestRunner.h"

#import <sys/types.h>
#import <sys/stat.h>

#import "FBXCTestConfiguration.h"
#import "FBXCTestReporter.h"
#import "FBXCTestShimConfiguration.h"
#import "FBXCTestError.h"

@interface FBListTestRunner ()

@property (nonatomic, strong, readonly) FBXCTestConfiguration *configuration;

@end

@implementation FBListTestRunner

+ (instancetype)runnerWithConfiguration:(FBXCTestConfiguration *)configuration
{
  return [[self alloc] initWithConfiguration:configuration];
}

- (instancetype)initWithConfiguration:(FBXCTestConfiguration *)configuration
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _configuration = configuration;
  return self;
}

- (BOOL)listTestsWithError:(NSError **)error
{
  [self.configuration.reporter didBeginExecutingTestPlan];

  NSString *xctestPath = [self.configuration xctestPathForSimulator:nil];
  NSString *otestQueryPath = self.configuration.shims.macOtestQueryPath;
  NSString *otestQueryOutputPath = [self.configuration.workingDirectory stringByAppendingPathComponent:@"query-output-pipe"];

  if (mkfifo([otestQueryOutputPath UTF8String], S_IWUSR | S_IRUSR) != 0) {
    NSError *posixError = [[NSError alloc] initWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
    return [[[FBXCTestError describeFormat:@"Failed to create a named pipe %@", otestQueryOutputPath] causedBy:posixError] failBool:error];
  }

  NSTask *task = [[NSTask alloc] init];
  task.launchPath = xctestPath;
  task.arguments = @[@"-XCTest", @"All", self.configuration.testBundlePath];
  task.environment = [FBXCTestConfiguration
    buildEnvironmentWithEntries:@{
      @"DYLD_INSERT_LIBRARIES": otestQueryPath,
      @"OTEST_QUERY_OUTPUT_FILE": otestQueryOutputPath,
      @"OtestQueryBundlePath": self.configuration.testBundlePath,
    }
    simulator:nil];
  task.standardOutput = [NSFileHandle fileHandleWithStandardError];
  task.standardError = [NSFileHandle fileHandleWithStandardError];
  [task launch];

  NSFileHandle *otestQueryOutputHandle = [NSFileHandle fileHandleForReadingAtPath:otestQueryOutputPath];
  if (otestQueryOutputHandle == nil) {
    return [[FBXCTestError describeFormat:@"Failed to open fifo for reading: %@", otestQueryOutputPath] failBool:error];
  }

  FBMultiFileReader *multiReader = [FBMultiFileReader new];
  NSMutableData *queryOutput = [NSMutableData data];

  if (![multiReader
        addFileHandle:otestQueryOutputHandle
        withConsumer:^(NSData *data) {
          [queryOutput appendData:data];
        }
        error:error]) {
    return NO;
  }

  if (![multiReader
        readWhileBlockRuns:^{
          [task waitUntilExit];
        }
        error:error]) {
    return NO;
  }

  [otestQueryOutputHandle closeFile];

  NSArray<NSString *> *testNames = [NSJSONSerialization JSONObjectWithData:queryOutput options:0 error:error];
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
    [self.configuration.reporter testCaseDidStartForTestClass:className method:methodName];
    [self.configuration.reporter testCaseDidFinishForTestClass:className method:methodName withStatus:FBTestReportStatusPassed duration:0];
  }

  if (task.terminationStatus != 0) {
    return [[FBXCTestError describeFormat:@"Subprocess exited with code %d: %@ %@", task.terminationStatus, task.launchPath, task.arguments] failBool:error];
  }

  [self.configuration.reporter didFinishExecutingTestPlan];

  return YES;
}

@end
