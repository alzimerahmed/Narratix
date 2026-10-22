//
//  PlayerControlsViewModel.swift
//  BookPlayer
//
//  Created by Pavel Kyzmin on 09.01.2022.
//  Copyright © 2021 BookPlayer LLC. All rights reserved.
//

import BookPlayerKit
import Combine
import Foundation
import SwiftUI

class PlayerControlsViewModel: PlayerControlsView.Model {
  /// Concrete, not `PlayerManagerProtocol`: EQ is iOS-only, so `applyAudioEffects`
  /// deliberately lives off the shared protocol the watch player conforms to.
  let playerManager: PlayerManager
  private var disposeBag = Set<AnyCancellable>()
  private var boostVolumeObserver: NSKeyValueObservation?

  init(playerManager: PlayerManager) {
    self.playerManager = playerManager

    super.init(
      currentSpeed: Double(playerManager.currentSpeed),
      isBoostVolumeEnabled: UserDefaults.standard.bool(forKey: Constants.UserDefaults.boostVolumeEnabled),
      eqPreset: AudioEQSettings.preset,
      isVoiceBoostEnabled: AudioEQSettings.voiceBoostEnabled
    )

    bindObservers()
  }

  private func bindObservers() {
    playerManager.currentSpeedPublisher()
      .removeDuplicates()
      .receive(on: DispatchQueue.main)
      .sink { [weak self] speed in
        self?.currentSpeed = round(Double(speed) * 100) / 100.0
      }
      .store(in: &disposeBag)

    boostVolumeObserver = UserDefaults.standard.observe(
      \.userSettingsBoostVolume,
      options: [.new]
    ) { [weak self] _, change in
      guard let newValue = change.newValue else { return }

      self?.isBoostVolumeEnabled = newValue
    }
  }

  override func handleSpeedChange(_ speed: Double) {
    let roundedValue = round(speed * 100) / 100.0

    guard currentSpeed != roundedValue else { return }

    playerManager.setSpeed(Float(roundedValue))
  }

  override func handleBoostVolumeToggle(_ enabled: Bool) {
    UserDefaults.standard.set(enabled, forKey: Constants.UserDefaults.boostVolumeEnabled)

    playerManager.setBoostVolume(enabled)
  }

  override func handleEQPresetChange(_ preset: EQPreset) {
    guard eqPreset != preset else { return }

    eqPreset = preset
    AudioEQSettings.preset = preset
    playerManager.applyAudioEffects()
  }

  override func handleVoiceBoostToggle(_ enabled: Bool) {
    isVoiceBoostEnabled = enabled
    AudioEQSettings.voiceBoostEnabled = enabled
    playerManager.applyAudioEffects()
  }
}
