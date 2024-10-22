/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <dlfcn.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "FBXCTestConstants.h"
#import "XCTestCaseHelpers.h"
#import "XCTestPrivate.h"
#import "XTSwizzle.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"

static NSString *const XCTestFilterArg = @"XCTest";
static NSString *const XCTestFrameworkName = @"XCTest";
static NSString *const XCTestProbeClassName = @"XCTestProbe";
static NSString *const XCTestSuiteClassName = @"XCTestSuite";

static FILE *__stdout;
static FILE *__stderr;

static NSMutableArray<NSDictionary<NSString *, id> *> *__testExceptions = nil;
static int __testSuiteDepth = 0;

NSDictionary<NSString *, id> *EventDictionaryWithNameAndContent(NSString *name, NSDictionary *content)
{
  NSMutableDictionary<NSString *, id> *eventJSON = [NSMutableDictionary dictionaryWithDictionary:@{
    kReporter_Event_Key: name,
    kReporter_TimestampKey: @([[NSDate date] timeIntervalSince1970])
  }];
  [eventJSON addEntriesFromDictionary:content];
  return eventJSON;
}


NSArray<XCTestCase *> *TestsFromSuite(id testSuite)
{
  NSMutableArray<XCTestCase *> *tests = [NSMutableArray array];
  NSMutableArray<id> *queue = [NSMutableArray array];
  [queue addObject:testSuite];

  while ([queue count] > 0) {
    id test = [queue objectAtIndex:0];
    [queue removeObjectAtIndex:0];

    if ([test isKindOfClass:[testSuite class]] ||
        [test respondsToSelector:@selector(tests)]) {
      // XCTestSuite keep a list of tests in an ivar called 'tests'.
      id testsInSuite = [test valueForKey:@"tests"];
      NSCAssert(testsInSuite != nil, @"Can't get tests for suite: %@", testSuite);
      [queue addObjectsFromArray:testsInSuite];
    } else {
      [tests addObject:test];
    }
  }
  return tests;
}

// Key used by objc_setAssociatedObject
static int TestDescriptionKey;

static NSString *TestCase_nameOrDescription(id self, SEL cmd)
{
  id description = objc_getAssociatedObject(self, &TestDescriptionKey);
  NSCAssert(description != nil, @"Value for `TestNameKey` wasn't set.");
  return description;
}

static char *const kEventQueueLabel = "xctool.events";

@interface XCToolAssertionHandler : NSAssertionHandler
@end

@implementation XCToolAssertionHandler

- (void)handleFailureInFunction:(NSString *)functionName
                           file:(NSString *)fileName
                     lineNumber:(NSInteger)line
                    description:(NSString *)format, ...
{
  // Format message
  va_list vl;
  va_start(vl, format);
  NSString *msg = [[NSString alloc] initWithFormat:format arguments:vl];
  va_end(vl);

  // Raise exception
  [NSException raise:NSInternalInconsistencyException format:@"*** Assertion failure in %@, %@:%lld: %@", functionName, fileName, (long long)line, msg];
}

@end

static dispatch_queue_t EventQueue()
{
  static dispatch_queue_t eventQueue = {0};
  static dispatch_once_t onceToken;

  dispatch_once(&onceToken, ^{
    // We'll serialize all events through this queue.
    eventQueue = dispatch_queue_create(kEventQueueLabel, DISPATCH_QUEUE_SERIAL);
  });

  return eventQueue;
}

static void PrintJSON(id JSONObject)
{
  NSError *error = nil;
  NSData *data = [NSJSONSerialization dataWithJSONObject:JSONObject options:0 error:&error];

  if (error) {
    fprintf(__stderr,
            "ERROR: Error generating JSON for object: %s: %s\n",
            [[JSONObject description] UTF8String],
            [[error localizedFailureReason] UTF8String]);
    exit(1);
  }

  fwrite([data bytes], 1, [data length], __stdout);
  fputs("\n", __stdout);
  fflush(__stdout);
}

#pragma mark - testSuiteDidStart

static void XCToolLog_testSuiteDidStart(NSString *name)
{
  if (__testSuiteDepth > 0) {
    dispatch_sync(EventQueue(), ^{
      PrintJSON(EventDictionaryWithNameAndContent(
        kReporter_Events_BeginTestSuite,
        @{kReporter_BeginTestSuite_SuiteKey : name}
      ));
    });
  }
  __testSuiteDepth++;
}

