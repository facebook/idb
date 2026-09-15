/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import "FBAXSignatureProbe.h"

@implementation FBAXSignatureProbe
- (FBAXQuad)quadFromPair:(FBAXPair)pair
{
  return (FBAXQuad) {{pair.first, pair.second, 0, 0}};
}

@end
