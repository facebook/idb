/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <dlfcn.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "ReporterEvents.h"
#import "XCTestPrivate.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"

void ParseClassAndMethodFromTestName(NSString **className, NSString **methodName, NSString *testName)
{
  NSCAssert(className, @"className should be non-nil");
  NSCAssert(methodName, @"methodName should be non-nil");
  NSCAssert(testName, @"testName should be non-nil");

  static dispatch_once_t onceToken;
  static NSRegularExpression *testNameRegex;
  dispatch_once(&onceToken, ^{
    testNameRegex = [[NSRegularExpression alloc] initWithPattern:@"^-\\[([\\w.]+) ([\\w\\:]+)\\]$"
                                                         options:0
                                                           error:nil];
  });

  NSTextCheckingResult *match =
  [testNameRegex firstMatchInString:testName
                            options:0
                              range:NSMakeRange(0, [testName length])];
  NSCAssert(match && [match numberOfRanges] == 3,
            @"Test name seems to be malformed: %@", testName);

  *className = [testName substringWithRange:[match rangeAtIndex:1]];
  *methodName = [testName substringWithRange:[match rangeAtIndex:2]];
}


NSString *const kTestingFrameworkTestProbeClassName = @"kTestingFrameworkTestProbeClassName";
NSString *const kTestingFrameworkTestSuiteClassName = @"kTestingFrameworkTestSuiteClassName";
NSString *const kTestingFrameworkIOSTestrunnerName = @"ios_executable";
NSString *const kTestingFrameworkOSXTestrunnerName = @"osx_executable";
NSString *const kTestingFrameworkInvertScopeKey = @"invertScope";
NSString *const kTestingFrameworkFilterTestArgsKey = @"filterTestcasesArg";

static NSDictionary<NSString *, NSString *> *XCTestFrameworkInfo()
{
  return @{
    kTestingFrameworkTestProbeClassName: @"XCTestProbe",
    kTestingFrameworkTestSuiteClassName: @"XCTestSuite",
    kTestingFrameworkIOSTestrunnerName: @"usr/bin/xctest",
    kTestingFrameworkOSXTestrunnerName: @"usr/bin/xctest",
    kTestingFrameworkFilterTestArgsKey: @"XCTest",
    kTestingFrameworkInvertScopeKey: @"XCTestInvertScope"
  };
}

NSDictionary *EventDictionaryWithNameAndContent(NSString *name, NSDictionary *content)
{
  NSMutableDictionary *eventJSON = [NSMutableDictionary dictionaryWithDictionary:@{
    kReporter_Event_Key: name,
    kReporter_TimestampKey: @([[NSDate date] timeIntervalSince1970])
  }];
  [eventJSON addEntriesFromDictionary:content];
  return eventJSON;
}

void XTSwizzleClassSelectorForFunction(Class cls, SEL sel, IMP newImp) __attribute__((no_sanitize("nullability-arg")))
{
  Class clscls = object_getClass((id)cls);
  Method originalMethod = class_getClassMethod(cls, sel);

  NSString *selectorName = [[NSString alloc] initWithFormat:
                            @"__%s_%s",
                            class_getName(cls),
                            sel_getName(sel)];
  SEL newSelector = sel_registerName([selectorName UTF8String]);

  class_addMethod(clscls, newSelector, newImp, method_getTypeEncoding(originalMethod));
  Method replacedMethod = class_getClassMethod(cls, newSelector);
  method_exchangeImplementations(originalMethod, replacedMethod);
}

void XTSwizzleSelectorForFunction(Class cls, SEL sel, IMP newImp)
{
  Method originalMethod = class_getInstanceMethod(cls, sel);
  const char *typeEncoding = method_getTypeEncoding(originalMethod);

  NSString *selectorName = [[NSString alloc] initWithFormat:
                            @"__%s_%s",
                            class_getName(cls),
                            sel_getName(sel)];
  SEL newSelector = sel_registerName([selectorName UTF8String]);

  class_addMethod(cls, newSelector, newImp, typeEncoding);

  Method newMethod = class_getInstanceMethod(cls, newSelector);
  if (class_addMethod(cls, sel,newImp, typeEncoding)) {
    class_replaceMethod(cls, newSelector, method_getImplementation(originalMethod), typeEncoding);
  } else {
    method_exchangeImplementations(originalMethod, newMethod);
  }
}

