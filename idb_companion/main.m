/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#import <FBControlCore/FBControlCore.h>

#import "FBBootManager.h"
#import "FBIDBCompanionServer.h"
#import "FBIDBConfiguration.h"
#import "FBIDBError.h"
#import "FBIDBPortsConfiguration.h"
#import "FBiOSTargetProvider.h"
#import "FBiOSTargetStateChangeNotifier.h"
#import "FBStorageUtils.h"
#import "FBTemporaryDirectory.h"

const char *kUsageHelpMessage = "\
Usage: \n \
  --udid UDID                Will attach to a device/simulator with the specified UDID \n \
  --boot UDID                Will boot a simulator with the specified UDID \n \
  --debug-port PORT          Port to connect debugger on (default: 10881) \n \
  --grpc-port PORT           Port to start GRPC on (default: 10882) \n \
  --log-file-path PATH       Path to write a log file to e.g ./output.log (default: logs to stdErr) \n \
  --device-set-path PATH     Path to the custom device set if used \n \
  --notify VALUE             When set to 1 - enables notify mode \n \
  --terminate-offline VALUE  Terminate if the target goes offline, otherwise the companion will stay alive\n \
  --help                     Show this help message and exit \n";

static BOOL shouldPrintUsage(void) {
  return [NSProcessInfo.processInfo.arguments containsObject:@"--help"];
}

static id<FBControlCoreLogger> CreateRootLogger(NSUserDefaults *defaults)
{
  id<FBControlCoreLogger> logger = [FBControlCoreLogger systemLoggerWritingToStderr:YES withDebugLogging:YES];

  NSError *error;
  NSUserDefaults *userDefaults = NSUserDefaults.standardUserDefaults;
  NSString *logFilePath = [userDefaults stringForKey:@"-log-file-path"];
  if (logFilePath) {
    NSURL *logFileURL = [NSURL fileURLWithPath:logFilePath];
    if (![[NSFileManager defaultManager] createDirectoryAtURL:logFileURL.URLByDeletingLastPathComponent
                                  withIntermediateDirectories:YES
                                                   attributes:@{}
                                                        error:&error]) {
      [logger.error logFormat:@"Couldn't create log file path %@", error];
      exit(1);
    }

    if (![[NSFileManager defaultManager] createFileAtPath:logFileURL.path
                                                 contents:nil
                                               attributes:@{}]) {
      [logger.error log:@"Couldn't create log file"];
      exit(1);
    }

    int fileDescriptor = open(logFileURL.path.UTF8String, O_WRONLY | O_APPEND | O_CREAT);
    [logger logFormat:@"All logs will be written to %@", logFileURL.path];
    logger = [FBControlCoreLogger compositeLoggerWithLoggers:@[
      logger,
      [FBControlCoreLogger loggerToFileDescriptor:fileDescriptor closeOnEndOfFile:YES],
    ]];
  }
  return [logger withDateFormatEnabled:YES];
}

static FBFuture<NSNull *> *TargetOfflineFuture(id<FBiOSTarget> target, id<FBControlCoreLogger> logger)
{
  return [[FBFuture
    onQueue:target.workQueue resolveWhen:^ BOOL {
      if (target.state != FBiOSTargetStateBooted) {
        [logger.error logFormat:@"Target with udid %@ is no longer booted, it is in state %@", target.udid, FBiOSTargetStateStringFromState(target.state)];
        return YES;
      }
      return NO;
    }]
    mapReplace:NSNull.null];
}

