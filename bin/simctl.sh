#!/usr/bin/env bash

set +e

source bin/log.sh

# Force Xcode 8 CoreSimulator env to be loaded so xcodebuild does not fail.

function ensure_valid_core_sim_service {
  info "Ensuring there is a valid CoreSimulatorService"
	for try in {1..4}; do
    local valid=$(valid_core_sim_service)
    if [ "${valid}" = "false" ]; then
      info "Trying again to ensure valid CoreSimulatorService"
      sleep 1.0
    else
      info "CoreSimulatorService is valid"
      break
    fi
	done
}

function valid_core_sim_service {
  local tmp_file=$(mktemp)
  xcrun simctl help >> "${tmp_file}"

  if [ "$?" != "0" ]; then
    echo -n "false"
  elif grep -q "Failed to location valid instance of CoreSimulatorService" "${tmp_file}"; then
    echo -n "false"
  elif grep -q "CoreSimulatorService connection became invalid" "${tmp_file}"; then
    echo -n "false"
  else
    echo -n "true"
  fi
}
