#import <XCTestPrivate/XCTMessagingRole_ProcessMonitoring-Protocol.h>
#import <XCTestPrivate/XCTMessagingRole_TestExecution-Protocol.h>
#import <XCTestPrivate/XCTMessagingRole_TestExecution_Legacy-Protocol.h>
#import <XCTestPrivate/_XCTMessaging_VoidProtocol-Protocol.h>

@protocol XCTMessagingChannel_IDEToRunner <XCTMessagingRole_TestExecution, XCTMessagingRole_TestExecution_Legacy, XCTMessagingRole_ProcessMonitoring, _XCTMessaging_VoidProtocol>

@optional
- (void)__dummy_method_to_work_around_68987191;
@end

