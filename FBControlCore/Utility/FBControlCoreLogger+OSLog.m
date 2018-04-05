/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBControlCoreLogger+OSLog.h"

#if defined(__apple_build_version__)

#include <os/log.h>

static const char *LoggerSubsystem = "com.facebook.fbcontrolcore";

@interface FBControlCoreLogger_OSLog : NSObject <FBControlCoreLogger>

@property (nonatomic, strong, readonly) os_log_t client;

@end

@implementation FBControlCoreLogger_OSLog

@synthesize level = _level;
@synthesize prefix = _prefix;

- (instancetype)initWithClient:(os_log_t)client prefix:(NSString *)prefix level:(FBControlCoreLogLevel)level
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _client = client;
  _prefix = prefix;
  _level = level;

  return self;
}

- (id<FBControlCoreLogger>)log:(NSString *)message
{
  switch (self.level) {
    case FBControlCoreLogLevelError:
      os_log_error(self.client, "%s", message.UTF8String);
      break;
    case FBControlCoreLogLevelInfo:
      os_log_info(self.client, "%s", message.UTF8String);
      break;
    case FBControlCoreLogLevelDebug:
      os_log_debug(self.client, "%s", message.UTF8String);
      break;
    default:
      break;
  }
  return self;
}

- (id<FBControlCoreLogger>)logFormat:(NSString *)format, ...
{
  va_list args;
  va_start(args, format);
  NSString *string = [[NSString alloc] initWithFormat:format arguments:args];
  va_end(args);

  return [self log:string];
}

- (id<FBControlCoreLogger>)info
{
  return [[self.class alloc] initWithClient:self.client prefix:self.prefix level:FBControlCoreLogLevelInfo];
}

- (id<FBControlCoreLogger>)debug
{
  return [[self.class alloc] initWithClient:self.client prefix:self.prefix level:FBControlCoreLogLevelDebug];
}

- (id<FBControlCoreLogger>)error
{
  return [[self.class alloc] initWithClient:self.client prefix:self.prefix level:FBControlCoreLogLevelError];
}

- (id<FBControlCoreLogger>)withPrefix:(NSString *)prefix
{
  os_log_t client = os_log_create(LoggerSubsystem, prefix.UTF8String);
  return [[self.class alloc] initWithClient:client prefix:prefix level:self.level];
}

- (id<FBControlCoreLogger>)withDateFormatEnabled:(BOOL)dateFormat
{
  return self;
}

@end

#endif

@implementation FBControlCoreLogger (OSLog)

+ (id<FBControlCoreLogger>)osLoggerWithLevel:(FBControlCoreLogLevel)level
{
#if defined(__apple_build_version__)
  os_log_t client = os_log_create(LoggerSubsystem, "");
  return [[FBControlCoreLogger_OSLog alloc] initWithClient:client prefix:nil level:level];
#else
  return nil;
#endif
}

+ (BOOL)systemLoggerWillLogToStdErr
{
#if defined(__apple_build_version__)
  // rdar://36919139
  // os_log will log to stderr depending on if some environment variables are set.
  NSDictionary<NSString *, NSString *> *environment = NSProcessInfo.processInfo.environment;
  return environment[@"OS_ACTIVITY_DT_MODE"] || environment[@"ACTIVITY_LOG_STDERR"] || environment[@"CFLOG_FORCE_STDERR"];
#else
  return YES;
#endif
}

@end
