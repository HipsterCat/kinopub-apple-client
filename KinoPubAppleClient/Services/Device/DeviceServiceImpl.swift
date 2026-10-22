//
//  DeviceServiceImpl.swift
//  KinoPubAppleClient
//

import Foundation
import KinoPubBackend
import OSLog
import KinoPubLogging

final class DeviceServiceImpl: DeviceService, @unchecked Sendable {

  private let apiClient: APIClient

  init(apiClient: APIClient) {
    self.apiClient = apiClient
  }

  func fetchCurrentDevice() async throws -> DeviceInfo {
    let request = DeviceInfoRequest()
    let response = try await apiClient.performRequest(
      with: request,
      decodingType: DeviceInfoData.self
    )
    return response.device
  }

  func fetchSettings(deviceId: Int) async throws -> DeviceSettings {
    let request = DeviceSettingsRequest(id: deviceId)
    let response = try await apiClient.performRequest(
      with: request,
      decodingType: DeviceSettingsData.self
    )
    return response.settings
  }

  func updateSettings(deviceId: Int, settings: DeviceSettings) async throws {
    let request = UpdateDeviceSettingsRequest(id: deviceId, settings: settings)
    _ = try await apiClient.performRequest(
      with: request,
      decodingType: EmptyResponseData.self
    )
  }

  func listDevices() async throws -> [ManagedDevice] {
    let request = ListDevicesRequest()
    return try await apiClient.performRequest(
      with: request,
      decodingType: DevicesData.self
    ).devices
  }

  func removeDevice(id: Int) async throws {
    let request = RemoveDeviceRequest(id: id)
    _ = try await apiClient.performRequest(
      with: request,
      decodingType: EmptyResponseData.self
    )
  }

  func syncDeviceProfile(activated: Bool) async {
    let identity = DeviceIdentity.current
    let supportsHevc = DeviceCapabilities.supportsHEVC
    let fingerprint = DeviceProfileRegistry.fingerprint(
      identity: identity,
      supportsHevc: supportsHevc
    )

    // Activation always registers. Otherwise the profile only goes out when it says
    // something new — a launch on an unchanged device must not overwrite settings the
    // user edited in Settings › Device since.
    guard activated || !DeviceProfileRegistry.isRegistered(fingerprint) else {
      Logger.app.debug("device profile unchanged — nothing to register")
      return
    }

    do {
      try await registerIdentity(identity)
      try await applyStreamingProfile()
      // Only now: a half-registered device must retry on the next launch.
      DeviceProfileRegistry.markRegistered(fingerprint)
    } catch {
      Logger.app.error("device profile registration failed: \(String(describing: error))")
    }
  }

  private func registerIdentity(_ identity: DeviceIdentity.NotifyPayload) async throws {
    let request = DeviceNotifyRequest(
      title: identity.title,
      hardware: identity.hardware,
      software: identity.software
    )
    _ = try await apiClient.performRequest(
      with: request,
      decodingType: EmptyResponseData.self
    )
    Logger.app.debug(
      "device notify: \(identity.title) / \(identity.hardware) / \(identity.software)"
    )
  }

  /// Configures the shared kino.pub device slot with the universal Apple playback
  /// profile (`4K + HDR + HEVC + SSL + mixedPlaylist`) so opening the app on an iPhone,
  /// iPad, or Simulator never downgrades 4K/HDR on the slot shared with Apple TV and Mac.
  private func applyStreamingProfile() async throws {
    let device = try await fetchCurrentDevice()
    var settings = try await fetchSettings(deviceId: device.id)
    guard DeviceCapabilities.applyUniversalProfile(to: &settings) else { return }
    try await updateSettings(deviceId: device.id, settings: settings)
    Logger.app.debug("device capabilities synced to universal Apple profile (4K + HDR + HEVC + SSL + mixedPlaylist)")
  }
}
