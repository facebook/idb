// Manual proto definitions to work around the conflicting definitions in idb.proto

use prost::Message;

#[derive(Clone, PartialEq, Message)]
pub struct Point {
    #[prost(double, tag = "1")]
    pub x: f64,
    #[prost(double, tag = "2")]
    pub y: f64,
}

#[derive(Clone, PartialEq, Message)]
pub struct HidTouch {
    #[prost(message, optional, tag = "1")]
    pub point: Option<Point>,
}

#[derive(Clone, PartialEq, Message)]
pub struct HidPressAction {
    #[prost(oneof = "hid_press_action::Action", tags = "1")]
    pub action: Option<hid_press_action::Action>,
}

pub mod hid_press_action {
    #[derive(Clone, PartialEq, prost::Oneof)]
    pub enum Action {
        #[prost(message, tag = "1")]
        Touch(super::HidTouch),
    }
}

#[derive(Clone, PartialEq, Message)]
pub struct HidPress {
    #[prost(message, optional, tag = "1")]
    pub action: Option<HidPressAction>,
    #[prost(enumeration = "HidDirection", tag = "2")]
    pub direction: i32,
}

#[derive(Clone, PartialEq, Message)]
pub struct HidEvent {
    #[prost(oneof = "hid_event::Event", tags = "1")]
    pub event: Option<hid_event::Event>,
}

pub mod hid_event {
    #[derive(Clone, PartialEq, prost::Oneof)]
    pub enum Event {
        #[prost(message, tag = "1")]
        Press(super::HidPress),
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord, prost::Enumeration)]
#[repr(i32)]
pub enum HidDirection {
    Down = 0,
    Up = 1,
}

#[derive(Clone, PartialEq, Message)]
pub struct HidResponse {}

#[derive(Clone, PartialEq, Message)]
pub struct ScreenshotRequest {}

#[derive(Clone, PartialEq, Message)]
pub struct ScreenshotResponse {
    #[prost(bytes = "vec", tag = "1")]
    pub image_data: Vec<u8>,
    #[prost(string, tag = "2")]
    pub image_format: String,
}