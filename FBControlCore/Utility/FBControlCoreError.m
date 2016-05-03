/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBControlCoreError.h"

#import "FBControlCoreGlobalConfiguration.h"
#import "FBControlCoreLogger.h"
#import "FBProcessInfo.h"
#import "FBProcessFetcher.h"

NSString *const FBControlCoreErrorDomain = @"com.facebook.FBControlCore";

@interface FBControlCoreError ()

@property (nonatomic, copy, readwrite) NSString *domain;
@property (nonatomic, copy, readwrite) NSString *describedAs;
@property (nonatomic, copy, readwrite) NSError *cause;
@property (nonatomic, strong, readwrite) id<FBControlCoreLogger> logger;
@property (nonatomic, strong, readwrite) NSMutableDictionary *additionalInfo;
@property (nonatomic, assign, readwrite) BOOL describeRecursively;
@property (nonatomic, assign, readwrite) NSInteger code;

@end

@implementation FBControlCoreError

- (instancetype)init
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _domain = FBControlCoreErrorDomain;
  _code = 0;
  _additionalInfo = [NSMutableDictionary dictionary];
  _describeRecursively = YES;
  _logger = FBControlCoreGlobalConfiguration.defaultLogger;

  return self;
}

+ (instancetype)describe:(NSString *)description
{
  return [self.new describe:description];
}

- (instancetype)describe:(NSString *)description
{
  self.describedAs = description;
  return self;
}

+ (instancetype)describeFormat:(NSString *)format, ...
{
  va_list args;
  va_start(args, format);
  NSString *string = [[NSString alloc] initWithFormat:format arguments:args];
  va_end(args);
  return [self describe:string];
}

- (instancetype)describeFormat:(NSString *)format, ...
{
  va_list args;
  va_start(args, format);
  NSString *string = [[NSString alloc] initWithFormat:format arguments:args];
  va_end(args);
  return [self describe:string];
}

+ (instancetype)causedBy:(NSError *)cause
{
  return [self.new causedBy:cause];
}

- (instancetype)causedBy:(NSError *)cause
{
  self.cause = cause;
  return self;
}

- (BOOL)failBool:(NSError **)error
{
  if (error) {
    *error = [self build];
  }
  return NO;
}

- (unsigned int)failUInt:(NSError **)error
{
  if (error) {
    *error = [self build];
  }
  return 0;
}

- (CGRect)failRect:(NSError **)error
{
  if (error) {
    *error = [self build];
  }
  return CGRectNull;
}

- (id)fail:(NSError **)error
{
  if (error) {
    *error = [self build];
  }
  return nil;
}

- (instancetype)extraInfo:(NSString *)key value:(id)value
{
  if (!key || !value) {
    return self;
  }
  self.additionalInfo[key] = value;
  return self;
}

- (instancetype)recursiveDescription
{
  self.describeRecursively = YES;
  return self;
}

- (instancetype)noRecursiveDescription
{
  self.describeRecursively = NO;
  return self;
}

- (instancetype)attachProcessInfoForIdentifier:(pid_t)processIdentifier processFetcher:(FBProcessFetcher *)processFetcher
{
  return [self
    extraInfo:[NSString stringWithFormat:@"%d_process", processIdentifier]
    value:[processFetcher processInfoFor:processIdentifier] ?: @"No Process Info"];
}

- (instancetype)logger:(id<FBControlCoreLogger>)logger
{
  self.logger = logger;
  return self;
}

- (instancetype)inDomain:(NSString *)domain
{
  self.domain = domain;
  return self;
}

- (instancetype)code:(NSInteger)code
{
  self.code = code;
  return self;
}

- (NSError *)build
{
  // If there's just a cause, there's no error to build
  if (self.cause && !self.describedAs && self.additionalInfo.count == 0) {
    return self.cause;
  }

  NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
  if (self.describedAs) {
    userInfo[NSLocalizedDescriptionKey] = self.describedAs;
  }
  if (self.cause) {
    userInfo[NSUnderlyingErrorKey] = self.underlyingError;
  }
  [userInfo addEntriesFromDictionary:self.additionalInfo];

  NSError *error = [NSError errorWithDomain:self.domain code:self.code userInfo:[userInfo copy]];
  if (FBControlCoreGlobalConfiguration.debugLoggingEnabled) {
    [self.logger.error logFormat:@"New Error Built ==> %@", error];
  }

  return error;
}

#pragma mark Private

- (NSError *)underlyingError
{
  NSError *error = self.cause;
  if (!self.describeRecursively) {
    return error;
  }
  NSError *cause = self.cause;
  if (!cause) {
    return error;
  }

  NSMutableString *description = [NSMutableString stringWithFormat:@"%@", error.localizedDescription];
  while (error.userInfo[NSUnderlyingErrorKey]) {
    error = error.userInfo[NSUnderlyingErrorKey];
    [description appendFormat:@"\nCaused By: %@", error.localizedDescription];
  }

  NSMutableDictionary *userInfo = [cause.userInfo mutableCopy];
  userInfo[NSLocalizedDescriptionKey] = description;
  return [NSError errorWithDomain:cause.domain code:cause.code userInfo:[userInfo copy]];
}

@end

@implementation FBControlCoreError (Constructors)

+ (NSError *)errorForDescription:(NSString *)description
{
  return [[self describe:description] build];
}

+ (id)failWithErrorMessage:(NSString *)errorMessage errorOut:(NSError **)errorOut
{
  return [[self describe:errorMessage] fail:errorOut];
}

+ (id)failWithError:(NSError *)failureCause errorOut:(NSError **)errorOut
{
  return [[self causedBy:failureCause] fail:errorOut];
}

+ (id)failWithError:(NSError *)failureCause description:(NSString *)description errorOut:(NSError **)errorOut
{
  return [[[self causedBy:failureCause] describe:description] fail:errorOut];
}

+ (BOOL)failBoolWithErrorMessage:(NSString *)errorMessage errorOut:(NSError **)errorOut
{
  return [[self describe:errorMessage] failBool:errorOut];
}

+ (BOOL)failBoolWithError:(NSError *)failureCause errorOut:(NSError **)errorOut
{
  return [[self causedBy:failureCause] failBool:errorOut];
}

+ (BOOL)failBoolWithError:(NSError *)failureCause description:(NSString *)description errorOut:(NSError **)errorOut
{
  return [[[self causedBy:failureCause] describe:description] failBool:errorOut];
}

@end
