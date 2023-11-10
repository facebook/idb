/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

struct __va_list_tag {
  unsigned int _field1;
  unsigned int _field2;
  void *_field3;
  void *_field4;
};

@interface XCTestObserver : NSObject
{
}

+ (void)initialize;
+ (void)suspendObservation;
+ (void)resumeObservation;
+ (void)tearDownTestObservers;
+ (void)setUpTestObservers;
+ (void)removeTestObserverClass:(Class)arg1;
+ (void)addTestObserverClass:(Class)arg1;
- (void)testCaseDidFail:(id)arg1 withDescription:(id)arg2 inFile:(id)arg3 atLine:(NSUInteger)arg4;
- (void)testCaseDidStop:(id)arg1;
- (void)testCaseDidStart:(id)arg1;
- (void)testSuiteDidStop:(id)arg1;
- (void)testSuiteDidStart:(id)arg1;
- (void)_testCaseDidFail:(id)arg1;
- (void)_testCaseDidStop:(id)arg1;
- (void)_testCaseDidStart:(id)arg1;
- (void)_testSuiteDidStop:(id)arg1;
- (void)_testSuiteDidStart:(id)arg1;
- (void)stopObserving;
- (void)startObserving;

@end

@class XCTestRun;

@interface XCTest : NSObject
{
}

- (id)run;
- (void)tearDown;
- (void)setUp;
- (void)performTest:(id)arg1;
- (id)name;
- (XCTestRun *)testRun;
- (Class)testRunClass;
- (NSUInteger)testCaseCount;
- (BOOL)isEmpty;
- (void)removeTestsWithNames:(id)arg1;

@end

@interface XCTestRun : NSObject
{
  double startDate;
  double stopDate;
  XCTest *test;
}

+ (id)testRunWithTest:(id)arg1;
- (id)description;
- (BOOL)hasSucceeded;
- (NSUInteger)testCaseCount;
- (NSInteger)executionCount;
- (NSUInteger)unexpectedExceptionCount;
- (NSUInteger)failureCount;
- (NSUInteger)totalFailureCount;
- (void)stop;
- (void)start;
- (id)stopDate;
- (id)startDate;
- (double)testDuration;
- (double)totalDuration;
- (id)test;
- (void)dealloc;
- (instancetype)initWithTest:(id)arg1;

@end

@interface XCTestCaseRun : XCTestRun
{
  NSUInteger failureCount;
  NSUInteger unexpectedExceptionCount;
}

- (void)recordFailureInTest:(id)arg1 withDescription:(id)arg2 inFile:(id)arg3 atLine:(NSUInteger)arg4 expected:(BOOL)arg5;
- (NSUInteger)unexpectedExceptionCount;
- (NSUInteger)failureCount;
- (NSString *)nameForLegacyLogging;
- (void)stop;
- (void)start;

@end

@interface XCTestSuite : XCTest
{
  NSString *name;
  NSMutableArray *tests;
}

+ (id)defaultTestSuite;
+ (id)allTests;
+ (id)structuredTests;
+ (id)testSuiteForTestCaseClass:(Class)arg1;
+ (id)testSuiteForTestCaseWithName:(id)arg1;
+ (id)testSuiteForBundlePath:(id)arg1;
+ (id)suiteForBundleCache;
+ (void)invalidateCache;
+ (id)_suiteForBundleCache;
+ (id)emptyTestSuiteNamedFromPath:(id)arg1;
+ (id)testSuiteWithName:(id)arg1;
- (void)performTest:(id)arg1;
- (Class)testRunClass;
- (NSUInteger)testCaseCount;
- (id)tests;
- (void)addTestsEnumeratedBy:(id)arg1;
- (void)addTest:(id)arg1;
- (id)description;
- (id)name;
- (void)dealloc;
- (instancetype)initWithName:(id)arg1;
- (void)removeTestsWithNames:(id)arg1;
- (void)setName:(id)arg1;

@end

@interface XCTestCaseSuite : XCTestSuite
{
    Class testCaseClass;
}

+ (id)emptyTestSuiteForTestCaseClass:(Class)arg1;
- (void)tearDown;
- (void)setUp;
- (instancetype)initWithTestCaseClass:(Class)arg1;

@end

@interface XCTestCase : XCTest
{
    NSInvocation *_invocation;
    XCTestCaseRun *_testCaseRun;
    BOOL _continueAfterFailure;
}

