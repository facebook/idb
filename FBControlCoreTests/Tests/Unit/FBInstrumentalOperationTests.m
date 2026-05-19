/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import <FBControlCore/FBControlCore.h>
#import <FBControlCore/FBInstrumentalOperation.h>

#import "FBControlCoreLoggerDouble.h"
#import "FBiOSTargetDouble.h"

// Expose private method for testing
@interface FBInstrumentalOperation (Testing)
+ (FBFuture<FBInstrumentsOperation *> *)instrumentalOperationWithTargetInternal:(id<FBiOSTarget>)target
                                                                  configuration:(FBInstrumentsConfiguration *)configuration
                                                                         logger:(id<FBControlCoreLogger>)logger;
@end

#pragma mark - Test Class

@interface FBInstrumentalOperationTests : XCTestCase
@end

@implementation FBInstrumentalOperationTests
{
  FBControlCoreLoggerDouble *_logger;
  dispatch_queue_t _queue;
  NSString *_tempDir;
}

- (void)setUp
{
  [super setUp];
  _logger = [[FBControlCoreLoggerDouble alloc] init];
  _queue = dispatch_queue_create("com.facebook.fbcontrolcore.tests.instrumental", DISPATCH_QUEUE_SERIAL);
  _tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
  [[NSFileManager defaultManager] createDirectoryAtPath:_tempDir withIntermediateDirectories:YES attributes:nil error:nil];
}

- (void)tearDown
{
  [[NSFileManager defaultManager] removeItemAtPath:_tempDir error:nil];
  [super tearDown];
}

#pragma mark - Stop Tests

- (void)testStop_WhenExitCodeIsZero_ReturnsTraceDir
{
  // Arrange
  FBMutableFuture *statLoc = FBMutableFuture.future;
  [statLoc resolveWithResult:@0];
  FBMutableFuture *exitCodeFuture = FBMutableFuture.future;
  FBMutableFuture *signalFuture = FBMutableFuture.future;

  FBSubprocess *task = [[FBSubprocess alloc] initWithProcessIdentifier:0
                                                               statLoc:statLoc
                                                              exitCode:exitCodeFuture
                                                                signal:signalFuture
                                                         configuration:nil
                                                                 queue:_queue];

  NSURL *traceDir = [NSURL fileURLWithPath:_tempDir];
  FBInstrumentsTimings *timings = [FBInstrumentsTimings timingsWithTerminateTimeout:5.0
                                                               launchRetryTimeout:10.0
                                                              launchErrorTimeout:5.0
                                                             operationDuration:60.0];
  FBInstrumentsConfiguration *config = [FBInstrumentsConfiguration configurationWithTemplateName:@"TestTemplate"
                                                                              targetApplication:@""
                                                                               appEnvironment:@{}
                                                                                 appArguments:@[]
                                                                                toolArguments:@[]
                                                                                      timings:timings];

  FBInstrumentalOperation *operation = [[FBInstrumentalOperation alloc] initWithTask:task
                                                                           traceDir:traceDir
                                                                      configuration:config
                                                                              queue:_queue
                                                                             logger:_logger];

  // Resolve exit code to 0 (success)
  [exitCodeFuture resolveWithResult:@0];

  // Act
  NSError *error = nil;
  NSURL *result = [[operation stop] await:&error];

  // Assert
  XCTAssertNil(error, @"Stop should not produce an error for exit code 0");
  XCTAssertEqualObjects(result, traceDir, @"Stop should return the trace directory on success");
}

- (void)testStop_WhenExitCodeIsNonZero_ReturnsError
{
  // Arrange
  FBMutableFuture *statLoc = FBMutableFuture.future;
  [statLoc resolveWithResult:@0];
  FBMutableFuture *exitCodeFuture = FBMutableFuture.future;
  FBMutableFuture *signalFuture = FBMutableFuture.future;

  FBSubprocess *task = [[FBSubprocess alloc] initWithProcessIdentifier:0
                                                               statLoc:statLoc
                                                              exitCode:exitCodeFuture
                                                                signal:signalFuture
                                                         configuration:nil
                                                                 queue:_queue];

  NSURL *traceDir = [NSURL fileURLWithPath:_tempDir];
  FBInstrumentsTimings *timings = [FBInstrumentsTimings timingsWithTerminateTimeout:5.0
                                                               launchRetryTimeout:10.0
                                                              launchErrorTimeout:5.0
                                                             operationDuration:60.0];
  FBInstrumentsConfiguration *config = [FBInstrumentsConfiguration configurationWithTemplateName:@"TestTemplate"
                                                                              targetApplication:@""
                                                                               appEnvironment:@{}
                                                                                 appArguments:@[]
                                                                                toolArguments:@[]
                                                                                      timings:timings];

  FBInstrumentalOperation *operation = [[FBInstrumentalOperation alloc] initWithTask:task
                                                                           traceDir:traceDir
                                                                      configuration:config
                                                                              queue:_queue
                                                                             logger:_logger];

  // Resolve exit code to 137 (SIGKILL, a realistic non-zero exit code)
  [exitCodeFuture resolveWithResult:@137];

  // Act
  NSError *error = nil;
  NSURL *result = [[operation stop] await:&error];

  // Assert
  XCTAssertNil(result, @"Stop should not return a result for non-zero exit code");
  XCTAssertNotNil(error, @"Stop should produce an error for non-zero exit code");
}