static void XCTestLog_testSuiteDidStart(id self, SEL sel, XCTestSuiteRun *run)
{
  XCToolLog_testSuiteDidStart(kReporter_TestSuite_TopLevelSuiteName);
}

static void XCTestLog_testSuiteWillStart(id self, SEL sel, XCTestSuite *suite)
{
  XCToolLog_testSuiteDidStart(parseXCTestSuiteKey(suite));
}

#pragma mark - testSuiteDidStop

static void XCToolLog_testSuiteDidStop(NSString *testSuiteName, XCTestSuiteRun *run)
{
  __testSuiteDepth--;

  if (__testSuiteDepth > 0) {
    NSDictionary<NSString *, id> *content =
      @{
        kReporter_EndTestSuite_SuiteKey : testSuiteName,
        kReporter_EndTestSuite_TestCaseCountKey : @([run testCaseCount]),
        kReporter_EndTestSuite_TotalFailureCountKey : @([run totalFailureCount]),
        kReporter_EndTestSuite_UnexpectedExceptionCountKey : @([run unexpectedExceptionCount]),
        kReporter_EndTestSuite_TestDurationKey: @([run testDuration]),
        kReporter_EndTestSuite_TotalDurationKey : @([run totalDuration]),
      };
    NSDictionary<NSString *, id> *json = EventDictionaryWithNameAndContent(kReporter_Events_EndTestSuite, content);
    dispatch_sync(EventQueue(), ^{
      PrintJSON(json);
    });
  }
}

static void XCTestLog_testSuiteDidStop(id self, SEL sel, XCTestSuiteRun *run)
{
  XCToolLog_testSuiteDidStop(kReporter_TestSuite_TopLevelSuiteName, run);
}

static void XCTestLog_testSuiteDidFinish(id self, SEL sel, XCTestSuite *suite)
{
  XCToolLog_testSuiteDidStop(parseXCTestSuiteKey(suite), (id)suite.testRun);
}

#pragma mark - testCaseDidStart

static void XCToolLog_testCaseDidStart(XCTestCase *testCase)
{
  dispatch_sync(EventQueue(), ^{
    NSString *testKey;
    NSString *className;
    NSString *methodName;
    parseXCTestCase(testCase, &className, &methodName, &testKey);

    PrintJSON(EventDictionaryWithNameAndContent(
      kReporter_Events_BeginTest, @{
        kReporter_BeginTest_TestKey : testKey,
        kReporter_BeginTest_ClassNameKey : className,
        kReporter_BeginTest_MethodNameKey : methodName,
      }
    ));

    __testExceptions = [[NSMutableArray alloc] init];
  });
}

static void XCTestLog_testCaseDidStart(id self, SEL sel, XCTestCaseRun *run)
{
  XCToolLog_testCaseDidStart([run test]);
}

static void XCTestLog_testCaseWillStart(id self, SEL sel, XCTestCase *testCase)
{
  id (*msgsend)(id, SEL) = (void *) objc_msgSend;
  XCTestLog_testCaseDidStart(self, sel, msgsend(testCase, @selector(testRun)));
}

#pragma mark - testCaseDidStop

static void XCToolLog_testCaseDidStop(XCTestCase *testCase, NSNumber *unexpectedExceptionCount, NSNumber *failureCount, NSNumber *totalDuration)
{
  dispatch_sync(EventQueue(), ^{
    NSString *className = nil;
    NSString *methodName = nil;
    NSString *testKey = nil;
    parseXCTestCase(testCase, &className, &methodName, &testKey);

    BOOL errored = [unexpectedExceptionCount integerValue] > 0;
    BOOL failed = [failureCount integerValue] > 0;
    BOOL succeeded = NO;
    NSString *result;
    if (errored) {
      result = kReporter_EndTest_ResultValueError;
    } else if (failed) {
      result = kReporter_EndTest_ResultValueFailure;
    } else {
      result = kReporter_EndTest_ResultValueSuccess;
      succeeded = YES;
    }

    // report test results
    NSArray<NSDictionary<NSString *, id> *> *retExceptions = [__testExceptions copy];
    NSDictionary<NSString *, id> *json = EventDictionaryWithNameAndContent(
      kReporter_Events_EndTest, @{
        kReporter_EndTest_TestKey : testKey,
        kReporter_EndTest_ClassNameKey : className,
        kReporter_EndTest_MethodNameKey : methodName,
        kReporter_EndTest_SucceededKey: @(succeeded),
        kReporter_EndTest_ResultKey : result,
        kReporter_EndTest_TotalDurationKey : totalDuration,
        kReporter_EndTest_ExceptionsKey : retExceptions,
    });

    PrintJSON(json);
  });
}

