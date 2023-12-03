#import "XCTMessagingRole_ControlSessionInitiation-Protocol.h"
#import "XCTMessagingRole_DiagnosticsCollection-Protocol.h"
#import "XCTMessagingRole_RunnerSessionInitiation-Protocol.h"
#import "XCTMessagingRole_UIRecordingControl-Protocol.h"
#import "_XCTMessaging_VoidProtocol-Protocol.h"

@protocol XCTMessagingChannel_IDEToDaemon <XCTMessagingRole_RunnerSessionInitiation, XCTMessagingRole_ControlSessionInitiation, XCTMessagingRole_UIRecordingControl, XCTMessagingRole_DiagnosticsCollection, _XCTMessaging_VoidProtocol>

@optional
- (void)__dummy_method_to_work_around_68987191;
@end

