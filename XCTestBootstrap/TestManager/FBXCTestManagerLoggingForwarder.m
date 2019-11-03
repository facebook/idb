/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBXCTestManagerLoggingForwarder.h"

#import <XCTest/XCTestManager_IDEInterface-Protocol.h>

#import <FBControlCore/FBControlCore.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wprotocol"
#pragma clang diagnostic ignored "-Wincomplete-implementation"

@interface FBXCTestManagerLoggingForwarder() <XCTestManager_IDEInterface>

@end

@implementation FBXCTestManagerLoggingForwarder

#pragma mark Initializers

+ (instancetype)withIDEInterface:(id<XCTestManager_IDEInterface, NSObject>)interface logger:(id<FBControlCoreLogger>)logger
{
  return [[FBXCTestManagerLoggingForwarder alloc] initWithIDEInterface:interface logger:logger];
}

- (instancetype)initWithIDEInterface:(id<XCTestManager_IDEInterface, NSObject>)interface logger:(id<FBControlCoreLogger>)logger
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _interface = interface;
  _logger = logger;

  return self;
}

#pragma mark Default Implementations

- (id)_XCT_testSuite:(NSString *)arg1 didStartAt:(NSString *)arg2
{
  [self.logger logFormat:@"Test Suite %@ started", arg1];
  return [self.interface _XCT_testSuite:arg1 didStartAt:arg2];
}

- (id)_XCT_testSuite:(NSString *)arg1 didFinishAt:(NSString *)arg2 runCount:(NSNumber *)arg3 withFailures:(NSNumber *)arg4 unexpected:(NSNumber *)arg5 testDuration:(NSNumber *)arg6 totalDuration:(NSNumber *)arg7
{
  [self.logger logFormat:@"Test Suite Did Finish %@", arg1];
  return [self.interface _XCT_testSuite:arg1 didFinishAt:arg2 runCount:arg3 withFailures:arg4 unexpected:arg5 testDuration:arg6 totalDuration:arg7];
}

- (id)_XCT_testCaseDidStartForTestClass:(NSString *)arg1 method:(NSString *)arg2
{
  [self.logger logFormat:@"Test Case %@/%@ did start", arg1, arg2];
  return [self.interface _XCT_testCaseDidStartForTestClass:arg1 method:arg2];
}

- (id)_XCT_testCaseDidFinishForTestClass:(NSString *)arg1 method:(NSString *)arg2 withStatus:(NSString *)arg3 duration:(NSNumber *)arg4
{
  [self.logger logFormat:@"Test Case %@/%@ did finish (%@)", arg1, arg2, arg3];
  return [self.interface _XCT_testCaseDidFinishForTestClass:arg1 method:arg2 withStatus:arg3 duration:arg4];
}

- (id)_XCT_testCaseDidFailForTestClass:(NSString *)arg1 method:(NSString *)arg2 withMessage:(NSString *)arg3 file:(NSString *)arg4 line:(NSNumber *)arg5
{
  [self.logger logFormat:@"Test Case %@/%@ did fail: %@", arg1, arg2, arg3];
  return [self.interface _XCT_testCaseDidFailForTestClass:arg1 method:arg2 withMessage:arg3 file:arg4 line:arg5];
}

- (id)_XCT_logDebugMessage:(NSString *)arg1
{
  [self.logger log:[arg1 stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]];
  return [self.interface _XCT_logDebugMessage:arg1];
}

#pragma mark Forwarding Un-implemented selectors.

- (BOOL)respondsToSelector:(SEL)selector
{
  return [super respondsToSelector:selector] || [self.interface respondsToSelector:selector];
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)selector
{
  return [super methodSignatureForSelector:selector] ?: [(id)self.interface methodSignatureForSelector:selector];
}

- (void)forwardInvocation:(NSInvocation *)invocation
{
  if ([self.interface respondsToSelector:invocation.selector]) {
    [self.logger.debug log:NSStringFromSelector(invocation.selector)];
    [invocation invokeWithTarget:self.interface];
  } else {
    [super forwardInvocation:invocation];
  }
}

@end

#pragma clang diagnostic pop
