/*
 * Copyright (c) Facebook, Inc. and its affiliates.
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
                               package:(nullable NSString *)package
                          allProcesses:(BOOL)allProcesses
                       processToAttach:(nullable NSString *)processToAttach
                       processToLaunch:(nullable NSString *)processToLaunch
                            launchArgs:(nullable NSArray<NSString *> *)launchArgs
                           targetStdin:(nullable NSString *)targetStdin
                          targetStdout:(nullable NSString *)targetStdout
                            processEnv:(NSDictionary<NSString *, NSString *> *)processEnv
{
  return [[self alloc] initWithTemplateName:templateName timeLimit:timeLimit package:package allProcesses:allProcesses processToAttach:processToAttach processToLaunch:processToLaunch launchArgs:launchArgs targetStdin:targetStdin targetStdout:targetStdout processEnv:processEnv];
}

- (instancetype)initWithTemplateName:(NSString *)templateName
                           timeLimit:(NSTimeInterval)timeLimit
                             package:(nullable NSString *)package
                        allProcesses:(BOOL)allProcesses
                     processToAttach:(nullable NSString *)processToAttach
                     processToLaunch:(nullable NSString *)processToLaunch
                          launchArgs:(nullable NSArray<NSString *> *)launchArgs
                         targetStdin:(nullable NSString *)targetStdin
                        targetStdout:(nullable NSString *)targetStdout
                          processEnv:(NSDictionary<NSString *, NSString *> *)processEnv
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
  return self;
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
