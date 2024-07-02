/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBDsymInstallLinkToBundle.h"

@implementation FBDsymInstallLinkToBundle

- (instancetype)initWith:(NSString *)bundle_id bundle_type:(FBDsymBundleType)bundle_type
{
  self = [super init];
  if (!self) {
    return nil;
  }
  
  _bundle_id = bundle_id;
  _bundle_type = bundle_type;

  return self;
}

@end
