/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

// Carries an aggregate signature for the encoding-comparison tests. Foundation has plenty of selectors to
// compare against, but none whose encoding contains a digit that is part of the type rather than an
// offset, which is the case the comparison has to get right.
typedef struct FBAXQuad {
  int values[4];
} FBAXQuad;

typedef struct FBAXPair {
  int first;
  int second;
} FBAXPair;

@interface FBAXSignatureProbe : NSObject
- (FBAXQuad)quadFromPair:(FBAXPair)pair;
@end
