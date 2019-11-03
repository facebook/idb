/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBServiceManagement.h"

#import <ServiceManagement/ServiceManagement.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated"

@implementation FBServiceManagement

+ (nullable NSDictionary<NSString *, id> *)jobInformationForUserServiceNamed:(NSString *)serviceName
{
  CFDictionaryRef dictionary = SMJobCopyDictionary(kSMDomainUserLaunchd, (__bridge CFStringRef) serviceName);
  return (__bridge_transfer NSDictionary *) dictionary;
}

+ (NSDictionary<NSString *, NSDictionary<NSString *, id> *> *)jobInformationForUserServicesNamed:(NSArray<NSString *> *)serviceNames
{
  NSSet<NSString *> *serviceSet = [NSSet setWithArray:serviceNames];

  CFArrayRef jobs = SMCopyAllJobDictionaries(kSMDomainUserLaunchd);
  NSMutableDictionary<NSString *, NSDictionary<NSString *, id> *> *jobInformation = [NSMutableDictionary dictionary];
  for (CFIndex index = 0; index < CFArrayGetCount(jobs); index++) {
    NSDictionary *dictionary = (__bridge NSDictionary *) CFArrayGetValueAtIndex(jobs, index);
    NSString *labelString = dictionary[@"Label"];
    if (![serviceSet containsObject:labelString]) {
      continue;
    }
    jobInformation[labelString] = dictionary;
  }
  CFRelease(jobs);
  return [jobInformation copy];
}

+ (NSArray<NSDictionary<NSString *, id> *> *)jobsWithProgramWithLaunchPathSubstring:(NSString *)launchPathSubstring
{
  CFArrayRef jobs = SMCopyAllJobDictionaries(kSMDomainUserLaunchd);
  NSMutableArray<NSDictionary<NSString *, id> *> *matchingJobs = [NSMutableArray array];

  for (CFIndex index = 0; index < CFArrayGetCount(jobs); index++) {
    NSDictionary *job = (__bridge NSDictionary *) CFArrayGetValueAtIndex(jobs, index);
    NSString *jobLaunchPath = job[@"Program"];
    if (![jobLaunchPath containsString:launchPathSubstring]) {
      continue;
    }
    [matchingJobs addObject:job];
  }
  CFRelease(jobs);
  return [matchingJobs copy];
}

@end

#pragma clang diagnostic pop
