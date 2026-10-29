#!/bin/bash
set -euo pipefail
# Run the actual app-linked Swift Testing bundle without LaunchServices' launcher.
main() {
  local repo_root developer_dir products
  repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  cd "$repo_root"
  pwd
  developer_dir="$(xcode-select -p)"
  products="$repo_root/.build/Xcode/Build/Products/DebugLocal"
  xcodebuild -project CueFlow.xcodeproj -scheme CueFlow -configuration DebugLocal \
    -destination 'platform=macOS' -derivedDataPath .build/Xcode build-for-testing
  CUEFLOW_EPHEMERAL=1 CUEFLOW_TEST_ROOT="$repo_root/.build/test-fixtures" \
    DYLD_LIBRARY_PATH="$products/CueGlass.app/Contents/MacOS:$developer_dir/Platforms/MacOSX.platform/Developer/usr/lib" \
    DYLD_FRAMEWORK_PATH="$products/PackageFrameworks:$developer_dir/Platforms/MacOSX.platform/Developer/Library/Frameworks" \
    "$developer_dir/usr/bin/xctest" "$products/CueFlowTests.xctest"
}
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
