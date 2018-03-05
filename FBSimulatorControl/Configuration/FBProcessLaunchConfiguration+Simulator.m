/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBProcessLaunchConfiguration+Simulator.h"

#import "FBSimulator.h"
#import "FBSimulatorDiagnostics.h"
#import "FBSimulatorError.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"

@implementation FBProcessLaunchConfiguration (Simulator)

- (instancetype)withEnvironmentAdditions:(NSDictionary<NSString *, NSString *> *)environmentAdditions
{
  NSMutableDictionary *environment = [[self environment] mutableCopy];
  [environment addEntriesFromDictionary:environmentAdditions];

  return [self withEnvironment:[environment copy]];
}

- (instancetype)withAdditionalArguments:(NSArray<NSString *> *)arguments
{
  return [self withAdditionalArguments:[self.arguments arrayByAddingObjectsFromArray:arguments]];
}

- (instancetype)withDiagnosticEnvironment
{
  // It looks like DYLD_PRINT is not currently working as per TN2239.
  return [self withEnvironmentAdditions:@{
    @"OBJC_PRINT_LOAD_METHODS" : @"YES",
    @"OBJC_PRINT_IMAGES" : @"YES",
    @"OBJC_PRINT_IMAGE_TIMES" : @"YES",
    @"DYLD_PRINT_STATISTICS" : @"1",
    @"DYLD_PRINT_ENV" : @"1",
    @"DYLD_PRINT_LIBRARIES" : @"1"
  }];
}

- (instancetype)injectingLibrary:(NSString *)filePath
{
  NSParameterAssert(filePath);

  return [self withEnvironmentAdditions:@{
    @"DYLD_INSERT_LIBRARIES" : filePath
  }];
}

- (instancetype)injectingShimulator
{
  return [self injectingLibrary:[[NSBundle bundleForClass:FBSimulator.class] pathForResource:@"libShimulator" ofType:@"dylib"]];
}

- (NSString *)identifiableName
{
  NSAssert(NO, @"-[%@ %@] is abstract and should be overridden", NSStringFromClass(self.class), NSStringFromSelector(_cmd));
  return nil;
}

+ (NSMutableDictionary<NSString *, id> *)launchOptionsWithArguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment waitForDebugger:(BOOL)waitForDebugger
{
  NSMutableDictionary<NSString *, id> *options = [NSMutableDictionary dictionary];
  options[@"arguments"] = arguments;
  options[@"environment"] = environment ? environment: @{@"__SOME_MAGIC__" : @"__IS_ALIVE__"};
  if (waitForDebugger) {
    options[@"wait_for_debugger"] = @1;
  }
  return options;
}

- (FBFuture<id> *)createStdOutDiagnosticForSimulator:(FBSimulator *)simulator
{
  return [self createDiagnosticForSelector:@selector(stdOut) simulator:simulator];
}

- (FBFuture<id> *)createStdErrDiagnosticForSimulator:(FBSimulator *)simulator
{
  return [self createDiagnosticForSelector:@selector(stdErr) simulator:simulator];
}

- (FBFuture<NSArray<FBProcessOutput *> *> *)createOutputForSimulator:(FBSimulator *)simulator
{
  return [FBFuture futureWithFutures:@[
    [self createOutputForSimulator:simulator selector:@selector(stdOut)],
    [self createOutputForSimulator:simulator selector:@selector(stdErr)],
  ]];
}

#pragma mark Private

- (FBFuture<id> *)createDiagnosticForSelector:(SEL)selector simulator:(FBSimulator *)simulator
{
  NSString *output = [self.output performSelector:selector];
  if (![output isKindOfClass:NSString.class]) {
    return [FBFuture futureWithResult:NSNull.null];
  }

  SEL diagnosticSelector = NSSelectorFromString([NSString stringWithFormat:@"%@:", NSStringFromSelector(selector)]);
  FBDiagnostic *diagnostic = [simulator.diagnostics performSelector:diagnosticSelector withObject:self];
  FBDiagnosticBuilder *builder = [FBDiagnosticBuilder builderWithDiagnostic:diagnostic];

  NSString *path = [output isEqualToString:FBProcessOutputToFileDefaultLocation] ? [builder createPath] : output;

  [builder updateStorageDirectory:[path stringByDeletingLastPathComponent]];

  if (![NSFileManager.defaultManager createFileAtPath:path contents:NSData.data attributes:nil]) {
    return [[FBSimulatorError
      describeFormat:@"Could not create '%@' at path '%@' for config '%@'", NSStringFromSelector(selector), path, self]
      failFuture];
  }

  [builder updatePath:path];

  return [FBFuture futureWithResult:[builder build]];
}

