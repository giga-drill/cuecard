#!/bin/zsh
set -euo pipefail

if (( $# != 1 )); then
  print -u2 "Usage: $0 <captured-log>"
  exit 64
fi

log_file=$1
if [[ ! -f "$log_file" ]]; then
  print -u2 "Log not found: $log_file"
  exit 66
fi

events=(
  sessionConfigured sessionActivated audioBuffer partialTranscript
  pipStarted appBackgrounded interruptionBegan routeChanged
  noBufferTimeout voiceAlignment fallbackToFixedSpeed error
)

print "Speech diagnostic event counts"
for event_name in $events; do
  count=$(rg -c "event=$event_name([[:space:]]|$)" "$log_file" 2>/dev/null || true)
  print "$event_name: ${count:-0}"
done

print ""
print "Ordered diagnostic lines"
rg '\[SpeechDiagnostics\]' "$log_file" || true
