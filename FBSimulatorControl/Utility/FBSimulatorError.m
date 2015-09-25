/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorError.h"

#import "FBSimulator+Queries.h"
#import "FBSimulator.h"

NSString *const FBSimulatorControlErrorDomain = @"com.facebook.FBSimulatorControl";

@interface FBSimulatorError ()

@property (nonatomic, copy, readwrite) NSString *describedAs;
@property (nonatomic, copy, readwrite) NSError *cause;
@property (nonatomic, strong, readwrite) NSMutableDictionary *additionalInfo;

@end

@implementation FBSimulatorError

- (instancetype)init
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _additionalInfo = [NSMutableDictionary dictionary];
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

- (instancetype)inSimulator:(FBSimulator *)simulator
{
  self.additionalInfo[@"launchd_is_running"] = @(simulator.hasActiveLaunchdSim);
  self.additionalInfo[@"launchd_subprocesses"] = [simulator launchedProcesses];
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
    userInfo[NSUnderlyingErrorKey] = self.cause;
  }
  [userInfo addEntriesFromDictionary:self.additionalInfo];
  return [NSError errorWithDomain:FBSimulatorControlErrorDomain code:0 userInfo:[userInfo copy]];
}

@end

@implementation FBSimulatorError (Constructors)

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