+ (id)testInvocations;
+ (BOOL)isInheritingTestCases;
+ (id)testCaseWithSelector:(SEL)arg1;
+ (id)testCaseWithInvocation:(id)arg1;
+ (void)tearDown;
+ (void)setUp;
+ (id)defaultTestSuite;
+ (id)xct_allTestMethodInvocations;
+ (id)xct_testMethodInvocations;
+ (id)xct_allSubclasses;
@property (atomic, assign) BOOL continueAfterFailure; // @synthesize continueAfterFailure=_continueAfterFailure;
@property (atomic, retain) XCTestCaseRun *testCaseRun;
- (NSUInteger)numberOfTestIterationsForTestWithSelector:(SEL)arg1;
- (void)afterTestIteration:(NSUInteger)arg1 selector:(SEL)arg2;
- (void)beforeTestIteration:(NSUInteger)arg1 selector:(SEL)arg2;
- (void)tearDownTestWithSelector:(SEL)arg1;
- (void)setUpTestWithSelector:(SEL)arg1;
- (void)performTest:(id)arg1;
- (void)invokeTest;
- (Class)testRunClass;
- (void)_recordUnexpectedFailureWithDescription:(id)arg1 exception:(id)arg2;
- (void)recordFailureWithDescription:(id)arg1 inFile:(id)arg2 atLine:(NSUInteger)arg3 expected:(BOOL)arg4;
- (void)setInvocation:(id)arg1;
- (id)invocation;
- (NSString *)languageAgnosticTestMethodName;
- (void)dealloc;
- (id)description;
- (id)name;
- (NSUInteger)testCaseCount;
- (SEL)selector;
- (instancetype)initWithSelector:(SEL)arg1;
- (instancetype)initWithInvocation:(id)arg1;
- (instancetype)init;
- (id)_xctTestIdentifier;

@end

@interface XCTTestIdentifier : NSObject <NSCopying, NSSecureCoding>
{
}

+ (_Bool)supportsSecureCoding;
+ (id)allocWithZone:(struct _NSZone *)arg1;
+ (id)bundleIdentifier;
+ (id)identifierForClass:(Class)arg1;
+ (id)leafIdentifierWithComponents:(id)arg1;
+ (id)containerIdentifierWithComponents:(id)arg1;
+ (id)containerIdentifierWithComponent:(id)arg1;
- (Class)classForCoder;
- (void)encodeWithCoder:(id)arg1;
- (id)initWithCoder:(id)arg1;
@property(readonly) unsigned long long options;
- (id)componentAtIndex:(unsigned long long)arg1;
@property(readonly) unsigned long long componentCount;
@property(readonly) NSArray *components;
- (id)initWithComponents:(id)arg1 options:(unsigned long long)arg2;
- (id)initWithStringRepresentation:(id)arg1 preserveModulePrefix:(_Bool)arg2;
- (id)initWithStringRepresentation:(id)arg1;
- (id)initWithClassName:(id)arg1;
- (id)initWithClassName:(id)arg1 methodName:(id)arg2;
- (id)initWithClassAndMethodComponents:(id)arg1;
- (id)initWithComponents:(id)arg1 isContainer:(_Bool)arg2;
- (id)copyWithZone:(struct _NSZone *)arg1;
@property(readonly) XCTTestIdentifier *swiftMethodCounterpart;
@property(readonly) XCTTestIdentifier *firstComponentIdentifier;
@property(readonly) XCTTestIdentifier *parentIdentifier;
- (id)_identifierString;
@property(readonly) NSString *identifierString;
@property(readonly) NSString *displayName;
@property(readonly) NSString *lastComponentDisplayName;
@property(readonly) NSString *lastComponent;
@property(readonly) NSString *firstComponent;
@property(readonly) _Bool representsBundle;
@property(readonly) _Bool isLeaf;
@property(readonly) _Bool isContainer;
- (unsigned long long)hash;
- (_Bool)isEqual:(id)arg1;
- (id)debugDescription;
- (id)description;
@property(readonly) _Bool isSwiftMethod;
@property(readonly) _Bool usesClassAndMethodSemantics;

@end

@interface XCTestLog : XCTestObserver
{
}

- (void)testCaseDidFail:(id)arg1 withDescription:(id)arg2 inFile:(id)arg3 atLine:(NSUInteger)arg4;
- (void)testSuiteDidStop:(id)arg1;
- (void)testSuiteDidStart:(id)arg1;
- (void)testCaseDidStop:(id)arg1;
- (void)testCaseDidStart:(id)arg1;
- (void)testLogWithFormat:(id)arg1 arguments:(struct __va_list_tag [1])arg2;
- (void)testLogWithFormat:(id)arg1;
- (id)logFileHandle;

@end

@interface XCTestSuiteRun : XCTestRun
{
    NSMutableArray *runs;
}

- (double)testDuration;
- (NSUInteger)unexpectedExceptionCount;
- (NSUInteger)failureCount;
- (void)addTestRun:(id)arg1;
- (id)testRuns;
- (void)stop;
- (void)start;
- (void)dealloc;
- (instancetype)initWithTest:(id)arg1;

@end

@interface XCTestProbe : NSObject
{
}

+ (void)load;
+ (void)initialize;
+ (void)_applicationFinishedLaunching:(id)arg1;
+ (void)runTests:(id)arg1;
+ (void)resumeAppSleep:(id)arg1;
+ (id)suspendAppSleep;
+ (void)runTestsAtUnitPath:(id)arg1 scope:(id)arg2;
+ (id)specifiedTestSuite;
+ (id)multiTestSuiteForScope:(id)arg1 inverse:(BOOL)arg2;
+ (id)testCaseNamesForScopeNames:(id)arg1;
+ (id)testedBundlePath;
+ (BOOL)isTesting;
+ (BOOL)isInverseTestScope;
+ (id)testScope;
+ (BOOL)isLoadedFromTool;
+ (BOOL)isProcessActingAsTestRig;
+ (BOOL)isLoadedFromApplication;

