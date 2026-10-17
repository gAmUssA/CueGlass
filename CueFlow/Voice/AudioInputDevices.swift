import CoreAudio
import Foundation

/// One selectable microphone. `uid` is Core Audio's stable device UID, used for persistence;
/// device IDs change across reconnects and are resolved at capture time.
struct VoiceInputDeviceOption: Identifiable, Equatable, Sendable {
  let uid: String
  let name: String
  let isDefault: Bool
  var id: String { uid }
}

/// Resolves the microphone to use. A remembered device that is no longer attached falls back
/// to the system default rather than failing capture.
enum VoiceInputSelection {
  static func resolve(preferredUID: String?, available: [VoiceInputDeviceOption]) -> String? {
    guard let preferredUID, !preferredUID.isEmpty else { return nil }
    return available.contains(where: { $0.uid == preferredUID }) ? preferredUID : nil
  }
}

/// Read-only Core Audio queries for input-capable devices. Everything here is synchronous
/// and cheap; the system keeps the device list in memory.
enum AudioInputDeviceCatalog {
  static func inputDevices() -> [VoiceInputDeviceOption] {
    let defaultID = defaultInputDeviceID()
    return allDeviceIDs().compactMap { id in
      guard hasInputStreams(id), let uid = string(for: kAudioDevicePropertyDeviceUID, of: id),
        !uid.isEmpty
      else { return nil }
      let name = string(for: kAudioObjectPropertyName, of: id) ?? uid
      return VoiceInputDeviceOption(uid: uid, name: name, isDefault: id == defaultID)
    }
  }

  static func deviceID(forUID uid: String) -> AudioDeviceID? {
    allDeviceIDs().first { string(for: kAudioDevicePropertyDeviceUID, of: $0) == uid }
  }

  static func defaultInputDeviceID() -> AudioDeviceID? {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultInputDevice,
      mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var id = AudioDeviceID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    let status = AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
    return status == noErr && id != kAudioObjectUnknown ? id : nil
  }

  private static func allDeviceIDs() -> [AudioDeviceID] {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard
      AudioObjectGetPropertyDataSize(
        AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr, size > 0
    else { return [] }
    var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
    guard
      AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr
    else { return [] }
    return ids
  }

  private static func hasInputStreams(_ id: AudioDeviceID) -> Bool {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyStreams, mScope: kAudioObjectPropertyScopeInput,
      mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size > 0
  }

  private static func string(for selector: AudioObjectPropertySelector, of id: AudioDeviceID)
    -> String?
  {
    var address = AudioObjectPropertyAddress(
      mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    var size = UInt32(MemoryLayout<CFString?>.size)
    var value: CFString?
    let status = withUnsafeMutablePointer(to: &value) { pointer in
      AudioObjectGetPropertyData(id, &address, 0, nil, &size, pointer)
    }
    guard status == noErr, let value else { return nil }
    return value as String
  }
}

/// Reports attach, detach, and default-input changes on the main actor so the picker and the
/// capture source can react. The engine itself recovers through its configuration-change
/// notification; this observer only keeps the list and the remembered selection honest.
final class AudioInputDeviceObserver {
  private var addresses: [AudioObjectPropertyAddress]
  private let block: AudioObjectPropertyListenerBlock

  init(_ handler: @escaping @MainActor () -> Void) {
    addresses = [
      kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultInputDevice,
    ].map {
      AudioObjectPropertyAddress(
        mSelector: $0, mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    }
    let relay = MainActorRelay(handler)
    block = { _, _ in relay.fire() }
    for index in addresses.indices {
      AudioObjectAddPropertyListenerBlock(
        AudioObjectID(kAudioObjectSystemObject), &addresses[index], DispatchQueue.main, block)
    }
  }

  deinit {
    for index in addresses.indices {
      AudioObjectRemovePropertyListenerBlock(
        AudioObjectID(kAudioObjectSystemObject), &addresses[index], DispatchQueue.main, block)
    }
  }
}

private final class MainActorRelay: @unchecked Sendable {
  private let handler: @MainActor () -> Void
  init(_ handler: @escaping @MainActor () -> Void) { self.handler = handler }
  func fire() { Task { @MainActor in self.handler() } }
}