static void XCTestLog_testCaseDidStop(id self, SEL sel, XCTestCaseRun *run)
{
  XCToolLog_testCaseDidStop([run test], @([run unexpectedExceptionCount]), @([run failureCount]), @([run totalDuration]));
}

static void XCTestLog_testCaseDidFinish(id self, SEL sel, XCTestCase *testCase)
{
  id (*msgsend)(id, SEL) = (void *) objc_msgSend;
  XCTestLog_testCaseDidStop(self, sel, msgsend(testCase, @selector(testRun)));
}

#pragma mark - testCaseDidFail

static void XCToolLog_testCaseDidFail(NSDictionary *exceptionInfo)
{
  dispatch_sync(EventQueue(), ^{
    [__testExceptions addObject:exceptionInfo];
  });
}

static void XCTestLog_testCaseDidFail(id self, SEL sel, XCTestCaseRun *run, NSString *description, NSString *file, NSUInteger line)
{
  XCToolLog_testCaseDidFail(@{
    kReporter_EndTest_Exception_FilePathInProjectKey : file ?: @"Unknown File",
    kReporter_EndTest_Exception_LineNumberKey : @(line),
    kReporter_EndTest_Exception_ReasonKey : description,
  });
}

static void XCTestLog_testCaseDidFailWithDescription(id self, SEL sel, XCTestCase *testCase, NSString *description, NSString *file, NSUInteger line)
{
  id (*msgsend)(id, SEL) = (void *) objc_msgSend;
  XCTestLog_testCaseDidFail(self, sel, msgsend(testCase, @selector(testRun)), description, file, line);
}

#pragma mark - performTest

static void XCPerformTestWithSuppressedExpectedAssertionFailures(id self, SEL origSel, id arg1)
{
  void (*msgsend)(id, SEL, id) = (void *) objc_msgSend;
  int timeout = [@(getenv("TEST_SHIM_TEST_TIMEOUT") ?: "0") intValue];

  NSAssertionHandler *handler = [[XCToolAssertionHandler alloc] init];
  NSThread *currentThread = [NSThread currentThread];
  NSMutableDictionary *currentThreadDict = [currentThread threadDictionary];
  [currentThreadDict setObject:handler forKey:NSAssertionHandlerKey];

  if (timeout > 0) {
    BOOL isSuite = [self isKindOfClass:objc_getClass("XCTestCaseSuite")];
    // If running in a suite, time out if we run longer than the combined timeouts of all tests + a fudge factor.
    int64_t testCount = isSuite ? [[self tests] count] : 1;
    // When in a suite, add a second per test to help account for the time required to switch tests in a suite.
    int64_t fudgeFactor = isSuite ? MAX(testCount, 1) : 0;
    int64_t interval = (timeout * testCount + fudgeFactor) * NSEC_PER_SEC ;
    NSString *queueName = [NSString stringWithFormat:@"test.timer.%p", self];
    dispatch_queue_t queue = dispatch_queue_create([queueName cStringUsingEncoding:NSASCIIStringEncoding], DISPATCH_QUEUE_SERIAL);
    dispatch_set_target_queue(queue, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0));
    dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
    dispatch_source_set_timer(source, dispatch_time(DISPATCH_TIME_NOW, interval), 0, 0);
    dispatch_source_set_event_handler(source, ^{
        if (isSuite) {
            NSString *additionalInformation = @"";
            if ([self respondsToSelector:@selector(testRun)]) {
                XCTestRun *run = [self testRun];
                NSUInteger executedTests = [run executionCount];
                if (executedTests == 0) {
                    additionalInformation = [NSString stringWithFormat:@"(No tests ran, likely stalled in +[%@ setUp])", [self name]];
                } else if (executedTests == testCount) {
                    additionalInformation = [NSString stringWithFormat:@"(All tests ran, likely stalled in +[%@ tearDown])", [self name]];
                }
            }

            [NSException raise:NSInternalInconsistencyException
                        format:@"*** Suite %@ ran longer than combined test time limit: %lld second(s) %@", [self name], testCount * timeout, additionalInformation];

        } else {
            [NSException raise:NSInternalInconsistencyException
                        format:@"*** Test %@ ran longer than specified test time limit: %d second(s)", self, timeout];
        }
    });
    dispatch_resume(source);

    // Call through original implementation
    msgsend(self, origSel, arg1);

    dispatch_source_cancel(source);
  } else {
    // Call through original implementation
    msgsend(self, origSel, arg1);
  }

  // The assertion handler hasn't been touched for our test, so we can safely remove it.
  [currentThreadDict removeObjectForKey:NSAssertionHandlerKey];
}