@end

@interface NSFileManager (XCTestAdditions)
- (BOOL)xct_fileExistsAtPathOrLink:(id)arg1;
@end

@interface NSValue (XCTestAdditions)
- (id)xct_contentDescription;
@end

@interface XCTestConfiguration : NSObject <NSSecureCoding>
{
  NSURL *_testBundleURL;
  NSString *_testBundleRelativePath;
  id _testsToSkip;
  id _testsToRun;
  BOOL _reportResultsToIDE;
  NSUUID *_sessionIdentifier;
  NSString *_pathToXcodeReportingSocket;
  BOOL _disablePerformanceMetrics;
  BOOL _treatMissingBaselinesAsFailures;
  NSURL *_baselineFileURL;
  NSString *_baselineFileRelativePath;
  NSString *_targetApplicationPath;
  NSString *_targetApplicationBundleID;
  NSString *_productModuleName;
  BOOL _reportActivities;
  BOOL _testsMustRunOnMainThread;
  BOOL _initializeForUITesting;
  NSArray *_targetApplicationArguments;
  NSDictionary *_targetApplicationEnvironment;
  NSDictionary *_aggregateStatisticsBeforeCrash;
  NSString *_automationFrameworkPath;
  BOOL _emitOSLogs;
}
@property BOOL emitOSLogs; // @synthesize emitOSLogs=_emitOSLogs;
@property(copy) NSString *automationFrameworkPath; // @synthesize automationFrameworkPath=_automationFrameworkPath;
@property(copy) NSDictionary *aggregateStatisticsBeforeCrash; // @synthesize aggregateStatisticsBeforeCrash=_aggregateStatisticsBeforeCrash;
@property(copy) NSArray *targetApplicationArguments; // @synthesize targetApplicationArguments=_targetApplicationArguments;
@property(copy) NSDictionary *targetApplicationEnvironment; // @synthesize targetApplicationEnvironment=_targetApplicationEnvironment;
@property BOOL initializeForUITesting; // @synthesize initializeForUITesting=_initializeForUITesting;
@property BOOL testsMustRunOnMainThread; // @synthesize testsMustRunOnMainThread=_testsMustRunOnMainThread;
@property BOOL reportActivities; // @synthesize reportActivities=_reportActivities;
@property(copy) NSString *productModuleName; // @synthesize productModuleName=_productModuleName;
@property(copy) NSString *targetApplicationBundleID; // @synthesize targetApplicationBundleID=_targetApplicationBundleID;
@property(copy) NSString *targetApplicationPath; // @synthesize targetApplicationPath=_targetApplicationPath;
@property BOOL treatMissingBaselinesAsFailures; // @synthesize treatMissingBaselinesAsFailures=_treatMissingBaselinesAsFailures;
@property BOOL disablePerformanceMetrics; // @synthesize disablePerformanceMetrics=_disablePerformanceMetrics;
@property BOOL reportResultsToIDE; // @synthesize reportResultsToIDE=_reportResultsToIDE;
@property(copy, nonatomic) NSURL *baselineFileURL; // @synthesize baselineFileURL=_baselineFileURL;
@property(copy) NSString *baselineFileRelativePath; // @synthesize baselineFileRelativePath=_baselineFileRelativePath;
@property(copy) NSString *pathToXcodeReportingSocket; // @synthesize pathToXcodeReportingSocket=_pathToXcodeReportingSocket;
@property(copy) NSUUID *sessionIdentifier; // @synthesize sessionIdentifier=_sessionIdentifier;
@property(copy) id testsToSkip; // @synthesize testsToSkip=_testsToSkip;
@property(copy) id testsToRun; // @synthesize testsToRun=_testsToRun;
@property(copy, nonatomic) NSURL *testBundleURL; // @synthesize testBundleURL=_testBundleURL;
@property(copy) NSString *testBundleRelativePath; // @synthesize testBundleRelativePath=_testBundleRelativePath;

// `absolutePath` has been replaced by `basePathForTestBundleResolution` on XCode 13.0. We don't use either.
// @property(copy) NSString *absolutePath; // @synthesize absolutePath=_absolutePath;
// @property (copy,nonatomic) NSString *basePathForTestBundleResolution;

+ (id)configurationWithContentsOfFile:(id)arg1;
+ (id)activeTestConfiguration;
+ (void)setActiveTestConfiguration:(id)arg1;

- (BOOL)writeToFile:(id)arg1;
- (instancetype)init;

@end

@interface NSKeyedUnarchiver (XCTestAdditions)
+ (XCTestConfiguration *)xct_unarchivedObjectOfClass:(Class)aClass fromData:(NSData *)data;
@end
