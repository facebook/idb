/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>
#import <XCTestBootstrap/FBXCTestReporter.h>

@protocol FBDataConsumer;
@protocol FBControlCoreLogger;

/**
 A Reporter using xctool's linewise-json output.
 */
@interface FBJSONTestReporter : NSObject <FBXCTestReporter>

/**
 The Designated Initializer.

 @param testBundlePath the Test Bundle to Report for.
 @param testType the Test Type to Report for
 @param logger the logger to log out-of-band information to.
 @param dataConsumer the consumer of the output.
 */
- (nonnull instancetype)initWithTestBundlePath:(nonnull NSString *)testBundlePath testType:(nonnull NSString *)testType logger:(nullable id<FBControlCoreLogger>)logger dataConsumer:(nonnull id<FBDataConsumer>)dataConsumer;

@end
