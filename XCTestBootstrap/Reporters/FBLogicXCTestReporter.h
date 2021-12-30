/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

/**
 Protocol used by the logic test shim to report
 back events during test execution.
 */
@protocol FBLogicXCTestReporter <NSObject>

/**
 Called when a process has been launched and is awaiting a debugger to be attached.

 @param pid the process identifer of the waiting process.
 */
- (void)processWaitingForDebuggerWithProcessIdentifier:(pid_t)pid;


/**
 Called when the test plan has started executing.
 */
- (void)didBeginExecutingTestPlan;

/**
 Called when the test plan has finished executing.
 */
- (void)didFinishExecutingTestPlan;

/**
 Called when the test process has some output.

 @param output the test output.
 */
- (void)testHadOutput:(NSString *)output;

/**
 Called when an event happens
 @param data JSON Encoded bytes.
 */
- (void)handleEventJSONData:(NSData *)data;

/**
 Called when the test process has crashed mid test

 @param error error returned by the test process, most likely includes a stack trace
 */
- (void)didCrashDuringTest:(NSError *)error;

@end
