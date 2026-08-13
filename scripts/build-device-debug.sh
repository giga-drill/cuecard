#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
repo_root=${script_dir:h}
project_dir="$repo_root/cuecard-mobile/ios/CueCard"
output_dir=${1:-/tmp/cuecard-device-debug}
derived_data_dir="$output_dir/DerivedData"
product_dir="$output_dir/Product"

mkdir -p "$output_dir"
xcodebuild \
  -project "$project_dir/CueCard.xcodeproj" \
  -scheme CueCard \
  -configuration Debug \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$derived_data_dir" \
  CODE_SIGNING_ALLOWED=NO \
  CONFIGURATION_BUILD_DIR="$product_dir" \
  build

print "Unsigned arm64 debug build: $product_dir/CueCard.app"
print "Installation still requires an Apple Development team configured in Xcode."