NSArray *TestsFromSuite(id testSuite)
{
  NSMutableArray *tests = [NSMutableArray array];
  NSMutableArray *queue = [NSMutableArray array];
  [queue addObject:testSuite];

  while ([queue count] > 0) {
    id test = [queue objectAtIndex:0];
    [queue removeObjectAtIndex:0];

    if ([test isKindOfClass:[testSuite class]] ||
        [test respondsToSelector:@selector(tests)]) {
      // Both SenTestSuite and XCTestSuite keep a list of tests in an ivar
      // called 'tests'.
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

static NSString *TestNameWithCount(NSString *name, NSUInteger count) {
  NSString *className = nil;
  NSString *methodName = nil;
  ParseClassAndMethodFromTestName(&className, &methodName, name);

  return [NSString stringWithFormat:@"-[%@ %@_%ld]",
          className,
          methodName,
          (unsigned long)count];
}

static void ProcessTestSuite(id testSuite)
{
  NSCountedSet *seenCounts = [NSCountedSet set];
  NSMutableSet *classesToSwizzle = [NSMutableSet set];

  for (id test in TestsFromSuite(testSuite)) {
    NSString *testName = [test respondsToSelector:@selector(nameForLegacyLogging)]
      ? [test nameForLegacyLogging]
      : [test description];

    [seenCounts addObject:testName];
    NSUInteger seenCount = [seenCounts countForObject:testName];

    if (seenCount > 1) {
      // It's a duplicate - we need to override the name.
      testName = TestNameWithCount(testName, seenCount);
    }
    objc_setAssociatedObject(
      test,
      &TestDescriptionKey,
      testName,
      OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );
    [classesToSwizzle addObject:[test class]];
  }

  for (Class cls in classesToSwizzle) {
    // In all versions of XCTest.framework and SenTestingKit.framework I can
    // find, the `name` method generates the actual string, and `description`
    // just calls `name`.  We override both, because we don't know which things
    // call which.
    class_replaceMethod(cls, @selector(description), (IMP)TestCase_nameOrDescription, "@@:");
    class_replaceMethod(cls, @selector(name), (IMP)TestCase_nameOrDescription, "@@:");
  }
}

static id TestProbe_specifiedTestSuite(Class cls, SEL cmd)
{
  id (*msgsend)(id, SEL) = (void *) objc_msgSend;
  NSString *selectorName = [NSString stringWithFormat:@"__%s_specifiedTestSuite", class_getName(cls)];
  id testSuite = msgsend(cls, sel_registerName(selectorName.UTF8String));
  ProcessTestSuite(testSuite);
  return testSuite;
}

static id TestSuite_allTests(Class cls, SEL cmd)
{
  id (*msgsend)(id, SEL) = (void *) objc_msgSend;
  NSString *selectorName = [NSString stringWithFormat:@"__%s_allTests", class_getName(cls)];
  id testSuite = msgsend(cls, sel_registerName(selectorName.UTF8String));
  ProcessTestSuite(testSuite);
  return testSuite;
}

void ApplyDuplicateTestNameFix(NSString *testProbeClassName, NSString *testSuiteClassName)
{
  // Hooks into `[-(Sen|XC)TestProbe specifiedTestSuite]` so we have a chance
  // to 1) scan over the entire list of tests to be run, 2) rewrite any
  // duplicate names we find, and 3) return the modified list to the caller.
  XTSwizzleClassSelectorForFunction(
    NSClassFromString(testProbeClassName),
    @selector(specifiedTestSuite),
    (IMP)TestProbe_specifiedTestSuite
  );

  // Hooks into `[-(Sen|XC)TestSuite allTests]` so we have a chance
  // to 1) scan over the entire list of tests to be run, 2) rewrite any
  // duplicate names we find, and 3) return the modified list to the caller.
  XTSwizzleClassSelectorForFunction(
    NSClassFromString(testSuiteClassName),
    @selector(allTests),
    (IMP)TestSuite_allTests
  );
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

static FILE *__stdout;
static FILE *__stderr;

static NSMutableArray *__testExceptions = nil;
static int __testSuiteDepth = 0;

static NSString *__testScope = nil;

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

#pragma mark - XCToolLog function declarations

static void XCToolLog_testSuiteDidStart(NSString *testDescription);
static void XCToolLog_testSuiteDidStop(NSString *testSuiteName, XCTestSuiteRun *testRun);
static void XCToolLog_testCaseDidStart(NSString *fullTestName);
static void XCToolLog_testCaseDidStop(NSString *fullTestName, NSNumber *unexpectedExceptionCount, NSNumber *failureCount, NSNumber *totalDuration);
static void XCToolLog_testCaseDidFail(NSDictionary *exceptionInfo);

#pragma mark - testSuiteDidStart

static void XCTestLog_testSuiteDidStart(id self, SEL sel, XCTestSuiteRun *run)
{
  XCToolLog_testSuiteDidStart(kReporter_TestSuite_TopLevelSuiteName);
}

static void XCTestLog_testSuiteWillStart(id self, SEL sel, XCTestSuite *suite)
{
  XCToolLog_testSuiteDidStart(suite.name);
}

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

#pragma mark - testSuiteDidStop
static void XCTestLog_testSuiteDidStop(id self, SEL sel, XCTestSuiteRun *run)
{
  XCToolLog_testSuiteDidStop(kReporter_TestSuite_TopLevelSuiteName, run);
}

static void XCTestLog_testSuiteDidFinish(id self, SEL sel, XCTestSuite *suite)
{
  XCToolLog_testSuiteDidStop(suite.name, (id)suite.testRun);
}

static void XCToolLog_testSuiteDidStop(NSString *testSuiteName, XCTestSuiteRun *run)
{
  __testSuiteDepth--;

  if (__testSuiteDepth > 0) {
    NSDictionary *content =
      @{
        kReporter_EndTestSuite_SuiteKey : testSuiteName,
        kReporter_EndTestSuite_TestCaseCountKey : @([run testCaseCount]),
        kReporter_EndTestSuite_TotalFailureCountKey : @([run totalFailureCount]),
        kReporter_EndTestSuite_UnexpectedExceptionCountKey : @([run unexpectedExceptionCount]),
        kReporter_EndTestSuite_TestDurationKey: @([run testDuration]),
        kReporter_EndTestSuite_TotalDurationKey : @([run totalDuration]),
      };
    NSDictionary *json = EventDictionaryWithNameAndContent(kReporter_Events_EndTestSuite, content);
    dispatch_sync(EventQueue(), ^{
      PrintJSON(json);
    });
  }
}

#pragma mark - testCaseDidStart

static void XCTestLog_testCaseDidStart(id self, SEL sel, XCTestCaseRun *run)
{
  NSString *fullTestName = [[run test] name];
  XCToolLog_testCaseDidStart(fullTestName);
}

static void XCTestLog_testCaseWillStart(id self, SEL sel, XCTestCase *testCase)
{
  id (*msgsend)(id, SEL) = (void *) objc_msgSend;
  XCTestLog_testCaseDidStart(self, sel, msgsend(testCase, @selector(testRun)));
}

static void XCToolLog_testCaseDidStart(NSString *fullTestName)
{
  dispatch_sync(EventQueue(), ^{
    NSString *className = nil;
    NSString *methodName = nil;
    ParseClassAndMethodFromTestName(&className, &methodName, fullTestName);

    PrintJSON(EventDictionaryWithNameAndContent(
      kReporter_Events_BeginTest, @{
        kReporter_BeginTest_TestKey : fullTestName,
        kReporter_BeginTest_ClassNameKey : className,
        kReporter_BeginTest_MethodNameKey : methodName,
    }));

    __testExceptions = [[NSMutableArray alloc] init];
  });
}

#pragma mark - testCaseDidStop

static void XCTestLog_testCaseDidStop(id self, SEL sel, XCTestCaseRun *run)
{
  NSString *fullTestName = [[run test] name];
  XCToolLog_testCaseDidStop(fullTestName, @([run unexpectedExceptionCount]), @([run failureCount]), @([run totalDuration]));
}

static void XCTestLog_testCaseDidFinish(id self, SEL sel, XCTestCase *testCase)
{
  id (*msgsend)(id, SEL) = (void *) objc_msgSend;
  XCTestLog_testCaseDidStop(self, sel, msgsend(testCase, @selector(testRun)));
}

static void XCToolLog_testCaseDidStop(NSString *fullTestName, NSNumber *unexpectedExceptionCount, NSNumber *failureCount, NSNumber *totalDuration)
{
  dispatch_sync(EventQueue(), ^{
    NSString *className = nil;
    NSString *methodName = nil;
    ParseClassAndMethodFromTestName(&className, &methodName, fullTestName);

    BOOL errored = [unexpectedExceptionCount integerValue] > 0;
    BOOL failed = [failureCount integerValue] > 0;
    BOOL succeeded = NO;
    NSString *result;
    if (errored) {
      result = @"error";
    } else if (failed) {
      result = @"failure";
    } else {
      result = @"success";
      succeeded = YES;
    }

    // report test results
    NSArray *retExceptions = [__testExceptions copy];
    NSDictionary *json = EventDictionaryWithNameAndContent(
      kReporter_Events_EndTest, @{
        kReporter_EndTest_TestKey : fullTestName,
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

#pragma mark - testCaseDidFail

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

static void XCToolLog_testCaseDidFail(NSDictionary *exceptionInfo)
{
  dispatch_sync(EventQueue(), ^{
    [__testExceptions addObject:exceptionInfo];
  });
}

#pragma mark - performTest

static void XCPerformTestWithSuppressedExpectedAssertionFailures(id self, SEL origSel, id arg1)
{
  void (*msgsend)(id, SEL, id) = (void *) objc_msgSend;
  int timeout = [@(getenv("OTEST_SHIM_TEST_TIMEOUT") ?: "0") intValue];

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
    NSDictionary *env = [[NSProcessInfo processInfo] environment];
    BOOL waitForDebugger = [env[@"XCTOOL_WAIT_FOR_DEBUGGER"] isEqualToString:@"YES"];
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

#pragma mark - Test Scope

static void UpdateTestScope()
{
  static NSString *const testListFileKey = @"OTEST_TESTLIST_FILE";
  static NSString *const testingFrameworkFilterTestArgsKeyKey = @"OTEST_FILTER_TEST_ARGS_KEY";

  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSString *testListFilePath = [defaults objectForKey:testListFileKey];
  NSString *testingFrameworkFilterTestArgsKey = [defaults objectForKey:testingFrameworkFilterTestArgsKeyKey];
  if (!testListFilePath && !testingFrameworkFilterTestArgsKey) {
    return;
  }
  NSCAssert(testListFilePath, @"Path to file with list of tests should be specified");
  NSCAssert(testingFrameworkFilterTestArgsKey, @"Testing framework filter test args key should be specified");

  NSError *readError = nil;
  NSString *testList = [NSString stringWithContentsOfFile:testListFilePath encoding:NSUTF8StringEncoding error:&readError];
  NSCAssert(testList, @"Failed to read file at path %@ with error %@", testListFilePath, readError);
  [defaults setValue:testList forKey:testingFrameworkFilterTestArgsKey];

  __testScope = testList;
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
    NSDictionary<NSString *, NSString *> *frameworkInfo = XCTestFrameworkInfo();
    ApplyDuplicateTestNameFix(
      frameworkInfo[kTestingFrameworkTestProbeClassName],
      frameworkInfo[kTestingFrameworkTestSuiteClassName]
    );
  });
}

/**
 Crawls through the test suite hierarchy and returns a list of all test case
 names in the format of ...

 @[@"-[SomeClass someMethod]",
 @"-[SomeClass otherMethod]"]
 */
static NSArray<NSString *> *testNamesFromSuite(id testSuite)
{
  NSMutableArray *names = [NSMutableArray array];

  for (id test in TestsFromSuite(testSuite)) {
    NSString *name = [test performSelector:@selector(description)];
    NSCAssert(name != nil, @"Can't get name for test: %@", test);
    [names addObject:name];
  }

  return names;
}

static void queryTestBundlePath(NSString *testBundlePath)
{
  NSString *outputFile = NSProcessInfo.processInfo.environment[@"OTEST_QUERY_OUTPUT_FILE"];
  NSCAssert(outputFile, @"Output path wasn't set in the enviroment: %@", NSProcessInfo.processInfo.environment);
  NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:outputFile];

  NSBundle *bundle = [NSBundle bundleWithPath:testBundlePath];
  if (!bundle) {
    fprintf(
      stderr,
      "Bundle '%s' does not identify an accessible bundle directory.\n",
      testBundlePath.UTF8String
    );
    exit(kBundleOpenError);
  }

  NSDictionary<NSString *, id> *framework = XCTestFrameworkInfo();
  if (!framework) {
    const char *bundleExtension = testBundlePath.pathExtension.UTF8String;
    fprintf(stderr, "The bundle extension '%s' is not supported.\n", bundleExtension);
    exit(kUnsupportedFramework);
  }

  if (![bundle executablePath]) {
    fprintf(stderr, "The bundle at %s does not contain an executable.\n", [testBundlePath UTF8String]);
    exit(kMissingExecutable);
  }

  // Make sure the 'SenTest' or 'XCTest' preference is cleared before we load the
  // test bundle - otherwise otest-query will accidentally start running tests.
  //
  // Instead of seeing the JSON list of test methods, you'll see output like ...
  //
  //   Test Suite 'All tests' started at 2013-11-07 23:47:46 +0000
  //   Test Suite 'All tests' finished at 2013-11-07 23:47:46 +0000.
  //   Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.001) seconds
  //
  // Here's what happens -- As soon as we dlopen() the test bundle, it will also
  // trigger the linker to load SenTestingKit.framework or XCTest.framework since
  // those are linked by the test bundle.  And, as soon as the testing framework
  // loads, the class initializer '+[SenTestSuite initialize]' is triggered.  If
  // the initializer sees that the 'SenTest' preference is set, it goes ahead
  // and runs tests.
  //
  // By clearing the preference, we can prevent tests from running.
  [NSUserDefaults.standardUserDefaults removeObjectForKey:framework[kTestingFrameworkFilterTestArgsKey]];
  [NSUserDefaults.standardUserDefaults synchronize];

  // We use dlopen() instead of -[NSBundle loadAndReturnError] because, if
  // something goes wrong, dlerror() gives us a much more helpful error message.
  if (dlopen([[bundle executablePath] UTF8String], RTLD_LAZY) == NULL) {
    fprintf(stderr, "%s\n", dlerror());
    exit(kDLOpenError);
  }

  [NSBundle.allFrameworks makeObjectsPerformSelector:@selector(principalClass)];

  ApplyDuplicateTestNameFix(
    framework[kTestingFrameworkTestProbeClassName],
    framework[kTestingFrameworkTestSuiteClassName]
  );

  Class testSuiteClass = NSClassFromString(framework[kTestingFrameworkTestSuiteClassName]);
  NSCAssert(testSuiteClass, @"Should have *TestSuite class");

  // By setting `-(XC|Sen)Test None`, we'll make `-[(XC|Sen)TestSuite allTests]`
  // return all tests.
  [NSUserDefaults.standardUserDefaults setObject:@"None" forKey:framework[kTestingFrameworkFilterTestArgsKey]];
  id allTestsSuite = [testSuiteClass performSelector:@selector(allTests)];
  NSCAssert(allTestsSuite, @"Should have gotten a test suite from allTests");

  NSArray<NSString *> *fullTestNames = [testNamesFromSuite(allTestsSuite) sortedArrayUsingSelector:@selector(compare:)];
  for (NSUInteger index = 0; index < fullTestNames.count; index++) {
    NSString *fullTestName = fullTestNames[index];
    NSString *className = nil;
    NSString *methodName = nil;
    ParseClassAndMethodFromTestName(&className, &methodName, fullTestName);
    NSString *line = index == 0
      ? [NSString stringWithFormat:@"%@/%@", className, methodName]
      : [NSString stringWithFormat:@"\n%@/%@", className, methodName];
    NSData *output = [line dataUsingEncoding:NSUTF8StringEncoding];
    [fileHandle writeData:output];
  }
  // Close the file so the other end knows this is the end of the input.
  [fileHandle closeFile];
  exit(kSuccess);
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
  const char *stdoutFileKey = "OTEST_SHIM_STDOUT_FILE";
  FILE *shimStdoutFile = fopen(getenv(stdoutFileKey), "w");
  if (shimStdoutFile) {
    __stdout = shimStdoutFile;
  } else {
    int stdoutHandle = dup(STDOUT_FILENO);
    __stdout = fdopen(stdoutHandle, "w");
  }
  setvbuf(__stdout, NULL, _IONBF, 0);

  const char *stderrFileKey = "OTEST_SHIM_STDERR_FILE";
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

__attribute__((constructor)) static void EntryPoint()
{
  // Unset so we don't cascade into any other process that might be spawned.
  unsetenv("DYLD_INSERT_LIBRARIES");

  NSString *bundleQueryPath = NSProcessInfo.processInfo.environment[@"OtestQueryBundlePath"];
  if (bundleQueryPath) {
    assignOutputFiles();
    queryTestBundlePath(bundleQueryPath);
    return;
  }
  NSString *bundleRunPath = NSProcessInfo.processInfo.environment[@"TEST_SHIM_BUNDLE_PATH"];
  if (bundleRunPath) {
    assignOutputFiles();
    UpdateTestScope();

    struct sigaction sa_abort;
    sa_abort.sa_handler = &handle_signal;
    sigaction(SIGABRT, &sa_abort, NULL);

    // Let's register to get notified when libraries are initialized
    XTSwizzleSelectorForFunction([NSBundle class], @selector(loadAndReturnError:), (IMP)NSBundle_loadAndReturnError);

    // Then Swizzle
    SwizzleXCTestMethodsIfAvailable();
    return;
  }
}

__attribute__((destructor)) static void ExitPoint()
{
  PrintNewlineAndCloseFDs();
}

#pragma clang diagnostic pop
