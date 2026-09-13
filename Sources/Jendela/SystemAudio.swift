import AudioToolbox
import Combine
import CoreAudio
import Foundation

/// Real system volume and output device, driven entirely by CoreAudio property
/// listeners — the OS tells us when something changes, we never poll.
@MainActor
final class SystemAudio: ObservableObject {
    struct Device: Identifiable, Equatable {
        let id: AudioDeviceID
        let name: String
        var isDefault: Bool
    }

    @Published private(set) var volume: Float = 0
    @Published private(set) var isMuted = false
    @Published private(set) var devices: [Device] = []
    @Published private(set) var canSetVolume = false
    @Published private(set) var canSetMute = false
    @Published private(set) var error: String?

    private var deviceID = AudioDeviceID(0)
    private var listening: [(AudioObjectID, AudioObjectPropertyAddress)] = []
    private var deviceListeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    /// Set while we are writing, so our own change doesn't echo back as an update.
    private var isWriting = false

    init() {
        deviceID = Self.defaultOutputDevice()
        observeDefaultDeviceChanges()
        attachDeviceListeners()
        reload()
    }

    // Listeners live for the lifetime of the app; there is no correct way to
    // remove a block listener without retaining the exact block that was added.

    // MARK: - Public

    func setVolume(_ value: Float) {
        guard canSetVolume else { return }
        let clamped = max(0, min(1, value))
        volume = clamped
        isWriting = true
        defer { isWriting = false }
        guard deviceID != 0 else { return }
        var v = clamped
        var addr = Self.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        if AudioObjectHasProperty(deviceID, &addr) {
            report(AudioObjectSetPropertyData(deviceID, &addr, 0, nil, UInt32(MemoryLayout<Float>.size), &v))
            reload()
            return
        }
        // Some devices expose no main channel; write both stereo channels.
        for channel in UInt32(1)...UInt32(2) {
            var chAddr = Self.address(kAudioDevicePropertyVolumeScalar, element: channel)
            guard AudioObjectHasProperty(deviceID, &chAddr) else { continue }
            report(AudioObjectSetPropertyData(deviceID, &chAddr, 0, nil, UInt32(MemoryLayout<Float>.size), &v))
        }
        reload()
    }

    func setMuted(_ muted: Bool) {
        guard deviceID != 0, canSetMute else { return }
        var value: UInt32 = muted ? 1 : 0
        var addr = Self.address(kAudioDevicePropertyMute)
        guard AudioObjectHasProperty(deviceID, &addr) else { return }
        report(AudioObjectSetPropertyData(deviceID, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value))
        reload()
    }

    func selectDevice(_ id: AudioDeviceID) {
        var value = id
        var addr = Self.address(
            kAudioHardwarePropertyDefaultOutputDevice,
            scope: kAudioObjectPropertyScopeGlobal
        )
        report(AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil,
            UInt32(MemoryLayout<AudioDeviceID>.size), &value
        ))
    }

    var currentDeviceName: String {
        devices.first(where: { $0.isDefault })?.name ?? "Output"
    }

    // MARK: - Wiring

    private func observeDefaultDeviceChanges() {
        var addr = Self.address(
            kAudioHardwarePropertyDefaultOutputDevice,
            scope: kAudioObjectPropertyScopeGlobal
        )
        let system = AudioObjectID(kAudioObjectSystemObject)
        AudioObjectAddPropertyListenerBlock(system, &addr, DispatchQueue.main) { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.deviceID = Self.defaultOutputDevice()
                self.attachDeviceListeners()
                self.reload()
            }
        }
        listening.append((system, addr))

        var listAddr = Self.address(
            kAudioHardwarePropertyDevices,
            scope: kAudioObjectPropertyScopeGlobal
        )
        AudioObjectAddPropertyListenerBlock(system, &listAddr, DispatchQueue.main) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        listening.append((system, listAddr))
    }

    private func attachDeviceListeners() {
        for (id, address, block) in deviceListeners {
            var address = address
            AudioObjectRemovePropertyListenerBlock(id, &address, DispatchQueue.main, block)
        }
        deviceListeners.removeAll()
        guard deviceID != 0 else { return }
        let addresses = [Self.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume),
            Self.address(kAudioDevicePropertyMute), Self.address(kAudioDevicePropertyVolumeScalar, element: 1),
            Self.address(kAudioDevicePropertyVolumeScalar, element: 2)]
        for address in addresses {
            var addr = address
            guard AudioObjectHasProperty(deviceID, &addr) else { continue }
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                MainActor.assumeIsolated {
                    guard let self, !self.isWriting else { return }
                    self.reload()
                }
            }
            if AudioObjectAddPropertyListenerBlock(deviceID, &addr, DispatchQueue.main, block) == noErr {
                deviceListeners.append((deviceID, addr, block))
            }
        }
    }

    private func reload() {
        canSetVolume = settable(Self.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume))
            || settable(Self.address(kAudioDevicePropertyVolumeScalar, element: 1))
        canSetMute = settable(Self.address(kAudioDevicePropertyMute))
        volume = Self.readVolume(deviceID)
        isMuted = Self.readMuted(deviceID)
        devices = Self.outputDevices(defaultID: deviceID)
    }

    private func settable(_ address: AudioObjectPropertyAddress) -> Bool {
        var address = address
        var result: DarwinBoolean = false
        return AudioObjectIsPropertySettable(deviceID, &address, &result) == noErr && result.boolValue
    }

    private func report(_ status: OSStatus) {
        error = status == noErr ? nil : "This output did not accept the change (\(status))."
    }

    // MARK: - CoreAudio helpers

    private static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioDevicePropertyScopeOutput,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    private static func defaultOutputDevice() -> AudioDeviceID {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return id
    }

    private static func readVolume(_ device: AudioDeviceID) -> Float {
        guard device != 0 else { return 0 }
        var value: Float = 0
        var size = UInt32(MemoryLayout<Float>.size)
        var addr = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        if AudioObjectHasProperty(device, &addr),
           AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value) == noErr {
            return value
        }
        var chAddr = address(kAudioDevicePropertyVolumeScalar, element: 1)
        if AudioObjectHasProperty(device, &chAddr),
           AudioObjectGetPropertyData(device, &chAddr, 0, nil, &size, &value) == noErr {
            return value
        }
        return 0
    }

    private static func readMuted(_ device: AudioDeviceID) -> Bool {
        guard device != 0 else { return false }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var addr = address(kAudioDevicePropertyMute)
        guard AudioObjectHasProperty(device, &addr),
              AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value) == noErr
        else { return false }
        return value == 1
    }

    private static func outputDevices(defaultID: AudioDeviceID) -> [Device] {
        var size = UInt32(0)
        var addr = address(kAudioHardwarePropertyDevices, scope: kAudioObjectPropertyScopeGlobal)
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }

        return ids.compactMap { id in
            // Output-capable only: it must publish at least one output stream.
            var streamAddr = address(kAudioDevicePropertyStreams)
            var streamSize = UInt32(0)
            guard AudioObjectGetPropertyDataSize(id, &streamAddr, 0, nil, &streamSize) == noErr,
                  streamSize > 0 else { return nil }

            var nameAddr = address(kAudioObjectPropertyName, scope: kAudioObjectPropertyScopeGlobal)
            var name: Unmanaged<CFString>?
            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            guard AudioObjectGetPropertyData(id, &nameAddr, 0, nil, &nameSize, &name) == noErr,
                  let resolved = name?.takeRetainedValue() as String?
            else { return nil }
            return Device(id: id, name: resolved, isDefault: id == defaultID)
        }
    }
}
