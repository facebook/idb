/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBXCTestBootstrapper.h"

#import <FBControlCore/FBControlCore.h>
#import <XCTestBootstrap/XCTestBootstrap.h>

#import <FBXCTestKit/FBXCTestKit.h>

@interface FBXCTestBootstrapper ()

@property (nonatomic, strong, readonly) FBXCTestLogger *logger;

@end

@implementation FBXCTestBootstrapper

- (instancetype)init
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _logger = FBXCTestLogger.defaultLoggerInDefaultDirectory;
  FBControlCoreGlobalConfiguration.defaultLogger = _logger;

  return self;
}

- (NSString *)workingDirectory:(NSArray<NSString *> *)arguments
{
  NSUInteger index = [arguments indexOfObject:@"-workingDirectory"];
  if (index == NSNotFound) {
    return [NSTemporaryDirectory() stringByAppendingPathComponent:NSProcessInfo.processInfo.globallyUniqueString];
  } else {
    return [arguments objectAtIndex:index+1];
  }
}

- (BOOL)definesReusableWorkingDirectory:(NSArray<NSString *> *)arguments {
  return [arguments containsObject:@"-workingDirectory"];
}

- (NSTimeInterval)timeout:(NSArray<NSString *> *)arguments {
  NSUInteger index = [arguments indexOfObject:@"-timeout"];
  if (index == NSNotFound) {
    return 0;
  } else {
    return [arguments objectAtIndex:index+1].doubleValue;
  }
}

- (BOOL)bootstrap
{
  NSError *error;

  NSArray<NSString *> *arguments = NSProcessInfo.processInfo.arguments;
  arguments = [arguments subarrayWithRange:NSMakeRange(1, [arguments count] - 1)];
  [self.logger.debug logFormat:@"fbxctest arguments: %@", [FBCollectionInformation oneLineDescriptionFromArray:arguments]];
  [self.logger.debug logFormat:@"xcode configuration: %@", [FBCollectionInformation oneLineDescriptionFromDictionary:FBXcodeConfiguration.new.jsonSerializableRepresentation]];
  
  NSString *workingDirectory = [self workingDirectory:arguments];
  
  if (![NSFileManager.defaultManager createDirectoryAtPath:workingDirectory withIntermediateDirectories:YES attributes:nil error:&error]) {
    return [self printErrorMessage:error file:__FILE__ line:__LINE__];
  }
  
  FBXCTestCommandLine *commandLine = [FBXCTestCommandLine
    commandLineFromArguments:arguments
    processUnderTestEnvironment:NSProcessInfo.processInfo.environment
    workingDirectory:workingDirectory
    timeout:[self timeout:arguments]
    logger:self.logger
    error:&error];
  if (!commandLine) {
    return [self printErrorMessage:error file:__FILE__ line:__LINE__];
  }
  id<FBDataConsumer> stdOutFileWriter = [FBFileWriter syncWriterWithFileDescriptor:STDOUT_FILENO closeOnEndOfFile:NO];
  FBJSONTestReporter *reporter = [[FBJSONTestReporter alloc] initWithTestBundlePath:commandLine.configuration.testBundlePath testType:commandLine.configuration.testType logger:self.logger dataConsumer:stdOutFileWriter];
  FBXCTestContext *context = [FBXCTestContext contextWithReporter:reporter logger:self.logger];

  [self.logger.info logFormat:@"Bootstrapping Test Runner with Configuration %@", [FBCollectionInformation oneLineJSONDescription:commandLine.configuration]];
  FBXCTestBaseRunner *testRunner = [FBXCTestBaseRunner testRunnerWithCommandLine:commandLine context:context];
  if (![[testRunner execute] await:&error]) {
    return [self printErrorMessage:error file:__FILE__ line:__LINE__];
  }

  if (![self definesReusableWorkingDirectory:arguments] &&
      ![NSFileManager.defaultManager removeItemAtPath:workingDirectory error:&error]) {
    return [self printErrorMessage:error file:__FILE__ line:__LINE__];
  }

  return YES;
}


- (BOOL)printErrorMessage:(NSError *)error file:(char *)file line:(NSUInteger)line
{
  NSString *message = [NSString stringWithFormat:@"%s:%lu: %@\n", file, (unsigned long)line, error.localizedDescription];
  if (message) {
    fputs(message.UTF8String, stderr);
  }
  fflush(stderr);
  return NO;
}

@end
