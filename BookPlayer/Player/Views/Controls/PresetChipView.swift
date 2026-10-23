//
//  PresetChipView.swift
//  BookPlayer
//
//  Copyright © 2026 BookPlayer LLC. All rights reserved.
//

import BookPlayerKit
import SwiftUI

/// The bordered preset chip the player-controls sections share (speed, EQ):
/// bold + tinted when current, for eyes and VoiceOver alike.
struct PresetChipView: View {
  let title: String
  let isCurrent: Bool
  let action: () -> Void

  @EnvironmentObject private var theme: ThemeViewModel

  var body: some View {
    Button(action: action) {
      Text(title)
        .bpFont(.subheadline)
        .fontWeight(isCurrent ? .bold : .regular)
        .padding(.horizontal, Spacing.S3)
        .frame(minWidth: 44, minHeight: 44)
    }
    .buttonStyle(.bordered)
    .tint(isCurrent ? theme.linkColor : theme.secondaryColor)
    .accessibilityAddTraits(isCurrent ? .isSelected : [])
  }
}
