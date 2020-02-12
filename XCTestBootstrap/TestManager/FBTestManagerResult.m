/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBTestManagerResult.h"

#import "XCTestBootstrapError.h"
#import "FBTestBundleResult.h"
#import "FBTestDaemonResult.h"

@interface FBTestManagerResult_Success : FBTestManagerResult
@end

@implementation FBTestManagerResult_Success

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
  return @"Finished Normally";
}

@end

@interface FBTestManagerResult_ClientRequestedDisconnect : FBTestManagerResult
@end

@implementation FBTestManagerResult_ClientRequestedDisconnect

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
  return @"Finished on Client Disconnect Request";
}

@end

@interface FBTestManagerResult_Timeout : FBTestManagerResult
@property (nonatomic, assign, readonly) NSTimeInterval timeout;
@end

@implementation FBTestManagerResult_Timeout

- (instancetype)initWithTimeout:(NSTimeInterval)timeout
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _timeout = timeout;

  return self;
}

- (BOOL)didEndSuccessfully
{
  return NO;
}

- (id)error
{
  return [[XCTestBootstrapError
    describeFormat:@"The Test Timed out in %f seconds", self.timeout]
    build];
}

- (FBCrashLogInfo *)crash
{
  return nil;
}

- (NSString *)description
{
  return [NSString stringWithFormat:@"Timed out after %f seconds", self.timeout];
}

@end

@interface FBTestManagerResult_TestHostCrashed : FBTestManagerResult

@property (nonatomic, strong, readonly) FBCrashLog *underlyingCrash;

@end

@implementation FBTestManagerResult_TestHostCrashed

- (instancetype)initWithCrashDiagnostic:(FBCrashLog *)crash
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _underlyingCrash = crash;

  return self;
}

- (BOOL)didEndSuccessfully
{
  return NO;
}

- (NSError *)error
{
  return [[XCTestBootstrapError
    describeFormat:@"The Test Host Crashed: %@", self.underlyingCrash]
    build];
}

- (FBCrashLog *)crash
{
  return self.underlyingCrash;
}

- (NSString *)description
{
  return @"The Test Host Process crashed";
}

@end

@interface FBTestManagerResult_InternalError : FBTestManagerResult
@property (nonatomic, strong, readonly) NSError *underlyingError;
@end

@implementation FBTestManagerResult_InternalError

- (instancetype)initWithError:(NSError *)error
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
  return self.underlyingError;
}

- (FBCrashLogInfo *)crash
{
  return nil;
}

- (NSString *)description
{
  return [NSString stringWithFormat:@"Internal Error %@", self.underlyingError];
}

@end

@implementation FBTestManagerResult

#pragma mark Constructors

+ (instancetype)success
{
  return [FBTestManagerResult_Success new];
}

+ (instancetype)clientRequestedDisconnect
{
  return [FBTestManagerResult_ClientRequestedDisconnect new];
}

+ (instancetype)timedOutAfter:(NSTimeInterval)timeout
{
  return [[FBTestManagerResult_Timeout alloc] initWithTimeout:timeout];
}

+ (instancetype)bundleConnectionFailed:(FBTestBundleResult *)bundleResult
{
  NSParameterAssert(bundleResult.didEndSuccessfully == NO);
  if (bundleResult.crash) {
    return [[FBTestManagerResult_TestHostCrashed alloc] initWithCrashDiagnostic:bundleResult.crash];
  }
  NSParameterAssert(bundleResult.error);
  return [[FBTestManagerResult_InternalError alloc] initWithError:bundleResult.error];
}

+ (instancetype)daemonConnectionFailed:(FBTestDaemonResult *)daemonResult
{
  NSParameterAssert(daemonResult.didEndSuccessfully == NO);
  NSParameterAssert(daemonResult.error);
  return [[FBTestManagerResult_InternalError alloc] initWithError:daemonResult.error];
}

+ (instancetype)internalError:(XCTestBootstrapError *)error
{
  return [[FBTestManagerResult_InternalError alloc] initWithError:error.build];
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

- (FBCrashLogInfo *)crash
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

@end
