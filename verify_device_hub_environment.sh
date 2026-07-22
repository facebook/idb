#!/bin/bash

set -euo pipefail

usage() {
  echo "usage: $0 --developer-dir <path> --udid <simulator-udid>" >&2
}

developer_dir=""
udid=""

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --developer-dir)
      developer_dir="${2:-}"
      shift 2
      ;;
    --udid)
      udid="${2:-}"
      shift 2
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

if [[ -z "$developer_dir" || -z "$udid" ]]; then
  usage
  exit 2
fi

if [[ ! -d "$developer_dir" ]]; then
  echo "error: developer directory does not exist: $developer_dir" >&2
  exit 2
fi

xcrun_path="$developer_dir/usr/bin/xcrun"
if [[ ! -x "$xcrun_path" ]]; then
  echo "error: xcrun not found under developer directory: $developer_dir" >&2
  exit 2
fi

devices_json="$(DEVELOPER_DIR="$developer_dir" "$xcrun_path" simctl list devices available --json)"
device_json="$(jq -c --arg udid "$udid" '
  [.devices | to_entries[] as $runtime
    | $runtime.value[]
    | select(.udid == $udid)
    | . + {runtime_identifier: $runtime.key}]
  | first // empty
' <<<"$devices_json")"

if [[ -z "$device_json" ]]; then
  echo "error: simulator is not available in the selected Xcode: $udid" >&2
  exit 1
fi

runtime_identifier="$(jq -r '.runtime_identifier' <<<"$device_json")"
runtimes_json="$(DEVELOPER_DIR="$developer_dir" "$xcrun_path" simctl list runtimes --json)"
runtime_json="$(jq -c --arg identifier "$runtime_identifier" '
  [.runtimes[] | select(.identifier == $identifier)] | first // {}
' <<<"$runtimes_json")"

xcode_version="$(DEVELOPER_DIR="$developer_dir" xcodebuild -version | awk 'NR == 1 { print $2 }')"
xcode_build="$(DEVELOPER_DIR="$developer_dir" xcodebuild -version | awk '/Build version/ { print $3 }')"
runtime_version="$(jq -r '.version // "unknown"' <<<"$runtime_json")"
runtime_build="$(jq -r '.buildversion // "unknown"' <<<"$runtime_json")"
device_name="$(jq -r '.name' <<<"$device_json")"
device_state="$(jq -r '.state' <<<"$device_json")"

xcode_app="${developer_dir%/Contents/Developer}"
device_hub_path="$xcode_app/Contents/Applications/DeviceHub.app"
if [[ -d "$device_hub_path" ]]; then
  device_hub_available=true
else
  device_hub_available=false
fi

if pgrep -x Simulator >/dev/null; then
  simulator_app_running=true
else
  simulator_app_running=false
fi

if pgrep -f "$device_hub_path/Contents/MacOS/DeviceHub" >/dev/null 2>&1; then
  device_hub_running=true
else
  device_hub_running=false
fi

jq -n \
  --arg xcode_version "$xcode_version" \
  --arg xcode_build "$xcode_build" \
  --arg developer_dir "$developer_dir" \
  --arg udid "$udid" \
  --arg device_name "$device_name" \
  --arg device_state "$device_state" \
  --arg runtime_identifier "$runtime_identifier" \
  --arg runtime_version "$runtime_version" \
  --arg runtime_build "$runtime_build" \
  --argjson device_hub_available "$device_hub_available" \
  --argjson device_hub_running "$device_hub_running" \
  --argjson simulator_app_running "$simulator_app_running" \
  '{
    xcode: {
      version: $xcode_version,
      build: $xcode_build,
      developer_dir: $developer_dir
    },
    simulator: {
      udid: $udid,
      name: $device_name,
      state: $device_state,
      runtime_identifier: $runtime_identifier,
      runtime_version: $runtime_version,
      runtime_build: $runtime_build
    },
    host: {
      device_hub_available: $device_hub_available,
      device_hub_running: $device_hub_running,
      simulator_app_running: $simulator_app_running
    }
  }'
