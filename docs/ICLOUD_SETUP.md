# iCloud owner setup

DebugLocal/ReleaseLocal use ad hoc signing with app sandbox and user-selected read/write access only. Their container identifier is empty; integrated iCloud is not configured. Saving to a user-selected Finder iCloud location in local mode does not enable or prove integrated container behavior.

Owner steps (not performed by this assignment):

1. Register a real bundle identifier and iCloud Documents container in your Apple Developer account. Enable iCloud Documents for the app ID and include the container in its provisioning profile. Sign into the same iCloud Drive account on both test Macs. Do not commit credentials or provisioning files.
2. Copy `Configuration/Owner.xcconfig.example` to `Configuration/Owner.xcconfig`. Supply DEVELOPMENT_TEAM, PRODUCT_BUNDLE_IDENTIFIER and CUEFLOW_ICLOUD_CONTAINER. These are owner values, not invented identifiers.
3. Copy `Configuration/Info-iCloud.plist.example` to `Configuration/Info-iCloud.plist`. Replace the literal `iCloud.your.bundle.cueflow` **dictionary key** under NSUbiquitousContainers with the exact registered container identifier. Keep the CueFlowICloudContainerIdentifier value as `$(CUEFLOW_ICLOUD_CONTAINER)`; Xcode expands that string value. The separate plist avoids relying on expansion of dictionary keys. Both owner files are gitignored.
4. Select DebugICloud in Xcode's scheme Run configuration, or build with `xcodebuild -project CueFlow.xcodeproj -scheme CueFlow -configuration DebugICloud -destination 'platform=macOS' -derivedDataPath .build/ICloud build`. Signing must be enabled with the owner's profile. The normal shared scheme defaults to DebugLocal.
5. Inspect the built Info.plist and signed entitlements with `plutil -p` and `codesign -d --entitlements :-`. The bundle's container string, NSUbiquitousContainers key, iCloud/ubiquity identifier arrays and registered provisioning container must agree. No network-client entitlement is required for iCloud Drive daemon transport.
6. Run the signed app. Save to iCloud discovers FileManager's entitled container, initializes the save panel in Documents, and invokes NSDocument save. A nil container leaves the document intact and shows an unavailable/local-save message. Do not hard-code a Mobile Documents path.

Locally available documents open/play offline. A cloud-only open requests download off main and reports that the user must reopen after download; it never prepares a partial snapshot. Refresh Status reads URL resource metadata, and presenter attribute callbacks refresh it automatically for open files. Uploaded to iCloud means server upload only, with no remote acknowledgment claim.

Account-change notifications preserve edits and advise Save a Copy. There is no silent migration or deletion. Conflicts are visible in status and handled first through NSDocument's Versions UI, with Save a Copy before resolving anything. No conflicting NSFileVersion is marked resolved or deleted by app code. If the actual OS Versions UI does not expose recoverable conflict versions, stop conflict testing and report that as a blocking recovery gap before distribution; scope an explicit non-destructive resolver separately.

A future-version file read during revert preserves the old model and blocks autosave/overwrite. Save a Copy uses `.saveToOperation` and can export the older in-memory model to a different path. Do not replace the future-version original.

Actual validation status: entitlement/plist source and API availability compiled; local mode/container-unconfigured test passed. No owner team/profile/container was supplied, no signed iCloud configuration built, and no two-Mac or real conflict results exist. Follow the exact cloud cases in MANUAL_TEST_PLAN.md before claiming R04 end-to-end validation.
