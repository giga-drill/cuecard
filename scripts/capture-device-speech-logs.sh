#!/bin/zsh
set -euo pipefail

if (( $# < 1 )); then
  print -u2 "Usage: $0 <device-id-or-name> [output-log]"
  exit 64
fi

device_id=$1
script_dir=${0:A:h}
repo_root=${script_dir:h}
timestamp=$(date '+%Y%m%d-%H%M%S')
output_log=${2:-"$repo_root/artifacts/device-tests/speech-$timestamp.log"}

mkdir -p "${output_log:h}"
print "Capturing CueCard diagnostics to: $output_log"
print "Leave this running, perform the checklist on the iPhone, then press Control-C."

xcrun devicectl device process launch \
  --device "$device_id" \
  --terminate-existing \
  --console \
  com.gigadrill.cuecard 2>&1 | tee "$output_log"
