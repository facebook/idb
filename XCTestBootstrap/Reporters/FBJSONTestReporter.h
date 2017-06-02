/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

#import <XCTestBootstrap/FBXCTestReporter.h>

NS_ASSUME_NONNULL_BEGIN

@protocol FBFileConsumer;
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
 @param fileConsumer the consumer of the output.
 */
- (instancetype)initWithTestBundlePath:(NSString *)testBundlePath testType:(NSString *)testType logger:(nullable id<FBControlCoreLogger>)logger fileConsumer:(id<FBFileConsumer>)fileConsumer;

@end

NS_ASSUME_NONNULL_END
