/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBControlCoreError.h"

#import "FBFuture.h"
#import "FBControlCoreGlobalConfiguration.h"
#import "FBControlCoreLogger.h"

NSString *const FBControlCoreErrorDomain = @"com.facebook.FBControlCore";

@interface FBControlCoreError ()

@property (nonatomic, copy, readwrite) NSString *domain;
@property (nonatomic, copy, readwrite) NSString *describedAs;
@property (nonatomic, copy, readwrite) NSError *cause;
@property (nonatomic, strong, nullable, readwrite) id<FBControlCoreLogger> logger;
@property (nonatomic, strong, readwrite) NSMutableDictionary *additionalInfo;
@property (nonatomic, assign, readwrite) BOOL describeRecursively;
@property (nonatomic, assign, readwrite) NSInteger code;

@end

@implementation FBControlCoreError

#pragma mark Initializers

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

#pragma mark Public Methods

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

- (int)failInt:(NSError **)error
{
  if (error) {
    *error = [self build];
  }
  return 0;
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

- (FBFuture *)failFuture
{
  NSError *error = [self build];
  return [FBFuture futureWithError:error];
}

- (FBFutureContext *)failFutureContext
{
  return [FBFutureContext futureContextWithError:[self build]];
}

- (void *)failPointer:(NSError **)error;
{
  if (error) {
    *error = [self build];
  }
  return NULL;
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

- (instancetype)noLogging
{
  self.logger = nil;
  return self;
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
  if (self.logger.level >= FBControlCoreLogLevelDebug) {
    [self.logger.error logFormat:@"New Error Built ==> %@", error];
  }

  return error;
}

#pragma mark NSObject

- (NSString *)description
{
  return [self.build description];
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

+ (NSError *)errorForFormat:(NSString *)format, ...
{
  va_list args;
  va_start(args, format);
  NSString *string = [[NSString alloc] initWithFormat:format arguments:args];
  va_end(args);
  return [self errorForDescription:string];
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

+ (FBFuture *)failFutureWithError:(NSError *)error
{
  return [FBFuture futureWithError:error];
}

@end
