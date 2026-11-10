import CoreAudio
import Foundation

/// Reads the default output device's volume, mute state and name. Writing during a gesture goes
/// through `VolumeWriter`, off the main thread.
@MainActor
final class SystemVolume {

    /// 'vmvc': the virtual main volume, the same scalar the volume keys drive.
    private static let virtualMainVolume: AudioObjectPropertySelector = 0x766D_7663
    private static let muteSelector: AudioObjectPropertySelector = 0x6D75_7465

    var volume: Float { scalar(for: Self.virtualMainVolume) ?? 0 }

    var isMuted: Bool { (integer(for: Self.muteSelector) ?? 0) != 0 }

    /// The output device's name ("MacBook Pro Speakers", headphones…), shown by indicators that
    /// name the device the way macOS does.
    var deviceName: String {
        let id = defaultDevice()
        guard id != kAudioObjectUnknown else { return "Sound" }
        var addr = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &name) == noErr,
              let value = name?.takeRetainedValue() as String?, !value.isEmpty else { return "Sound" }
        return value
    }

    // MARK: - Device plumbing

    private func defaultDevice() -> AudioDeviceID {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &addr, 0, nil, &size, &id) == noErr else { return kAudioObjectUnknown }
        return id
    }

    private func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector,
                                   mScope: kAudioDevicePropertyScopeOutput,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private func scalar(for selector: AudioObjectPropertySelector) -> Float? {
        let id = defaultDevice()
        guard id != kAudioObjectUnknown else { return nil }
        var addr = address(selector)
        guard AudioObjectHasProperty(id, &addr) else { return nil }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private func integer(for selector: AudioObjectPropertySelector) -> UInt32? {
        let id = defaultDevice()
        guard id != kAudioObjectUnknown else { return nil }
        var addr = address(selector)
        guard AudioObjectHasProperty(id, &addr) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }
}