static void XCWaitForDebuggerIfNeeded()
{
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    NSDictionary<NSString *, NSString *> *env = [[NSProcessInfo processInfo] environment];
    BOOL waitForDebugger = [env[kEnv_WaitForDebugger] isEqualToString:@"YES"];
    if (waitForDebugger) {
      int pid = [[NSProcessInfo processInfo] processIdentifier];
      NSString *beginMessage = [NSString stringWithFormat:@"Waiting for debugger to be attached to pid '%d' ...", pid];
      dispatch_sync(EventQueue(), ^{
        PrintJSON(EventDictionaryWithNameAndContent(
          kReporter_Events_BeginStatus,
          @{
            kReporter_BeginStatus_MessageKey : beginMessage,
            kReporter_BeginStatus_LevelKey : @"Info"
          }
        ));
      });

      // Halt process execution until a debugger is attached
      raise(SIGSTOP);

      NSString *endMessage = [NSString stringWithFormat:@"Debugger was successfully attached to pid '%d'.", pid];
      dispatch_sync(EventQueue(), ^{
        PrintJSON(EventDictionaryWithNameAndContent(
          kReporter_Events_EndStatus,
          @{
            kReporter_BeginStatus_MessageKey : endMessage,
            kReporter_BeginStatus_LevelKey : @"Info"
          }
        ));
      });
    }
  });
}

static void XCTestCase_performTest(id self, SEL sel, id arg1)
{
  SEL originalSelector = @selector(__XCTestCase_performTest:);
  XCWaitForDebuggerIfNeeded();
  XCPerformTestWithSuppressedExpectedAssertionFailures(self, originalSelector, arg1);
}

static void XCTestCaseSuite_performTest(id self, SEL sel, id arg1)
{
  SEL originalSelector = @selector(__XCTestCaseSuite_performTest:);
  XCWaitForDebuggerIfNeeded();
  XCPerformTestWithSuppressedExpectedAssertionFailures(self, originalSelector, arg1);
}

static id XCTRunnerDaemonSession_sharedSession(Class cls, SEL cmd)
{
  return nil;
}

#pragma mark - _enableSymbolication

static BOOL XCTestCase__enableSymbolication(id self, SEL sel)
{
  return NO;
}

#pragma mark - Interposes

/*
 *  We need to close opened fds so all pipe readers are notified and unblocked.
 *  The not obvious and weird part is that we need to print "\n" before closing.
 *  For some reason `select()`, `poll()` and `dispatch_io_read()` will be stuck
 *  if a test calls `exit()` or `abort()`. The found workaround was to print
 *  anithing to a pipe before closing it. Simply closing a pipe doesn't send EOF
 *  to the pipe reader. Printing "\n" should be safe because reader is skipping
 *  empty lines.
 */
static void PrintNewlineAndCloseFDs()
{
  if (__stdout == NULL) {
    return;
  }
  fprintf(__stdout, "\n");
  fclose(__stdout);
  __stdout = NULL;
}

#pragma mark - Entry

