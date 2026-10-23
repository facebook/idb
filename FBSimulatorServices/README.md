# FBSimulatorServices

Changes state inside a booted iOS Simulator that no `simctl` verb reaches, by running idb's `SimulatorFrameworkBridge` helper inside it. It is added onto `Simulator` from outside [`FBSimulatorControl`](../FBSimulatorControl/README.md): a consumer that uses none of it neither links it nor ships the helper.

It adds these commands to `Simulator`:

| Command | What it does |
| --- | --- |
| `contacts` | Replaces the contacts database from a file, or clears it |
| `photos` | Clears the photo library |
| `health` | Grants, revokes, lists and clears an application's HealthKit authorizations |
| `notification` | Sends a push notification, and lists and clears an application's delivered notifications |
| `privacy` | Grants and revokes privacy permissions (TCC), including location |
| `network` | Sets, lists and clears the proxy and DNS configuration |
| `preferences` | Applies settings (`SimulatorSetting`): appearance, Dynamic Type, accessibility, keyboard, and raw preferences |
| `orientation` | Reads and sets the physical device orientation, confirming that a change took effect |
| `lockScreen` | Reads SpringBoard's lock state, and locks and unlocks the device through SpringBoard rather than the lock button's toggle |

Each of these runs some or all of its work in the helper; the rest writes the Simulator's data directory or its defaults directly, and writing an orientation goes through the Simulator's HID services. The helper is staged and spawned on demand and talks to the host over a Unix domain socket. The connection is held per Simulator and reused, so a warm call does not pay to start the helper again. [`FBSimulatorAX`](../FBSimulatorAX/README.md) reads accessibility through the same helper, and [`FBSimulatorCodeInjection`](../FBSimulatorCodeInjection/README.md) starts the Simulator-wide REPL through it.

## Resources

The helper, `SimulatorFrameworkBridge-iOS` (and `-tvOS` for tvOS Simulators), is a resource of this library. It is a Simulator binary signed for the Simulator, and must be shipped as it is, without re-signing. Point `BundledResources.hostDirectoryPath` at the directory you copy it to, as described in [FBSimulatorControl's resources section](../FBSimulatorControl/README.md#resources). Contacts, Health and delivered notifications are not available on tvOS, whose SDK lacks those frameworks, and the lock screen is not available on tvOS or watchOS, which have no SpringBoard.
