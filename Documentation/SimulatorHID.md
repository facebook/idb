# Details about the Simulator.app and the HID System

The `SimulatorKit` and `CoreSimulator` Private Frameworks implement the vast majority of Simulator interactions that allow Simulators to be controlled from macOS. Being in a Shared Framework, means that this API is usable across Applications that are provided with the Xcode toolchain. `Xcode.app` (Device Organizer, Playgrounds), `xcodebuild`, `simctl` and `Simulator.app` are all downstream consumers of these Frameworks in one way or another.

The most notable exception to this rule is the sending of raw Human Interface Device (HID) events. A real-time protocol for sending of touch and keyboard events into the Simulator Runtime is essential for a responsive Simulator Application. Touches Down and Keys Down should be sent to the Simulator Runtime as soon as these events are received inside `Simulator.app`. Since `Simulator.app` is currently the only consumer of this API, it stands to reason that this behaviour has not been extracted to a Shared Framework. This means that understanding how HID events are sent and handled to a Simulator Runtime will require some investigation.

Note that a Real-Time API for sending events is distinct from Automation APIs such as `XCUITest` and `UIAutomation`. These APIs expose High-Level primitives for automated User-Interface testing. A Real-Time API for sending HID events much lower-level. Indeed the automation APIs eventually synthesize raw HID events after inspecting the UI Hierarchy. Having a usable API for sending HID events to Simulator Runtime is that is desirable for `FBSimulatorControl`. This document is a description of how HID events work inside Simulators.

## `Simulator.app` and Indigo

Due to a prior bug in Xcode, the existence of `Indigo` was already known about. [`FBSimulatorHID`](../FBSimulatorControl/Management/FBSimulatorHID.m) has to create a Mach Port when booting a Simulator headlessly, otherwise automation APIs such as `XCUITest` or `UIAutomation` will fail to synthesize Touch Events. This also shows that at some-level a usable HID System was needed for the high-level Automation APIs to work. This suggests that the `IndigoHIDRegistrationPort` is important in sending events to a Simulator. This port must also be registered with the `SimDevice` so that it can be used be the Simulator Runtime when it is booted.

The usage of `Indigo` can be seen be inspecting the disassembly for `Simulator.app`'s executable. There are a number callers of `-[GuiController sendIndigoHIDData:]`:

```
-[GuiController homeButtonPressed:]
-[GuiController sideButtonPressed:]
-[GuiController siriButtonPressed:]
..
-[DeviceWindow sendScrollEvent:]
-[DeviceWindow sendKeyboardEvent:]
```

Objective-C does encode the shape of structures passed to Objective-C Methods in the executable [using the same encoding as is used in `@encode`](https://developer.apple.com/library/content/documentation/Cocoa/Conceptual/ObjCRuntimeGuide/Articles/ocrtTypeEncodings.html). You can see this for yourself by dumping the sections of the Simulator's executable:

```
otool -ov /Applications/Xcode.app/Contents/Developer/Applications/Simulator.app/Contents/MacOS/Simulator | grep -A 1 sendIndigoHID
```

`class-dump` is capable of reconstructing this ecoding into a `struct`ure definition for a [C Header](../PrivateHeaders/SimulatorApp/Indigio.h). 

Following the path that this argument takes in the code, we can see that it eventually gets passed in to `mach_msg_send`. `mach_msg_send` takes a c-struct that has a `mach_msg_header_t` at the head of the structure. The structures that are sent in a `mach_msg_send` are typically specified in a `.defs` file, which is like a schema for the data to be sent. This is typically converted to a standard c-struct definition using the Mach Interface Generator. As this all gets compiled into the `Simulator.app` executable, all we can observe that is being sent in `mach_msg_send` is raw memory, without any headers to interpret it.

Since we do not have access to this `.defs` file, we will have to figure out what the contents of this memory actually means. However, there is sufficient metadata in the `Simulator.app` executable that can be extracted with `class-dump`. By looking at how the memory of the Indigo message set in the `Simulator.app` we can start to make some conclusions about what some of the fields in the structure actually mean. This is located [in the `Indigo.h` header](../PrivateHeaders/SimulatorApp/Indigo.h), which is derived from `class-dump`, but with annotations about fields and memory addresses.

## The Indigo Recipient

The `Simulator.app` sending Indigo Messages in Mach explains how HID events in the Mac `Simulator.app` are sent. For this to make meaningful interactions in the Simulator Runtime, there must be a recipient. In the `SimulatorHIDFallback.framework` there is a section that looks a little like:

```
mach_port_t port port;
if (bootstrap_look_up(bootstrap_port(), "IndigoHIDRegistrationPort", &port) != KERN_SUCCESS) {
  // Handle Failure
}
// Do something with the port
```

The `bootstrap` functions are a part of `launchd` that is used to register connections of `mach_port_t`'s without processes having to be directly aware of each other. It can help to think of this as a client-server relationship with the client being the `Simulator.app` and the server  being `SimulatorHIDFallback` running in `backboardd`.

With this relationship established, `SimulatorHIDFallback` can listen for incoming Indigo Messages with the `mach_msg` call. This can be seen in the dissasembly for a block in `-[SimulatorHIDFallbackSystem initUsingHIDService:error:]`. The code would look something like this at a high level:

```
// Make an IndigoMessage, this will be populated by mach_msg
IndigoMessage message;
// mach_msg will block, waiting for an incoming message and the call will return when one is available.
mach_msg(&message, sizeof(message), 0x0, port, 0x0, 0x0);
```

This data now has to be interpreted and sent to the underlying HID event system within the Simulator Runtime. Events are sent using the `IOKit.framework`. Parts of this API are public in macOS and there are also a number of Private Components that `SimulatorHIDFallback` uses. This can be seen further down the block:

```
// The IndigoMessage has a mach_msg_header at the top, we need to get to the contents of the message below it.
IndigoMessageContents contents = message.contents; // This is message+0x20, the size of the mach_msg_header_t
// There's always at least one message.
IOHIDEvent event = __IOHIDEventFromIndigoHIDData(contents, 0x2, 0x0);
// There can be more HID Events sent in a Single Indigo Message, so repeat on the array of events
while (event->hasNext) {
  contents++;
  IOHIDEvent nextEvent = __IOHIDEventFromIndigoHIDData(contents, 0x2, 0x0);
  // Update the original event by appending.
  IOHIDEventAppendEvent(event, nextEvent);
}
// Dispatch the event to the Event Service.
IOHIDServiceDispatchEvent(service, event);
```

The `__IOHIDEventFromIndigoHIDData` function is clearly quite important in tranforming `Indigo` messages into `IOHIDEvent` instances. The implementation of this function is also quite helpful in re-constructing an idea of what an Indigo message looks like. Inside the implementation of this transformation function there are number of conditionals that change the kind of `IOHIDEvent` (Keyboard/Touch) depending on the data passed in.

## Tracing with dtrace

Included in the `dtrace` [directory within this directory](dtrace) are a number of [`dtrace`](x-man-page://dtrace) scripts that demonstrate how messages are sent by `Simulator.app` and recieved by `backboardd`.

You can trace `Indigo` in the `Simulator.app` with the following command:

`dtrace/simulator_indigo -C /Applications/Xcode.app/Contents/Developer/Applications/Simulator.app`

