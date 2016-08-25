/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBTestBundleResult.h"

#import "XCTestBootstrapError.h"

@interface FBTestBundleResult_Success : FBTestBundleResult
@end

@implementation FBTestBundleResult_Success

- (BOOL)didEndSuccessfully
{
  return YES;
}

- (NSError *)error
{
  return nil;
}

- (FBDiagnostic *)diagnostic
{
  return nil;
}

- (NSString *)description
{
  return @"Bundle Connection ended normally";
}

@end

@interface FBTestBundleResult_ClientRequestedDisconnect : FBTestBundleResult
@end

@implementation FBTestBundleResult_ClientRequestedDisconnect

- (BOOL)didEndSuccessfully
{
  return YES;
}

- (NSError *)error
{
  return nil;
}

- (FBDiagnostic *)diagnostic
{
  return nil;
}

- (NSString *)description
{
  return @"Bundle Connection ended when client requested disconnect";
}

@end

@interface FBTestBundleResult_CrashedDuringTestRun : FBTestBundleResult
@property (nonatomic, strong, readonly) FBDiagnostic *underlyingDiagnostic;
@end

@implementation FBTestBundleResult_CrashedDuringTestRun

- (instancetype)initWithDiagnostic:(FBDiagnostic *)diagnostic
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _underlyingDiagnostic = diagnostic;
  return self;
}

- (BOOL)didEndSuccessfully
{
  return NO;
}

- (NSError *)error
{
  return [[XCTestBootstrapError
    describe:@"The Test Bundle Crashed during the Test Run"]
    build];
}

- (FBDiagnostic *)diagnostic
{
  return self.underlyingDiagnostic;
}

- (NSString *)description
{
  return [NSString stringWithFormat:@"Bundle Connection crashed during test run: %@", self.diagnostic];
}

@end

@interface FBTestBundleResult_FailedInError : FBTestBundleResult
@property (nonatomic, strong, readonly) NSError *underlyingError;
@end

@implementation FBTestBundleResult_FailedInError

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

- (FBDiagnostic *)diagnostic
{
  return nil;
}

- (NSString *)description
{
  return [NSString stringWithFormat:@"Bundle Connection Failed in error: %@", self.error];
}

@end

@implementation FBTestBundleResult

#pragma mark Constructors

+ (instancetype)success
{
  return [FBTestBundleResult_Success new];
}

+ (instancetype)clientRequestedDisconnect
{
  return [FBTestBundleResult_ClientRequestedDisconnect new];
}

+ (instancetype)bundleCrashedDuringTestRun:(FBDiagnostic *)diagnostic
{
  return [[FBTestBundleResult_CrashedDuringTestRun alloc] initWithDiagnostic:diagnostic];
}

+ (instancetype)failedInError:(XCTestBootstrapError *)error
{
  return [[FBTestBundleResult_FailedInError alloc] initWithError:error.build];
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

- (FBDiagnostic *)diagnostic
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

@end
