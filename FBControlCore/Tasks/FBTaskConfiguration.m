/*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBTaskConfiguration.h"

#import "FBCollectionInformation.h"

@implementation FBTaskConfiguration

- (instancetype)initWithLaunchPath:(NSString *)launchPath arguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment acceptableStatusCodes:(NSSet<NSNumber *> *)acceptableStatusCodes io:(FBProcessIO *)io logger:(nullable id<FBControlCoreLogger>)logger programName:(NSString *)programName
{
  self = [super init];
  if (!self) {
    return nil;
  }

  _launchPath = launchPath;
  _arguments = arguments;
  _environment = environment;
  _acceptableStatusCodes = acceptableStatusCodes;
  _io = io;
  _logger = logger;
  _programName = programName;

  return self;
}

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"Launch Path %@ | Arguments %@",
    self.launchPath,
    [FBCollectionInformation oneLineDescriptionFromArray:self.arguments]
  ];
}

@end