#pragma mark - instrumentalOperationWithTargetInternal Error Path Tests

- (void)testInternalOperation_WhenDirectoryCreationFails_ReturnsError
{
  // Arrange - use a non-existent parent directory so directory creation fails
  FBiOSTargetDouble *target = [[FBiOSTargetDouble alloc] init];
  target.auxillaryDirectory = @"/nonexistent/path/that/does/not/exist";
  target.udid = @"test-udid";

  FBInstrumentsTimings *timings = [FBInstrumentsTimings timingsWithTerminateTimeout:5.0
                                                               launchRetryTimeout:10.0
                                                              launchErrorTimeout:5.0
                                                             operationDuration:60.0];
  FBInstrumentsConfiguration *config = [FBInstrumentsConfiguration configurationWithTemplateName:@"TestTemplate"
                                                                              targetApplication:@""
                                                                               appEnvironment:@{}
                                                                                 appArguments:@[]
                                                                                toolArguments:@[@"/usr/bin/true", @"{}"]
                                                                                      timings:timings];

  // Act
  NSError *error = nil;
  id result = [[FBInstrumentalOperation instrumentalOperationWithTargetInternal:target
                                                                 configuration:config
                                                                        logger:_logger] await:&error];

  // Assert
  XCTAssertNil(result, @"Should fail when directory creation fails");
  XCTAssertNotNil(error, @"Should produce an error when directory creation fails");
}

- (void)testInternalOperation_WhenExecutablePathIsInvalid_ReturnsError
{
  // Arrange - use a valid directory but invalid executable path
  FBiOSTargetDouble *target = [[FBiOSTargetDouble alloc] init];
  target.auxillaryDirectory = _tempDir;
  target.udid = @"test-udid";

  FBInstrumentsTimings *timings = [FBInstrumentsTimings timingsWithTerminateTimeout:5.0
                                                               launchRetryTimeout:10.0
                                                              launchErrorTimeout:5.0
                                                             operationDuration:60.0];
  FBInstrumentsConfiguration *config = [FBInstrumentsConfiguration configurationWithTemplateName:@"TestTemplate"
                                                                              targetApplication:@""
                                                                               appEnvironment:@{}
                                                                                 appArguments:@[]
                                                                                toolArguments:@[@"/nonexistent/instrumental", @"{}"]
                                                                                      timings:timings];

  // Act
  NSError *error = nil;
  id result = [[FBInstrumentalOperation instrumentalOperationWithTargetInternal:target
                                                                 configuration:config
                                                                        logger:_logger] await:&error];

  // Assert
  XCTAssertNil(result, @"Should fail when executable path is invalid");
  XCTAssertNotNil(error, @"Should produce an error when executable path is invalid");
}

- (void)testInternalOperation_WhenJsonConfigIsInvalid_ReturnsError
{
  // Arrange - use a valid directory and valid executable but invalid JSON
  FBiOSTargetDouble *target = [[FBiOSTargetDouble alloc] init];
  target.auxillaryDirectory = _tempDir;
  target.udid = @"test-udid";

  FBInstrumentsTimings *timings = [FBInstrumentsTimings timingsWithTerminateTimeout:5.0
                                                               launchRetryTimeout:10.0
                                                              launchErrorTimeout:5.0
                                                             operationDuration:60.0];
  // Use /bin/sh as the executable (it's always present and executable)
  FBInstrumentsConfiguration *config = [FBInstrumentsConfiguration configurationWithTemplateName:@"TestTemplate"
                                                                              targetApplication:@""
                                                                               appEnvironment:@{}
                                                                                 appArguments:@[]
                                                                                toolArguments:@[@"/bin/sh", @"not valid json {{{"]
                                                                                      timings:timings];

  // Act
  NSError *error = nil;
  id result = [[FBInstrumentalOperation instrumentalOperationWithTargetInternal:target
                                                                 configuration:config
                                                                        logger:_logger] await:&error];

  // Assert
  XCTAssertNil(result, @"Should fail when JSON config is invalid");
  XCTAssertNotNil(error, @"Should produce an error when JSON config is invalid");
}

@end