#pragma mark Private

- (FBFuture<FBProcessOutput *> *)createOutputForSimulator:(FBSimulator *)simulator selector:(SEL)selector
{
  return [[self
    createDiagnosticForSelector:selector simulator:simulator]
    onQueue:simulator.workQueue fmap:^FBFuture *(id maybeDiagnostic) {
      if ([maybeDiagnostic isKindOfClass:FBDiagnostic.class]) {
        FBDiagnostic *diagnostic = maybeDiagnostic;
        NSString *path = diagnostic.asPath;
        return [FBFuture futureWithResult:[FBProcessOutput outputForFilePath:path]];
      }
      id<FBFileConsumer> consumer = [self.output performSelector:selector];
      if (![consumer conformsToProtocol:@protocol(FBFileConsumer)]) {
        return [FBFuture futureWithResult:FBProcessOutput.outputForNullDevice];
      }
      return [FBFuture futureWithResult:[FBProcessOutput outputForFileConsumer:consumer]];
    }];
}

#pragma clang diagnostic pop

@end

@implementation FBAgentLaunchConfiguration (Helpers)

- (NSDictionary<NSString *, id> *)simDeviceLaunchOptionsWithStdOut:(NSFileHandle *)stdOut stdErr:(NSFileHandle *)stdErr
{
  return [FBAgentLaunchConfiguration
    simDeviceLaunchOptionsWithLaunchPath:self.agentBinary.path
    arguments:self.arguments
    environment:self.environment
    waitForDebugger:NO
    stdOut:stdOut
    stdErr:stdErr];
}

+ (NSDictionary<NSString *, id> *)simDeviceLaunchOptionsWithLaunchPath:(NSString *)launchPath arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment waitForDebugger:(BOOL)waitForDebugger stdOut:(nullable NSFileHandle *)stdOut stdErr:(nullable NSFileHandle *)stdErr
{
  // argv[0] should be launch path of the process. SimDevice does not do this automatically, so we need to add it.
  arguments = [@[launchPath] arrayByAddingObjectsFromArray:arguments];
  NSMutableDictionary<NSString *, id> *options = [FBProcessLaunchConfiguration launchOptionsWithArguments:arguments environment:environment waitForDebugger:waitForDebugger];
  if (stdOut){
    options[@"stdout"] = @([stdOut fileDescriptor]);
  }
  if (stdErr) {
    options[@"stderr"] = @([stdErr fileDescriptor]);
  }
  return [options copy];
}

- (NSString *)identifiableName
{
  return self.agentBinary.name;
}

@end

@implementation FBApplicationLaunchConfiguration (Helpers)

- (instancetype)overridingLocalization:(FBLocalizationOverride *)localizationOverride
{
  return [self withAdditionalArguments:localizationOverride.arguments];
}

- (NSString *)identifiableName
{
  return self.bundleID;
}

- (NSDictionary<NSString *, id> *)simDeviceLaunchOptionsWithStdOutPath:(nullable NSString *)stdOutPath stdErrPath:(nullable NSString *)stdErrPath waitForDebugger:(BOOL)waitForDebugger
{
  NSMutableDictionary<NSString *, id> *options = [FBProcessLaunchConfiguration launchOptionsWithArguments:self.arguments environment:self.environment waitForDebugger:waitForDebugger];
  if (stdOutPath){
    options[@"stdout"] = stdOutPath;
  }
  if (stdErrPath) {
    options[@"stderr"] = stdErrPath;
  }
  return [options copy];
}

@end
