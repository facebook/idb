use tokio::time::{sleep, Duration};
use tonic::{transport::Channel, Request, Status};
use futures::stream;
use std::env;

use crate::proto::*;
use crate::CompanionServiceClient;

pub async fn tap_at_coordinates(x: f64, y: f64) -> Result<(), Box<dyn std::error::Error>> {
    println!("Manual Tap Mode");
    println!("===============");
    
    // Connect to idb_companion
    let channel = Channel::from_static("http://localhost:10882")
        .connect()
        .await?;
    let mut client = CompanionServiceClient::new(channel);
    println!("Connected to idb_companion");
    
    println!("Tapping at ({}, {})", x, y);
    
    // Send touch down
    let down_event = HidEvent {
        event: Some(crate::proto::hid_event::Event::Press(HidPress {
            action: Some(HidPressAction {
                action: Some(crate::proto::hid_press_action::Action::Touch(HidTouch {
                    point: Some(Point { x, y }),
                })),
            }),
            direction: HidDirection::Down as i32,
        })),
    };
    
    let down_stream = stream::once(async move { down_event });
    client.hid(Request::new(down_stream)).await?;
    
    // Small delay
    sleep(Duration::from_millis(50)).await;
    
    // Send touch up
    let up_event = HidEvent {
        event: Some(crate::proto::hid_event::Event::Press(HidPress {
            action: Some(HidPressAction {
                action: Some(crate::proto::hid_press_action::Action::Touch(HidTouch {
                    point: Some(Point { x, y }),
                })),
            }),
            direction: HidDirection::Up as i32,
        })),
    };
    
    let up_stream = stream::once(async move { up_event });
    client.hid(Request::new(up_stream)).await?;
    
    println!("✓ Tap completed");
    
    Ok(())
}

pub async fn run_manual_mode() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<String> = env::args().collect();
    
    if args.len() != 3 {
        eprintln!("Usage: {} <x> <y>", args[0]);
        eprintln!("Example: {} 150 300", args[0]);
        return Ok(());
    }
    
    let x: f64 = args[1].parse()?;
    let y: f64 = args[2].parse()?;
    
    tap_at_coordinates(x, y).await
}