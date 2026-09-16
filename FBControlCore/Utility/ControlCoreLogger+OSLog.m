/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "ControlCoreLogger+OSLog.h"

#import <FBControlCore/FBControlCore-Swift.h>

#if defined(__apple_build_version__)

 #include <os/log.h>

static const char *LoggerSubsystem = "com.facebook.fbcontrolcore";

@interface FBControlCoreLogger_OSLog : NSObject <ControlCoreLogger>

@property (nonatomic, readonly, strong) os_log_t client;

@end

@implementation FBControlCoreLogger_OSLog

@synthesize level = _level;
@synthesize name = _name;

- (instancetype)initWithClient:(os_log_t)client name:(NSString *)name level:(FBControlCoreLogLevel)level
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _client = client;
  _name = name;
  _level = level;

  return self;
}

- (id<ControlCoreLogger>)log:(NSString *)message
{
  switch (self.level) {
    case FBControlCoreLogLevelError:
      os_log_error(self.client, "%{public}s", message.UTF8String);
      break;
    case FBControlCoreLogLevelInfo:
      os_log_info(self.client, "%{public}s", message.UTF8String);
      break;
    case FBControlCoreLogLevelDebug:
      os_log_debug(self.client, "%{public}s", message.UTF8String);
      break;
    case FBControlCoreLogLevelMultiple:
    default:
      os_log(self.client, "%{public}s", message.UTF8String);
      break;
  }
  return self;
}

- (id<ControlCoreLogger>)info
{
  return [[self.class alloc] initWithClient:self.client name:self.name level:FBControlCoreLogLevelInfo];
}

- (id<ControlCoreLogger>)debug
{
  return [[self.class alloc] initWithClient:self.client name:self.name level:FBControlCoreLogLevelDebug];
}

- (id<ControlCoreLogger>)error
{
  return [[self.class alloc] initWithClient:self.client name:self.name level:FBControlCoreLogLevelError];
}

- (id<ControlCoreLogger>)withName:(NSString *)name
{
  os_log_t client = os_log_create(LoggerSubsystem, name.UTF8String);
  return [[self.class alloc] initWithClient:client name:name level:self.level];
}

- (id<ControlCoreLogger>)withDateFormatEnabled:(BOOL)dateFormat
{
  return self;
}

@end

#endif

@implementation FBControlCoreLoggerFactory (OSLog)

+ (id<ControlCoreLogger>)osLoggerWithLevel:(FBControlCoreLogLevel)level
{
#if defined(__apple_build_version__)
  os_log_t client = os_log_create(LoggerSubsystem, "");
  return [[FBControlCoreLogger_OSLog alloc] initWithClient:client name:nil level:level];
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
