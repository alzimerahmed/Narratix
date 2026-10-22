//
//  PlayerControlsEQSectionView.swift
//  BookPlayer
//
//  Copyright © 2025 BookPlayer LLC. All rights reserved.
//  Narratix — Phase 3e (equalizer / voice boost).
//

import BookPlayerKit
import SwiftUI

/// Equalizer section of the player controls sheet: a curated preset row plus
/// the voice-boost toggle. Presets are chips like the speed presets above them;
/// the toggle mirrors the boost-volume row's styling.
struct PlayerControlsEQSectionView: View {
  /// Read-only: chips route changes through `handlePresetChange`, so nothing
  /// here writes the preset — a binding would carry a dead setter
  let selectedPreset: EQPreset
  @Binding var voiceBoostEnabled: Bool
  let handlePresetChange: (EQPreset) -> Void

  @EnvironmentObject private var theme: ThemeViewModel

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.S) {
      Text("player_eq_title")
        .bpFont(.subheadline)
        .bold()
        .foregroundStyle(theme.primaryColor)

      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: Spacing.S3) {
          ForEach(EQPreset.allCases) { preset in
            PresetChipView(
              title: preset.titleKey.localized,
              isCurrent: selectedPreset == preset
            ) {
              handlePresetChange(preset)
            }
          }
        }
      }

      Toggle("settings_voiceboost_title", isOn: $voiceBoostEnabled)
        .bpFont(.subheadline)
        .bold()
        .foregroundStyle(theme.primaryColor)
        .tint(theme.linkColor)
        /// Voice boost stacks on a preset chain — `.off` renders nothing, so
        /// the toggle is disabled there rather than implying it acts alone;
        /// the hint says WHY, a disabled control can't
        .disabled(selectedPreset == .off)
        .accessibilityHint(
          selectedPreset == .off ? "settings_voiceboost_disabled_hint" : ""
        )

      Text("settings_voiceboost_description")
        .bpFont(.caption)
        .foregroundStyle(theme.secondaryColor)
        .fixedSize(horizontal: false, vertical: true)
        .frame(minWidth: 160, alignment: .leading)
    }
  }

}

#Preview {
  @Previewable @State var preset: EQPreset = .voice
  @Previewable @State var voiceBoost: Bool = true
  PlayerControlsEQSectionView(
    selectedPreset: preset,
    voiceBoostEnabled: $voiceBoost
  ) { preset = $0 }
}
