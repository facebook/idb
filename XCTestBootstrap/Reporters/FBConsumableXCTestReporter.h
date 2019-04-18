/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <XCTestBootstrap/FBXCTestReporter.h>

NS_ASSUME_NONNULL_BEGIN

/**
 Information about a single test failure.
 */
@interface FBTestRunFailureInfo : NSObject

/**
 The failure message.
 */
@property (nonatomic, copy, readonly) NSString *message;

/**
 The file that the test failed on.
 */
@property (nonatomic, copy, readonly, nullable) NSString *file;

/**
 The line number of the file that the test failed on.
 */
@property (nonatomic, assign, readonly) NSUInteger line;

@end

/**
 Activity reporting
 */
@interface FBTestRunTestActivity : NSObject

/**
 The title of the activity.
 */
@property (nonatomic, copy, readonly) NSString *title;

/**
 The duration of the activity.
 */
@property (nonatomic, assign, readonly) NSTimeInterval duration;

/**
 The UUID of the activity.
 */
@property (nonatomic, copy, readonly) NSString *uuid;

@end

/**
 A incremental update of test run info.
 */
@interface FBTestRunUpdate : NSObject

/**
 The bundle name of the test.
 */
@property (nonatomic, copy, readonly, nullable) NSString *bundleName;

/**
 The class name of the test.
 */
@property (nonatomic, copy, readonly, nullable) NSString *className;

/**
 The method name of the test.
 */
@property (nonatomic, copy, readonly, nullable) NSString *methodName;

/**
 The logs associated with the test.
 */
@property (nonatomic, copy, readonly) NSArray<NSString *> *logs;

/**
 The duration of the test
 */
@property (nonatomic, assign, readonly) NSTimeInterval duration;

/**
 YES if passed, NO otherwise
 */
@property (nonatomic, assign, readonly) BOOL passed;

/**
 The failure info, if failed
 */
@property (nonatomic, strong, nullable, readonly) FBTestRunFailureInfo *failureInfo;

/**
 The activity logs, if relevant
 */
@property (nonatomic, copy, nullable, readonly) NSArray<FBTestRunTestActivity *> *activityLogs;

/**
 YES if the test crashed, NO otherwise.
 */
@property (nonatomic, assign, readonly) BOOL crashed;

@end

/**
 Collects test results and exposes them as values that can be incrementally consumed.
 */
@interface FBConsumableXCTestReporter : NSObject <FBXCTestReporter>

#pragma mark Public Methods

/**
 Consumes the last set of test run info items.

 @return an array of the new results
 */
- (NSArray<FBTestRunUpdate *> *)consumeCurrentResults;

@end

NS_ASSUME_NONNULL_END
