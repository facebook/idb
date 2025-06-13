use tokio::time::{sleep, Duration};
use tonic::transport::Channel;

pub mod idb {
    tonic::include_proto!("idb");
}

use idb::companion_service_client::CompanionServiceClient;

#[derive(Debug, Clone)]
struct CalibrationTarget {
    x: f64,
    y: f64,
    name: &'static str,
}

impl CalibrationTarget {
    fn new(x: f64, y: f64, name: &'static str) -> Self {
        Self { x, y, name }
    }
}

async fn tap_target(
    client: &mut CompanionServiceClient<Channel>,
    target: &CalibrationTarget,
) -> Result<(), Box<dyn std::error::Error>> {
    println!("Tapping {} at ({}, {})", target.name, target.x, target.y);

    use futures::stream;
    
    // Create touch down event
    let touch_down = idb::HidEvent {
        event: Some(idb::hid_event::Event::Press(idb::hid_event::HidPress {
            action: Some(idb::hid_event::hid_press::HidPressAction {
                action: Some(idb::hid_event::hid_press::hid_press_action::Action::Touch(
                    idb::hid_event::hid_press::hid_press_action::HidTouch {
                        point: Some(idb::Point {
                            x: target.x,
                            y: target.y,
                        }),
                    }
                )),
            }),
            direction: idb::hid_event::HidDirection::Down as i32,
        })),
    };
    
    // Small delay to simulate human touch
    sleep(Duration::from_millis(50)).await;
    
    // Create touch up event
    let touch_up = idb::HidEvent {
        event: Some(idb::hid_event::Event::Press(idb::hid_event::HidPress {
            action: Some(idb::hid_event::hid_press::HidPressAction {
                action: Some(idb::hid_event::hid_press::hid_press_action::Action::Touch(
                    idb::hid_event::hid_press::hid_press_action::HidTouch {
                        point: Some(idb::Point {
                            x: target.x,
                            y: target.y,
                        }),
                    }
                )),
            }),
            direction: idb::hid_event::HidDirection::Up as i32,
        })),
    };
    
    // Send both events as a stream
    let events = vec![touch_down, touch_up];
    let stream = stream::iter(events);
    
    client.hid(stream).await?;
    
    println!("  ✓ Tapped {}", target.name);
    Ok(())
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    println!("IDB Calibration Tap Client");
    println!("==========================");
    
    // Connect to idb_companion using the static connect method
    let channel = Channel::from_static("http://localhost:10882").connect().await?;
    let mut client = CompanionServiceClient::new(channel);
    println!("Connected to idb_companion");
    
    // Define calibration targets based on the screenshot
    // These are approximate coordinates for iPhone 16 Pro Max (430x932 points)
    // Adjusted based on the percentage positions shown in the screenshot
    let targets = vec![
        CalibrationTarget::new(86.0, 186.0, "Target 1 (Top-left, 20%, 20%)"),
        CalibrationTarget::new(344.0, 186.0, "Target 2 (Top-right, 80%, 20%)"),
        CalibrationTarget::new(215.0, 559.0, "Target 3 (Center, 50%, 60%)"),
        CalibrationTarget::new(86.0, 746.0, "Target 4 (Bottom-left, 20%, 80%)"),
        CalibrationTarget::new(344.0, 746.0, "Target 5 (Bottom-right, 80%, 80%)"),
    ];
    
    println!("\nStarting calibration sequence...\n");
    
    // Tap each target with a delay between taps
    for (i, target) in targets.iter().enumerate() {
        tap_target(&mut client, target).await?;
        
        if i < targets.len() - 1 {
            println!("  Waiting 1 second before next tap...");
            sleep(Duration::from_secs(1)).await;
        }
    }
    
    println!("\n✅ Calibration complete! All 5 targets tapped.");
    
    Ok(())
}