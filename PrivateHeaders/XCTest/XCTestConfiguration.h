/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

@class NSSet, NSString, NSURL, NSUUID;

@interface XCTestConfiguration : NSObject <NSSecureCoding>
{
    NSURL *_testBundleURL;
    NSSet *_testsToSkip;
    NSSet *_testsToRun;
    BOOL _reportResultsToIDE;
    NSUUID *_sessionIdentifier;
    BOOL _disablePerformanceMetrics;
    BOOL _treatMissingBaselinesAsFailures;
    NSURL *_baselineFileURL;
    NSString *_targetApplicationPath;
    NSString *_targetApplicationBundleID;
    NSString *_productModuleName;
    NSString *_automationFrameworkPath;
    BOOL _reportActivities;
    BOOL _testsMustRunOnMainThread;

    // iOS 10.x specific
    NSDictionary *_aggregateStatisticsBeforeCrash;
    NSString *_testBundleRelativePath;
    NSString *_absolutePath;
    NSString *_baselineFileRelativePath;
    BOOL _initializeForUITesting;
}
@property BOOL testsMustRunOnMainThread; // @synthesize testsMustRunOnMainThread=_testsMustRunOnMainThread;
@property BOOL reportActivities; // @synthesize reportActivities=_reportActivities;
@property(copy) NSString *productModuleName; // @synthesize productModuleName=_productModuleName;
@property(copy) NSString *targetApplicationBundleID; // @synthesize targetApplicationBundleID=_targetApplicationBundleID;
@property(copy) NSString *targetApplicationPath; // @synthesize targetApplicationPath=_targetApplicationPath;
@property(copy) NSString *automationFrameworkPath; // @synthesize automationFrameworkPath=_automationFrameworkPath;
@property BOOL treatMissingBaselinesAsFailures; // @synthesize treatMissingBaselinesAsFailures=_treatMissingBaselinesAsFailures;
@property BOOL disablePerformanceMetrics; // @synthesize disablePerformanceMetrics=_disablePerformanceMetrics;
@property BOOL reportResultsToIDE; // @synthesize reportResultsToIDE=_reportResultsToIDE;
@property(copy) NSURL *baselineFileURL; // @synthesize baselineFileURL=_baselineFileURL;
@property(copy) NSUUID *sessionIdentifier; // @synthesize sessionIdentifier=_sessionIdentifier;
@property(copy) NSSet *testsToSkip; // @synthesize testsToSkip=_testsToSkip;
@property(copy) NSSet *testsToRun; // @synthesize testsToRun=_testsToRun;
@property(copy) NSURL *testBundleURL; // @synthesize testBundleURL=_testBundleURL;

// iOS 10.x specific
@property(copy) NSDictionary *aggregateStatisticsBeforeCrash; // @synthesize aggregateStatisticsBeforeCrash=_aggregateStatisticsBeforeCrash;
@property(copy) NSString *baselineFileRelativePath; // @synthesize baselineFileRelativePath=_baselineFileRelativePath;
@property(copy) NSString *testBundleRelativePath; // @synthesize testBundleRelativePath=_testBundleRelativePath;
@property(copy) NSString *absolutePath; // @synthesize absolutePath=_absolutePath;
@property BOOL initializeForUITesting; // @synthesize initializeForUITesting=_initializeForUITesting;

+ (id)configurationWithContentsOfFile:(id)arg1;
+ (id)activeTestConfiguration;
+ (void)setActiveTestConfiguration:(id)arg1;
- (id)init;
- (BOOL)writeToFile:(id)arg1;

@end
