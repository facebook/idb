/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <AppKit/NSView.h>

@class CALayer;
@protocol SimDeviceIOProtocol, _TtP12SimulatorKit32SimDisplayRenderableViewDelegate_;

@interface _TtC12SimulatorKit24SimDisplayRenderableView : NSView
{
    // Error parsing type: , name: surfaceLayer
    // Error parsing type: , name: displayClass
    // Error parsing type: , name: io
    // Error parsing type: , name: displaySize
    // Error parsing type: , name: delegate
    // Error parsing type: , name: _uuid
    // Error parsing type: , name: _queue
    // Error parsing type: , name: _port
    // Error parsing type: , name: _ioSurface
    // Error parsing type: , name: displayAngle
}

- (CDUnknownBlockType).cxx_destruct;
- (void)changeDisplayWithSize:(struct CGSize)arg1 scale:(double)arg2 completionQueue:(id)arg3 completion:(CDUnknownBlockType)arg4;
- (void)resetWithCompletionQueue:(id)arg1 completion:(CDUnknownBlockType)arg2;
- (void)setupWithIo:(id)arg1 displayClass:(unsigned short)arg2 completionQueue:(id)arg3 completion:(CDUnknownBlockType)arg4;
- (void)setupWithIo:(id)arg1 displayClass:(unsigned short)arg2 completion:(CDUnknownBlockType)arg3;
- (void)setupWithIo:(id)arg1 displayClass:(unsigned short)arg2;
- (id)takeScreenshotWithFileType:(unsigned long long)arg1;
- (void)setFrameSize:(struct CGSize)arg1;
- (void)setBoundsSize:(struct CGSize)arg1;
@property (nonatomic, readonly) NSView *nextValidKeyView;
@property (nonatomic, readonly) BOOL mouseDownCanMoveWindow;
@property (nonatomic, readonly) BOOL wantsUpdateLayer;
@property (nonatomic, assign) double displayAngle;
@property (nonatomic, weak) id <_TtP12SimulatorKit32SimDisplayRenderableViewDelegate_> delegate;
@property (nonatomic, retain) id<SimDeviceIOProtocol> io;
@property (nonatomic, assign) unsigned short displayClass;
@property (nonatomic, retain) CALayer *surfaceLayer;
- (void)dealloc;
- (id)initWithCoder:(id)arg1;
- (void)awakeFromNib;
- (id)initWithFrame:(struct CGRect)arg1;

@end