static void SwizzleXCTestMethodsIfAvailable()
{
  if ([[[NSBundle mainBundle] bundleIdentifier] hasPrefix:@"com.apple.dt.xctest"]) {
    // Start from Xcode 11.1, XCTest will try to connect to testmanagerd service
    // when reporting test failures (for capture screenshots automatically), and crash
    // if it cannot make a connection.
    // We don't really boot the simulator for running logic tests, so just force
    // it to return nil.
    static dispatch_once_t token;
    dispatch_once(&token, ^{
      XTSwizzleClassSelectorForFunction(
        NSClassFromString(@"XCTRunnerDaemonSession"),
        @selector(sharedSession),
        (IMP)XCTRunnerDaemonSession_sharedSession
      );
    });
  }

  Class testLogClass = objc_getClass("XCTestLog");

  if (testLogClass == nil) {
    // Looks like the XCTest framework has not been loaded yet.
    return;
  }

  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    if ([testLogClass instancesRespondToSelector:@selector(testSuiteWillStart:)]) {
      // Swizzle methods for Xcode 8.
      XTSwizzleSelectorForFunction(
        testLogClass,
        @selector(testSuiteWillStart:),
        (IMP)XCTestLog_testSuiteWillStart
      );
      XTSwizzleSelectorForFunction(
        testLogClass,
        @selector(testSuiteDidFinish:),
        (IMP)XCTestLog_testSuiteDidFinish
      );
      XTSwizzleSelectorForFunction(
        testLogClass,
        @selector(testCaseWillStart:),
        (IMP)XCTestLog_testCaseWillStart
      );
      XTSwizzleSelectorForFunction(
        testLogClass,
        @selector(testCaseDidFinish:),
        (IMP)XCTestLog_testCaseDidFinish
      );
      XTSwizzleSelectorForFunction(
        testLogClass,
        @selector(testCase:didFailWithDescription:inFile:atLine:),
        (IMP)XCTestLog_testCaseDidFailWithDescription
      );
    } else {
      // Swizzle methods for Xcode 7 and earlier.
      XTSwizzleSelectorForFunction(
        testLogClass,
        @selector(testSuiteDidStart:),
        (IMP)XCTestLog_testSuiteDidStart
      );
      XTSwizzleSelectorForFunction(
        testLogClass,
        @selector(testSuiteDidStop:),
        (IMP)XCTestLog_testSuiteDidStop
      );
      XTSwizzleSelectorForFunction(
        testLogClass,
        @selector(testCaseDidStart:),
        (IMP)XCTestLog_testCaseDidStart
      );
      XTSwizzleSelectorForFunction(
        testLogClass,
        @selector(testCaseDidStop:),
        (IMP)XCTestLog_testCaseDidStop
      );
      XTSwizzleSelectorForFunction(
        testLogClass,
        @selector(testCaseDidFail:withDescription:inFile:atLine:),
        (IMP)XCTestLog_testCaseDidFail
      );
      XTSwizzleSelectorForFunction(
        objc_getClass("XCTestCaseSuite"),
        @selector(performTest:),
        (IMP)XCTestCaseSuite_performTest
      );
    }
    XTSwizzleSelectorForFunction(
      objc_getClass("XCTestCase"),
      @selector(performTest:),
      (IMP)XCTestCase_performTest
    );
    if ([objc_getClass("XCTestCase") respondsToSelector:@selector(_enableSymbolication)]) {
      // Disable symbolication thing on xctest 7 because it sometimes takes forever.
      XTSwizzleClassSelectorForFunction(
        objc_getClass("XCTestCase"),
        @selector(_enableSymbolication),
        (IMP)XCTestCase__enableSymbolication
      );
    }
  });
}