static FBFuture<FBFuture<NSNull *> *> *GetCompanionCompletedFuture(int argc, const char *argv[], NSUserDefaults *userDefaults, id<FBControlCoreLogger> logger) {
  NSString *udid = [userDefaults stringForKey:@"-udid"];
  BOOL notify = [userDefaults boolForKey:@"-notify"];
  NSString *boot = [userDefaults stringForKey:@"-boot"];
  BOOL terminateOffline = [userDefaults boolForKey:@"-terminate-offline"];

  NSError *error = nil;
  id<FBEventReporter> reporter = FBIDBConfiguration.eventReporter;
  if (udid) {
    id<FBiOSTarget> target = [FBiOSTargetProvider targetWithUDID:udid logger:logger reporter:reporter error:&error];
    if (!target) {
      return [FBFuture futureWithError:error];
    }
    [reporter addMetadata:@{@"udid": udid}];
    [reporter report:[FBEventReporterSubject subjectForEvent:FBEventNameLaunched]];

    // Start up the companion
    FBIDBPortsConfiguration *ports = [FBIDBPortsConfiguration portsWithArguments:userDefaults];
    FBTemporaryDirectory *temporaryDirectory = [FBTemporaryDirectory temporaryDirectoryWithLogger:logger];
    FBIDBCompanionServer *companion = [FBIDBCompanionServer companionForTarget:target temporaryDirectory:temporaryDirectory ports:ports eventReporter:reporter logger:logger error:&error];
    if (!companion) {
      return [FBFuture futureWithError:error];
    }

    return [[companion
      start]
      onQueue:target.workQueue map:^(id<FBIDBCompanionServer> server) {
        NSData *jsonOutput = [NSJSONSerialization dataWithJSONObject:server.jsonSerializableRepresentation options:0 error:nil];
        NSMutableData *readyOutput = [NSMutableData dataWithData:jsonOutput];
        [readyOutput appendData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]];
        write(STDOUT_FILENO, readyOutput.bytes, readyOutput.length);
        fflush(stdout);
        FBFuture<NSNull *> *completed = server.completed;
        if (terminateOffline) {
          [logger.info logFormat:@"Companion will terminate when target goes offline"];
          completed = [FBFuture race:@[completed, TargetOfflineFuture(target, logger)]];
        } else {
          [logger.info logFormat:@"Companion will stay alive if target goes offline"];
        }
        return [completed
          onQueue:target.workQueue chain:^(FBFuture *future) {
            [temporaryDirectory cleanOnExit];
            return future;
          }];
      }];
  } else if (notify) {
    [logger.info log:@"Notify mode is set"];
    return [[FBiOSTargetStateChangeNotifier stdoutNotifierWithLogger:logger] startNotifier];
  } else if (boot) {
    [logger.info log:@"Booting target"];
    return [FBFuture futureWithResult:[[FBBootManager bootManagerForLogger:logger] boot:boot]];
  }

  return [[FBIDBError
    describeFormat:@"Please select the companion mode you want. \n--udid for attaching to a specific target. \n--boot to boot a specific target. or \n--notify to notify idb daemon of targets available \n\n%s", kUsageHelpMessage]
    failFuture];
}

static FBFuture<NSNumber *> *signalHandlerFuture(int signalCode, NSString *exitMessage, id<FBControlCoreLogger> logger)
{
  dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);
  FBMutableFuture<NSNumber *> *future = FBMutableFuture.future;
  dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, signalCode, 0, dispatch_get_main_queue());
  dispatch_source_set_event_handler(source, ^{
    [logger.error log:exitMessage];
    [future resolveWithResult:@(signalCode)];
  });
  dispatch_resume(source);
  struct sigaction action = {{0}};
  action.sa_handler = SIG_IGN;
  sigaction(signalCode, &action, NULL);
  return [future
    onQueue:queue notifyOfCompletion:^(FBFuture *_) {
      dispatch_cancel(source);
    }];
}

int main(int argc, const char *argv[]) {
  if (shouldPrintUsage()) {
    fprintf(stderr, "%s", kUsageHelpMessage);
    return 1;
  }

  @autoreleasepool {
    NSUserDefaults *userDefaults = NSUserDefaults.standardUserDefaults;
    FBControlCoreGlobalConfiguration.defaultLogger = CreateRootLogger(userDefaults);
    id<FBControlCoreLogger> logger = [FBControlCoreGlobalConfiguration.defaultLogger withName:@"main"];
    [logger.info logFormat:@"IDB Companion Built at %s %s", __DATE__, __TIME__];
    [logger.info logFormat:@"Invoked with args=%@ env=%@", [FBCollectionInformation oneLineDescriptionFromArray:NSProcessInfo.processInfo.arguments], [FBCollectionInformation oneLineDescriptionFromDictionary:NSProcessInfo.processInfo.environment]];

    NSError *error = nil;
    FBFuture<NSNull *> *completed = [GetCompanionCompletedFuture(argc, argv, userDefaults, logger) await:&error];
    if (!completed) {
      [logger.error log:error.localizedDescription];
      return 1;
    }

    completed = [FBFuture race:@[
      completed,
      signalHandlerFuture(SIGINT, @"Exiting: SIGINT", logger),
      signalHandlerFuture(SIGTERM, @"Exiting: SIGTERM", logger),
    ]];
    if (completed.error) {
      [logger.error log:completed.error.localizedDescription];
      return 1;
    }
    [completed await:nil];
  }
  return 0;
}
