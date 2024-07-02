/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, TestShimExitCode) {
  TestShimExitCodeSuccess = 0,
  TestShimExitCodeDLOpenError = 10,
  TestShimExitCodeBundleOpenError = 11,
  TestShimExitCodeMissingExecutable = 12,
  TestShimExitCodeXCTestFailedLoading = 13,
};

#define kReporter_TimestampKey @"timestamp"
#define kReporter_Event_Key @"event"

#define kReporter_Events_BeginTestSuite @"begin-test-suite"
#define kReporter_Events_EndTestSuite @"end-test-suite"
#define kReporter_Events_BeginTest @"begin-test"
#define kReporter_Events_EndTest @"end-test"
#define kReporter_Events_BeginStatus @"begin-status"
#define kReporter_Events_EndStatus @"end-status"

#define kReporter_TestSuite_TopLevelSuiteName @"Toplevel Test Suite"
#define kReporter_BeginTestSuite_SuiteKey @"suite"

#define kReporter_EndTestSuite_SuiteKey @"suite"
#define kReporter_EndTestSuite_TestCaseCountKey @"testCaseCount"
#define kReporter_EndTestSuite_TotalFailureCountKey @"totalFailureCount"
#define kReporter_EndTestSuite_UnexpectedExceptionCountKey @"unexpectedExceptionCount"
#define kReporter_EndTestSuite_TestDurationKey @"testDuration"
#define kReporter_EndTestSuite_TotalDurationKey @"totalDuration"

#define kReporter_BeginTest_TestKey @"test"
#define kReporter_BeginTest_ClassNameKey @"className"
#define kReporter_BeginTest_MethodNameKey @"methodName"

#define kReporter_ListTest_TestKey @"test"
#define kReporter_ListTest_ClassNameKey @"className"
#define kReporter_ListTest_MethodNameKey @"methodName"
#define kReporter_ListTest_LegacyTestNameKey @"legacyTestName"

#define kReporter_EndTest_TestKey @"test"
#define kReporter_EndTest_ClassNameKey @"className"
#define kReporter_EndTest_MethodNameKey @"methodName"
#define kReporter_EndTest_SucceededKey @"succeeded"
#define kReporter_EndTest_ResultKey @"result"
#define kReporter_EndTest_TotalDurationKey @"totalDuration"
#define kReporter_EndTest_ExceptionsKey @"exceptions"
#define kReporter_EndTest_Exception_FilePathInProjectKey @"filePathInProject"
#define kReporter_EndTest_Exception_LineNumberKey @"lineNumber"
#define kReporter_EndTest_Exception_ReasonKey @"reason"
#define kReporter_EndTest_ResultValueError @"error"
#define kReporter_EndTest_ResultValueFailure @"failure"
#define kReporter_EndTest_ResultValueSuccess @"success"

#define kReporter_BeginStatus_MessageKey @"message"
#define kReporter_BeginStatus_LevelKey @"level"

#define kEnv_LLVMProfileFile @"LLVM_PROFILE_FILE"
#define kEnv_LogDirectoryPath @"LOG_DIRECTORY_PATH"
#define kEnv_ShimStartXCTest @"SHIMULATOR_START_XCTEST"
#define kEnv_WaitForDebugger @"XCTOOL_WAIT_FOR_DEBUGGER"