static void listBundle(NSString *testBundlePath, NSString *outputFile)
{
  NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:outputFile];
  NSBundle *bundle = [NSBundle bundleWithPath:testBundlePath];
  if (!bundle) {
    fprintf(
      stderr,
      "Bundle '%s' does not identify an accessible bundle directory.\n",
      testBundlePath.UTF8String
    );
    exit(TestShimExitCodeBundleOpenError);
  }
  if (![bundle executablePath]) {
    fprintf(stderr, "The bundle at %s does not contain an executable.\n", [testBundlePath UTF8String]);
    exit(TestShimExitCodeMissingExecutable);
  }

  // Make sure the 'XCTest' preference is cleared before we load the
  // test bundle - otherwise we may accidentally start running tests.
  //
  // Instead of seeing the JSON list of test methods, you'll see output like ...
  //
  //   Test Suite 'All tests' started at 2013-11-07 23:47:46 +0000
  //   Test Suite 'All tests' finished at 2013-11-07 23:47:46 +0000.
  //   Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.001) seconds
  //
  // Here's what happens -- As soon as we dlopen() the test bundle, it will also
  // trigger the linker to load XCTest.framework since those are linked by the test bundle.
  // And, as soon as the testing framework loads, the class initializer
  // '+[XCTestSuite initialize]' is triggered.
  //
  // By clearing the preference, we can prevent tests from running.
  [NSUserDefaults.standardUserDefaults removeObjectForKey:XCTestFrameworkName];
  [NSUserDefaults.standardUserDefaults synchronize];

  // We use dlopen() instead of -[NSBundle loadAndReturnError] because, if
  // something goes wrong, dlerror() gives us a much more helpful error message.
  if (dlopen([[bundle executablePath] UTF8String], RTLD_LAZY) == NULL) {
    fprintf(stderr, "%s\n", dlerror());
    exit(TestShimExitCodeDLOpenError);
  }

  // Load the Test Bundle's 'Principal Class' and initialize it.
  // This is necessary for some Testing Frameworks that dynamically add XCTests
  // inside the basic `-init` method.
  Class principalClass = [bundle principalClass];
  if (principalClass && [principalClass instancesRespondToSelector:@selector(init)]) {
    NSLog(@"Calling Principal Class initializer -[%@ init]", NSStringFromClass(principalClass));
    id principalObject = [[principalClass alloc] init];
    NSLog(@"Principal Class %@ initialized", principalObject);
  }

  // Ensure that the principal class exists.
  Class testSuiteClass = NSClassFromString(XCTestSuiteClassName);
  NSCAssert(testSuiteClass, @"Should have %@ class", XCTestFrameworkName);

  // By setting `-XCTest None`, we'll make `-[XCTestSuite allTests]`
  // return all tests.
  [NSUserDefaults.standardUserDefaults setObject:@"None" forKey:XCTestFilterArg];
  XCTestSuite *allTestsSuite = [testSuiteClass performSelector:@selector(allTests)];
  NSCAssert(allTestsSuite, @"Should have gotten a test suite from allTests");

  // Enumerate the test cases, constructing the reported name for them.
  NSArray<XCTestCase *> *allTestCases = TestsFromSuite(allTestsSuite);
  NSMutableArray<NSDictionary<NSString *, NSString *> *> *testsToReport = NSMutableArray.array;
  for (XCTestCase *testCase in allTestCases) {
    NSString *className = nil;
    NSString *methodName = nil;
    NSString *testKey = nil;
    parseXCTestCase(testCase, &className, &methodName, &testKey);
    NSString *legacyTestName = [NSString stringWithFormat:@"%@/%@", className, methodName];
    NSLog(@"Found test: %@", legacyTestName);
    [testsToReport addObject:@{
      kReporter_ListTest_LegacyTestNameKey: legacyTestName,
      kReporter_ListTest_ClassNameKey: className,
      kReporter_ListTest_MethodNameKey: methodName,
      kReporter_ListTest_TestKey: testKey,
    }];
  }

  // Now write them out after sorting
  [testsToReport sortUsingComparator:^ NSComparisonResult (NSDictionary<NSString *, NSString *> *left, NSDictionary<NSString *, NSString *> *right) {
    return [left[kReporter_ListTest_LegacyTestNameKey] compare:right[kReporter_ListTest_LegacyTestNameKey]];
  }];
  NSError *error = nil;
  NSData *output = [NSJSONSerialization dataWithJSONObject:testsToReport options:0 error:&error];
  NSCAssert(output, @"Failed to generate test list JSON", error);
  bool fileWrittenSuccessfully = [fileHandle writeData:output error:&error];
  NSCAssert(fileWrittenSuccessfully, @"Failed to write test list to file", error);

  // Close the file so the other end knows this is the end of the input.
  bool fileClosedSuccessfully = [fileHandle closeAndReturnError:&error];
  NSCAssert(fileClosedSuccessfully, @"Failed to close file with test list", error);
  exit(TestShimExitCodeSuccess);
}

static BOOL NSBundle_loadAndReturnError(id self, SEL sel, NSError **error)
{
  BOOL (*msgsend)(id, SEL, NSError **) = (void *) objc_msgSend;
  SEL originalSelector = @selector(__NSBundle_loadAndReturnError:);
  BOOL result = msgsend(self, originalSelector, error);
  SwizzleXCTestMethodsIfAvailable();
  return result;
}

