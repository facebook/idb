use tokio::time::{sleep, Duration};
use tonic::{transport::Channel, Request, Status};
use futures::stream;
use std::env;

mod proto;
use proto::*;

mod tap_manual;
mod screenshot;
mod automated_calibration;

// Manual gRPC service client
pub struct CompanionServiceClient {
    inner: tonic::client::Grpc<Channel>,
}

impl CompanionServiceClient {
    pub fn new(channel: Channel) -> Self {
        let inner = tonic::client::Grpc::new(channel);
        Self { inner }
    }

    pub async fn hid(
        &mut self,
        request: impl tonic::IntoStreamingRequest<Message = HidEvent>,
    ) -> Result<tonic::Response<HidResponse>, Status> {
        self.inner.ready().await.map_err(|e| {
            Status::new(
                tonic::Code::Unknown,
                format!("Service was not ready: {}", e),
            )
        })?;
        let codec = tonic::codec::ProstCodec::default();
        let path = http::uri::PathAndQuery::from_static("/idb.CompanionService/hid");
        let req = request.into_streaming_request();
        self.inner.client_streaming(req, path, codec).await
    }
}

#[derive(Debug, Clone)]
pub struct CalibrationTarget {
    pub x: f64,
    pub y: f64,
    pub name: &'static str,
}

impl CalibrationTarget {
    pub fn new(x: f64, y: f64, name: &'static str) -> Self {
        Self { x, y, name }
    }
}

async fn send_tap(
    client: &mut CompanionServiceClient,
    x: f64,
    y: f64,
    direction: i32,
) -> Result<(), Box<dyn std::error::Error>> {
    let event = HidEvent {
        event: Some(hid_event::Event::Press(HidPress {
            action: Some(HidPressAction {
                action: Some(hid_press_action::Action::Touch(HidTouch {
                    point: Some(Point { x, y }),
                })),
            }),
            direction,
        })),
    };
    
    let stream = stream::once(async move { event });
    let request = Request::new(stream);
    
    client.hid(request).await?;
    Ok(())
}

pub async fn tap_target(
    client: &mut CompanionServiceClient,
    target: &CalibrationTarget,
) -> Result<(), Box<dyn std::error::Error>> {
    println!("Tapping {} at ({:.0}, {:.0})", target.name, target.x, target.y);
    
    // Send touch down
    send_tap(client, target.x, target.y, HidDirection::Down as i32).await?;
    
    // Small delay to simulate human touch
    sleep(Duration::from_millis(50)).await;
    
    // Send touch up
    send_tap(client, target.x, target.y, HidDirection::Up as i32).await?;
    
    println!("  ✓ Sent tap to {}", target.name);
    Ok(())
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Check for command line arguments
    let args: Vec<String> = env::args().collect();
    if args.len() > 1 {
        match args[1].as_str() {
            "--auto" => return automated_calibration::run_automated_calibration().await,
            x if args.len() == 3 => return tap_manual::run_manual_mode().await,
            _ => {
                println!("Usage: {} [--auto | <x> <y>]", args[0]);
                println!("  --auto       Run automated calibration with screenshots");
                println!("  <x> <y>      Tap at specific coordinates");
                println!("  (no args)    Run standard calibration");
                return Ok(());
            }
        }
    }
    
    println!("IDB Calibration Tap Client");
    println!("==========================");
    
    // Connect to idb_companion
    let channel = Channel::from_static("http://localhost:10882")
        .connect()
        .await?;
    let mut client = CompanionServiceClient::new(channel);
    println!("Connected to idb_companion on localhost:10882");
    
    // Based on tap history analysis:
    // 1. Y coordinates are inverted (screen_height - y)
    // 2. There's an additional offset of ~62 pixels
    // This is likely due to screenshot scaling or status bar height
    
    let screen_height = 800.0;
    let y_offset = 62.0; // Observed offset from tap history
    
    let targets = vec![
        CalibrationTarget::new(88.0, screen_height - 172.0 + y_offset, "Target 1 (Top-left)"),
        CalibrationTarget::new(352.0, screen_height - 172.0 + y_offset, "Target 2 (Top-right)"),
        CalibrationTarget::new(220.0, screen_height - 430.0 + y_offset, "Target 3 (Center)"),
        CalibrationTarget::new(88.0, screen_height - 688.0 + y_offset, "Target 4 (Bottom-left)"),
        CalibrationTarget::new(352.0, screen_height - 688.0 + y_offset, "Target 5 (Bottom-right)"),
    ];
    
    println!("\nStarting calibration sequence...");
    println!("Targets at exact coordinates from app\n");
    
    // Wait a moment before starting
    println!("Starting in 2 seconds...");
    sleep(Duration::from_secs(2)).await;
    
    // Tap each target with a delay between taps
    for (i, target) in targets.iter().enumerate() {
        tap_target(&mut client, target).await?;
        
        if i < targets.len() - 1 {
            println!("  Waiting 1.5 seconds before next tap...");
            sleep(Duration::from_millis(1500)).await;
        }
    }
    
    println!("\n✅ Calibration sequence complete!");
    println!("Check the app to see if all 5 targets were hit.");
    
    Ok(())
}