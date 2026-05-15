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

static NSString *const kReporter_TimestampKey = @"timestamp";
static NSString *const kReporter_Event_Key = @"event";

static NSString *const kReporter_Events_BeginTestSuite = @"begin-test-suite";
static NSString *const kReporter_Events_EndTestSuite = @"end-test-suite";
static NSString *const kReporter_Events_BeginTest = @"begin-test";
static NSString *const kReporter_Events_EndTest = @"end-test";
static NSString *const kReporter_Events_BeginStatus = @"begin-status";
static NSString *const kReporter_Events_EndStatus = @"end-status";

static NSString *const kReporter_TestSuite_TopLevelSuiteName = @"Toplevel Test Suite";
static NSString *const kReporter_BeginTestSuite_SuiteKey = @"suite";

static NSString *const kReporter_EndTestSuite_SuiteKey = @"suite";
static NSString *const kReporter_EndTestSuite_TestCaseCountKey = @"testCaseCount";
static NSString *const kReporter_EndTestSuite_TotalFailureCountKey = @"totalFailureCount";
static NSString *const kReporter_EndTestSuite_UnexpectedExceptionCountKey = @"unexpectedExceptionCount";
static NSString *const kReporter_EndTestSuite_TestDurationKey = @"testDuration";
static NSString *const kReporter_EndTestSuite_TotalDurationKey = @"totalDuration";

static NSString *const kReporter_BeginTest_TestKey = @"test";
static NSString *const kReporter_BeginTest_ClassNameKey = @"className";
static NSString *const kReporter_BeginTest_MethodNameKey = @"methodName";

static NSString *const kReporter_ListTest_TestKey = @"test";
static NSString *const kReporter_ListTest_ClassNameKey = @"className";
static NSString *const kReporter_ListTest_MethodNameKey = @"methodName";
static NSString *const kReporter_ListTest_LegacyTestNameKey = @"legacyTestName";

static NSString *const kReporter_EndTest_TestKey = @"test";
static NSString *const kReporter_EndTest_ClassNameKey = @"className";
static NSString *const kReporter_EndTest_MethodNameKey = @"methodName";
static NSString *const kReporter_EndTest_SucceededKey = @"succeeded";
static NSString *const kReporter_EndTest_ResultKey = @"result";
static NSString *const kReporter_EndTest_TotalDurationKey = @"totalDuration";
static NSString *const kReporter_EndTest_ExceptionsKey = @"exceptions";
static NSString *const kReporter_EndTest_Exception_FilePathInProjectKey = @"filePathInProject";
static NSString *const kReporter_EndTest_Exception_LineNumberKey = @"lineNumber";
static NSString *const kReporter_EndTest_Exception_ReasonKey = @"reason";
static NSString *const kReporter_EndTest_ResultValueError = @"error";
static NSString *const kReporter_EndTest_ResultValueFailure = @"failure";
static NSString *const kReporter_EndTest_ResultValueSuccess = @"success";

static NSString *const kReporter_BeginStatus_MessageKey = @"message";
static NSString *const kReporter_BeginStatus_LevelKey = @"level";

static NSString *const kEnv_LLVMProfileFile = @"LLVM_PROFILE_FILE";
static NSString *const kEnv_LogDirectoryPath = @"LOG_DIRECTORY_PATH";
static NSString *const kEnv_ShimStartXCTest = @"SHIMULATOR_START_XCTEST";
static NSString *const kEnv_WaitForDebugger = @"XCTOOL_WAIT_FOR_DEBUGGER";