static void assignOutputFiles(void)
{
  static const char *stdoutFileKey = "TEST_SHIM_STDOUT_PATH";
  FILE *shimStdoutFile = fopen(getenv(stdoutFileKey), "w");
  if (shimStdoutFile) {
    __stdout = shimStdoutFile;
  } else {
    int stdoutHandle = dup(STDOUT_FILENO);
    __stdout = fdopen(stdoutHandle, "w");
  }
  setvbuf(__stdout, NULL, _IONBF, 0);

  static const char *stderrFileKey = "TEST_SHIM_STDERR_PATH";
  FILE *shimStderrFile = fopen(getenv(stderrFileKey), "w");
  if (shimStderrFile) {
    __stderr = shimStderrFile;
  } else {
    int stderrHandle = dup(STDERR_FILENO);
    __stderr = fdopen(stderrHandle, "w");
  }
}

void handle_signal(int signal)
{
  PrintNewlineAndCloseFDs();
}

static id SimServiceContext_deviceSetWithPath_error(id cls, SEL sel, NSString *path, NSError **error)
{
  id (*msgsend)(id, SEL, NSString *, NSError **) = (void *) objc_msgSend;
  SEL originalSelector = @selector(__SimServiceContext_deviceSetWithPath:error:);
  NSString *simDeviceSetPath = NSProcessInfo.processInfo.environment[@"SIM_DEVICE_SET_PATH"];
  NSLog(@"Calling original -[SimServiceContext deviceSetWithPath:error:] with a custom path: %@", simDeviceSetPath);
  return msgsend(cls, originalSelector, simDeviceSetPath, error);
}

static void SwizzleXcodebuildMethods()
{
  static dispatch_once_t token;
  dispatch_once(&token, ^{
    NSLog(@"Swizzling -[SimServiceContext deviceSetWithPath:error:]");
    NSBundle *bundle = [[NSBundle alloc] initWithPath:@"/Library/Developer/PrivateFrameworks/CoreSimulator.framework"];
    NSError *error = nil;
    [bundle loadAndReturnError:&error];
    if (error) {
      NSLog(@"ERROR: failed to load CoreSimulator.framework: %@", [error localizedFailureReason]);
      exit(1);
    }
    XTSwizzleSelectorForFunction(
      // @lint-ignore FBOBJCDISCOURAGEDFUNCTION
      objc_getClass("SimServiceContext"),
      @selector(deviceSetWithPath:error:),
      (IMP)SimServiceContext_deviceSetWithPath_error
    );
  });
}

__attribute__((constructor)) static void EntryPoint()
{
  // Unset so we don't cascade into any other process that might be spawned.
  unsetenv("DYLD_INSERT_LIBRARIES");

  NSString *bundlePath = NSProcessInfo.processInfo.environment[@"TEST_SHIM_BUNDLE_PATH"];
  if (bundlePath) {
    assignOutputFiles();

    // Listing takes a different path, if the 'TEST_SHIM_OUTPUT_PATH' is set.
    NSString *listPath = NSProcessInfo.processInfo.environment[@"TEST_SHIM_OUTPUT_PATH"];
    if (listPath) {
      NSLog(@"Querying Bundle %@ to Path %@", bundlePath, listPath);
      listBundle(bundlePath, listPath);
      return;
    }


  // Install a signal handler to deal with tests crashing.
    struct sigaction sa_abort;
    sa_abort.sa_handler = &handle_signal;
    sigaction(SIGABRT, &sa_abort, NULL);

    // Let's register to get notified when libraries are initialized
    XTSwizzleSelectorForFunction([NSBundle class], @selector(loadAndReturnError:), (IMP)NSBundle_loadAndReturnError);

    // Then Swizzle
    SwizzleXCTestMethodsIfAvailable();
    return;
  }

  NSString *simDeviceSetPath = NSProcessInfo.processInfo.environment[@"SIM_DEVICE_SET_PATH"];
  if (simDeviceSetPath) {
    BOOL isDir = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:simDeviceSetPath isDirectory:&isDir]) {
      NSLog(@"ERROR: SIM_DEVICE_SET_PATH (%@) does not exist", simDeviceSetPath);
      exit(1);
    }
    if (!isDir) {
      NSLog(@"ERROR: SIM_DEVICE_SET_PATH (%@) is not a directory", simDeviceSetPath);
      exit(1);
    }
    SwizzleXcodebuildMethods();
    return;
  }
}

__attribute__((destructor)) static void ExitPoint()
{
  PrintNewlineAndCloseFDs();
}

#pragma clang diagnostic pop
