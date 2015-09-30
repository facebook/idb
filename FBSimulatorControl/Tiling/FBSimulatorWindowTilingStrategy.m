/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBSimulatorWindowTilingStrategy.h"

#import "FBSimulator.h"
#import "FBSimulatorError.h"
#import "FBSimulatorWindowHelpers.h"

static inline NSRange FBHorizontalOcclusionRange(CGRect rect)
{
  rect = CGRectIntegral(rect);
  return NSMakeRange(
    (NSUInteger) CGRectGetMinX(rect),
    (NSUInteger) (CGRectGetMaxX(rect) - CGRectGetMinX(rect))
  );
}

@interface FBWindowTilingStrategy_HorizontalOcclusion : NSObject <FBSimulatorWindowTilingStrategy>

@property (nonatomic, strong, readwrite) FBSimulator *targetSimulator;

@end

@implementation FBWindowTilingStrategy_HorizontalOcclusion

- (CGRect)targetPositionOfWindowWithSize:(CGSize)windowSize inScreenSize:(CGSize)screenSize withError:(NSError **)error
{
  NSMutableIndexSet *xOccluded = [NSMutableIndexSet indexSet];
  NSArray *occludingWindows = [FBSimulatorWindowHelpers obtainBoundsOfOtherSimulators:self.targetSimulator];

  // Only checks the X-Axis
  for (NSValue *contentRectValue in occludingWindows) {
    [xOccluded addIndexesInRange:FBHorizontalOcclusionRange(contentRectValue.rectValue)];
  }

  CGRect rect = { CGPointZero, windowSize };
  while ([xOccluded containsIndexesInRange:FBHorizontalOcclusionRange(rect)]) {
    rect.origin.x += CGRectGetWidth(rect);
  }
  return rect;
}

@end

@interface FBWindowTilingStrategy_IsolatedRegion : NSObject <FBSimulatorWindowTilingStrategy>

@property (nonatomic, assign, readwrite) NSInteger offset;
@property (nonatomic, assign, readwrite) NSInteger total;


@end

@implementation FBWindowTilingStrategy_IsolatedRegion

- (CGRect)targetPositionOfWindowWithSize:(CGSize)windowSize inScreenSize:(CGSize)screenSize withError:(NSError **)error
{
  if (self.total < 1) {
    return [[FBSimulatorError describe:@"Cannot Tile with total < 1"] failRect:error];
  }
  if (self.offset >= self.total) {
    return [[FBSimulatorError describe:@"Cannot Tile with offset >= total"] failRect:error];
  }

  return CGRectMake (
    floor((screenSize.width / self.total) * self.offset),
    0,
    windowSize.width,
    windowSize.height
  );
}

@end

@implementation FBSimulatorWindowTilingStrategy

+ (id<FBSimulatorWindowTilingStrategy>)horizontalOcclusionStrategy:(FBSimulator *)targetSimulator;
{
  FBWindowTilingStrategy_HorizontalOcclusion *strategy = [FBWindowTilingStrategy_HorizontalOcclusion new];
  strategy.targetSimulator = targetSimulator;
  return strategy;
}

+ (id<FBSimulatorWindowTilingStrategy>)isolatedRegionStrategyWithOffset:(NSInteger)offset total:(NSInteger)total
{
  FBWindowTilingStrategy_IsolatedRegion *strategy = [FBWindowTilingStrategy_IsolatedRegion new];
  strategy.offset = offset;
  strategy.total = total;
  return strategy;
}

@end
