/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBXCTraceConfiguration.h"

#import "FBCollectionInformation.h"

@implementation FBXCTraceRecordConfiguration

#pragma mark Initializers

+ (instancetype)RecordWithTemplateName:(NSString *)templateName
                             timeLimit:(NSTimeInterval)timeLimit
                               package:(NSString *)package
                          allProcesses:(BOOL)allProcesses
                       processToAttach:(NSString *)processToAttach
                       processToLaunch:(NSString *)processToLaunch
                            launchArgs:(NSArray<NSString *> *)launchArgs
                           targetStdin:(NSString *)targetStdin
                          targetStdout:(NSString *)targetStdout
                            processEnv:(NSDictionary<NSString *, NSString *> *)processEnv
                                 shim:(FBXCTestShimConfiguration *)shim
{
  return [[self alloc] initWithTemplateName:templateName timeLimit:timeLimit package:package allProcesses:allProcesses processToAttach:processToAttach processToLaunch:processToLaunch launchArgs:launchArgs targetStdin:targetStdin targetStdout:targetStdout processEnv:processEnv shim:shim];
}

- (instancetype)initWithTemplateName:(NSString *)templateName
                           timeLimit:(NSTimeInterval)timeLimit
                             package:(NSString *)package
                        allProcesses:(BOOL)allProcesses
                     processToAttach:(NSString *)processToAttach
                     processToLaunch:(NSString *)processToLaunch
                          launchArgs:(NSArray<NSString *> *)launchArgs
                         targetStdin:(NSString *)targetStdin
                        targetStdout:(NSString *)targetStdout
                          processEnv:(NSDictionary<NSString *, NSString *> *)processEnv
                               shim:(FBXCTestShimConfiguration *)shim;
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _templateName = templateName;
  _timeLimit = timeLimit;
  _package = package;
  _allProcesses = allProcesses;
  _processToAttach = processToAttach;
  _processToLaunch = processToLaunch;
  _launchArgs = launchArgs;
  _targetStdin = targetStdin;
  _targetStdout = targetStdout;
  _processEnv = processEnv;
  _shim = shim;
  return self;
}

- (instancetype)withShim:(FBXCTestShimConfiguration *)shim
{
  return [[FBXCTraceRecordConfiguration alloc]
    initWithTemplateName:self.templateName
    timeLimit:self.timeLimit
    package:self.package
    allProcesses:self.allProcesses
    processToAttach:self.processToAttach
    processToLaunch:self.processToLaunch
    launchArgs:self.launchArgs
    targetStdin:self.targetStdin
    targetStdout:self.targetStdout
    processEnv:self.processEnv
    shim:shim];
}

#pragma mark NSObject

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"xctrace record: template %@ | duration %f | process to launch %@ | process to attach %@ | package %@ | target stdin %@ | target stdout %@ | target arguments %@ | target environment %@ | record all processes %@",
    self.templateName,
    self.timeLimit,
    self.processToLaunch,
    self.processToAttach,
    self.package,
    self.targetStdin,
    self.targetStdout,
    [FBCollectionInformation oneLineDescriptionFromArray:self.launchArgs],
    [FBCollectionInformation oneLineDescriptionFromDictionary:self.processEnv],
    self.allProcesses ? @"Yes" : @"No"
  ];
}

#pragma mark NSCopying

- (instancetype)copyWithZone:(NSZone *)zone
{
  return self;
}
@end
