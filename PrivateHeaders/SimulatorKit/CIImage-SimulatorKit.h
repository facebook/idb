/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <CoreImage/CIImage.h>

@interface CIImage (SimulatorKit)
- (id)imageRepresentationWithType:(unsigned long long)arg1;
- (id)bitmapRepresentation;
@end
