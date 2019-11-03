/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBTestDaemonResult.h"

#import "XCTestBootstrapError.h"

@interface FBTestDaemonResult_Success : FBTestDaemonResult

@end

@implementation FBTestDaemonResult_Success

- (BOOL)didEndSuccessfully
{
  return YES;
}

- (NSError *)error
{
  return nil;
}

- (NSString *)description
{
  return @"Daemon Connection ended normally";
}

@end

@interface FBTestDaemonResult_ClientRequestedDisconnect : FBTestDaemonResult
@end

@implementation FBTestDaemonResult_ClientRequestedDisconnect

- (BOOL)didEndSuccessfully
{
  return YES;
}

- (NSError *)error
{
  return nil;
}

- (FBCrashLogInfo *)crash
{
  return nil;
}

- (NSString *)description
{
  return @"Daemon Connection ended when client requested disconnect";
}

@end

@interface FBTestDaemonResult_EndedInError : FBTestDaemonResult
@property (nonatomic, strong, readonly) XCTestBootstrapError *underlyingError;
@end

@implementation FBTestDaemonResult_EndedInError

- (instancetype)initWithError:(XCTestBootstrapError *)error
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _underlyingError = error;

  return self;
}

- (BOOL)didEndSuccessfully
{
  return NO;
}

- (NSError *)error
{
  return [self.underlyingError build];
}

@end

@implementation FBTestDaemonResult

#pragma mark Constructors

+ (instancetype)success
{
  return [FBTestDaemonResult_Success new];
}

+ (instancetype)clientRequestedDisconnect
{
  return [FBTestDaemonResult_ClientRequestedDisconnect new];
}

+ (instancetype)failedInError:(XCTestBootstrapError *)error
{
  return [[FBTestDaemonResult_EndedInError alloc] initWithError:error];
}

#pragma mark Public Methods

- (BOOL)didEndSuccessfully
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return NO;
}

- (NSError *)error
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

@end
