#!/bin/bash
set -euo pipefail
# PROVISIONAL check of the ReleaseAppStore configuration (ADR 0016; entitlements from proposed ADR 0015).
# Builds the configuration unsigned, then asserts bundle id, entitlement keys, hardened runtime and Info.plist keys.
# An unsigned build embeds no entitlements, so the entitlements file is read from CODE_SIGN_ENTITLEMENTS.
# Signing, notarization and App Store validation are NOT checked here (owner-only).
EXPECTED_BUNDLE_ID="io.gamov.cueglass"
EXPECTED_KEYS=$'com.apple.security.app-sandbox\ncom.apple.security.device.audio-input\ncom.apple.security.files.user-selected.read-write'

fail() {
  echo "FAIL: $*" >&2
  return 1
}

# Succeeds only when the entitlements file holds exactly the three expected keys, each true.
check_entitlements() {
  local file="$1" keys key value
  [[ -f "$file" ]] || { fail "entitlements file not found: $file — check CODE_SIGN_ENTITLEMENTS in Configuration/AppStore.xcconfig"; return 1; }
  keys="$(plutil -p "$file" | sed -n 's/^  "\(.*\)" => .*/\1/p' | sort)" \
    || { fail "cannot read $file as a property list"; return 1; }
  if [[ "$keys" != "$EXPECTED_KEYS" ]]; then
    fail "entitlement keys in $file differ from the expected three (get-task-allow and extras are rejected). Got:"$'\n'"$keys"
    return 1
  fi
  while IFS= read -r key; do
    value="$(/usr/libexec/PlistBuddy -c "Print :$key" "$file")"
    [[ "$value" == "true" ]] || { fail "$key is $value, expected true"; return 1; }
  done <<<"$EXPECTED_KEYS"
}

setting() {
  # Reads one build setting from the captured -showBuildSettings output.
  local name="$1" line
  line="$(grep -E "^ +${name} = " <<<"$SETTINGS" | head -n 1)" || { fail "build setting $name is not set"; return 1; }
  echo "${line#*= }"
}

expect_equal() {
  [[ "$2" == "$3" ]] || { fail "$1: expected '$3', got '$2'"; return 1; }
}

negative_cases() {
  local dir="$1" good="$2" bad
  mkdir -p "$dir"
  cp "$good" "$dir/extra.entitlements"
  /usr/libexec/PlistBuddy -c "Add :com.apple.security.network.client bool true" "$dir/extra.entitlements"
  cp "$good" "$dir/taskallow.entitlements"
  /usr/libexec/PlistBuddy -c "Add :com.apple.security.get-task-allow bool true" "$dir/taskallow.entitlements"
  cp "$good" "$dir/missing.entitlements"
  /usr/libexec/PlistBuddy -c "Delete :com.apple.security.device.audio-input" "$dir/missing.entitlements"
  for bad in extra taskallow missing; do
    if check_entitlements "$dir/$bad.entitlements" 2>/dev/null; then
      fail "negative case '$bad' was accepted; the entitlement check is broken"
      return 1
    fi
    echo "ok: rejected $bad entitlements"
  done
}

main() {
  local repo_root products app entitlements plist
  repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  cd "$repo_root"
  pwd
  SETTINGS="$(xcodebuild -project CueFlow.xcodeproj -scheme CueFlow -configuration ReleaseAppStore \
    -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/AppStore -showBuildSettings)"
  expect_equal "PRODUCT_BUNDLE_IDENTIFIER" "$(setting PRODUCT_BUNDLE_IDENTIFIER)" "$EXPECTED_BUNDLE_ID"
  expect_equal "ENABLE_HARDENED_RUNTIME" "$(setting ENABLE_HARDENED_RUNTIME)" "YES"
  expect_equal "CODE_SIGN_INJECT_BASE_ENTITLEMENTS" "$(setting CODE_SIGN_INJECT_BASE_ENTITLEMENTS)" "NO"
  expect_equal "CODE_SIGN_ENTITLEMENTS" "$(setting CODE_SIGN_ENTITLEMENTS)" "CueFlow/Resources/CueFlow-AppStore.entitlements"
  entitlements="$repo_root/$(setting CODE_SIGN_ENTITLEMENTS)"
  check_entitlements "$entitlements"
  echo "ok: entitlements are exactly the three provisional keys"
  negative_cases "$repo_root/.build/app-store-config-negative" "$entitlements"

  xcodebuild -project CueFlow.xcodeproj -scheme CueFlow -configuration ReleaseAppStore \
    -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/AppStore \
    CODE_SIGNING_ALLOWED=NO build >/dev/null
  products="$repo_root/.build/AppStore/Build/Products/ReleaseAppStore"
  app="$products/CueGlass.app"
  plist="$app/Contents/Info.plist"
  expect_equal "CFBundleIdentifier" "$(plutil -extract CFBundleIdentifier raw "$plist")" "$EXPECTED_BUNDLE_ID"
  expect_equal "LSApplicationCategoryType" "$(plutil -extract LSApplicationCategoryType raw "$plist")" "public.app-category.productivity"
  expect_equal "ITSAppUsesNonExemptEncryption" "$(plutil -extract ITSAppUsesNonExemptEncryption raw "$plist")" "false"
  plutil -extract NSMicrophoneUsageDescription raw "$plist" >/dev/null \
    || { fail "NSMicrophoneUsageDescription is missing from the built Info.plist"; return 1; }
  echo "PASS: ReleaseAppStore configuration (unsigned build; signing and App Store validation NOT RUN)"
}
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
