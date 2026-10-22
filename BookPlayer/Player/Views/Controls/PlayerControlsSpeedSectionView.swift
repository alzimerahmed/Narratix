//
//  PlayerControlsSpeedSectionView.swift
//  BookPlayer
//
//  Created by Gianni Carlo on 11/10/25.
//  Copyright © 2025 BookPlayer LLC. All rights reserved.
//

import BookPlayerKit
import SwiftUI

struct PlayerControlsSpeedSectionView: View {
  @AppStorage(Constants.UserDefaults.quickSpeedFirstPreference)
  var quickSpeedFirstPreference: Double = 1.0
  @AppStorage(Constants.UserDefaults.quickSpeedSecondPreference)
  var quickSpeedSecondPreference: Double = 2.0
  @AppStorage(Constants.UserDefaults.quickSpeedThirdPreference)
  var quickSpeedThirdPreference: Double = 3.0

  let minimumSpeed: Double = 0.5
  let maximumSpeed: Double = 4.0
  let speedStep: Double = 0.1
  /// One-tap speeds, fixed — the three quick buttons below stay user-configurable
  /// (Settings), these cover the common picks without a detour
  static let presetSpeeds: [Double] = [0.5, 1, 1.25, 1.5, 2, 2.5]
  @Binding var currentSpeed: Double
  let handleSpeedChange: (Double) -> Void

  @EnvironmentObject private var theme: ThemeViewModel

  var body: some View {
    VStack(spacing: Spacing.S) {
      HStack {
        Text("player_speed_title")
          .bpFont(.subheadline)
          .bold()
          .foregroundStyle(theme.primaryColor)

        Spacer()

        Text(formatSpeed(currentSpeed))
          .bpFont(.headline)
          .foregroundStyle(theme.primaryColor)
          .accessibilityHidden(true)
      }

      HStack(spacing: Spacing.S2) {
        Text(String(format: "%.1f", minimumSpeed))
          .bpFont(.subheadline)
          .foregroundStyle(theme.primaryColor)
          .frame(minWidth: 30)
          .accessibilityHidden(true)

        Slider(
          value: $currentSpeed,
          in: minimumSpeed...maximumSpeed
        )
        .accessibilityValue(formatSpeed(currentSpeed))
        .accessibilityAdjustableAction { direction in
          let speed = currentSpeed
          let newSpeed: Double
          switch direction {
          case .increment:
            let boundedSpeed = min(speed + 0.1, maximumSpeed)
            newSpeed = round(boundedSpeed / self.speedStep) * self.speedStep
          case .decrement:
            let boundedSpeed = max(speed - 0.1, minimumSpeed)
            newSpeed = round(boundedSpeed / self.speedStep) * self.speedStep
          @unknown default:
            return
          }

          currentSpeed = newSpeed
        }

        Text(String(format: "%.1f", maximumSpeed))
          .bpFont(.subheadline)
          .foregroundStyle(theme.primaryColor)
          .frame(minWidth: 30)
          .accessibilityHidden(true)
      }

      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: Spacing.S3) {
          ForEach(Self.presetSpeeds, id: \.self) { speed in
            PresetChipView(
              title: formatSpeed(speed),
              isCurrent: abs(currentSpeed - speed) < 0.001
            ) {
              handleSpeedChange(speed)
            }
          }
        }
      }

      // Speed control buttons
      HStack(spacing: 0) {
        // Decrement button
        Button {
          if currentSpeed > minimumSpeed {
            let newSpeed = currentSpeed - 0.05
            handleSpeedChange(newSpeed)
          }
        } label: {
          Image(systemName: "minus.circle")
            .imageScale(.large)
        }
        .foregroundStyle(theme.primaryColor)
        .frame(width: 44, height: 44)
        .accessibilityLabel("speed_decrease_button")

        Spacer()

        // Quick action buttons
        HStack(spacing: Spacing.S3) {
          quickSpeedButton(speed: quickSpeedFirstPreference)
          quickSpeedButton(speed: quickSpeedSecondPreference)
          quickSpeedButton(speed: quickSpeedThirdPreference)
        }

        Spacer()

        // Increment button
        Button {
          if currentSpeed < maximumSpeed {
            let newSpeed = currentSpeed + 0.05
            handleSpeedChange(newSpeed)
          }
        } label: {
          Image(systemName: "plus.circle")
            .imageScale(.large)
        }
        .foregroundStyle(theme.primaryColor)
        .frame(width: 44, height: 44)
        .accessibilityLabel("speed_increase_button")
      }
      .frame(height: 44)
    }
  }

  /// The chip itself lives in `PresetChipView`, shared with the EQ section
  @ViewBuilder
  private func quickSpeedButton(speed: Double) -> some View {
    Button {
      handleSpeedChange(speed)
    } label: {
      Text(formatSpeed(speed))
        .bpFont(.subheadline)
        .bold()
    }
    .buttonStyle(.bordered)
    .tint(theme.primaryColor)
    .clipShape(RoundedRectangle(cornerRadius: 5))
    .frame(minWidth: 70, minHeight: 44)
  }
}

#Preview {
  @Previewable @State var currentSpeed: Double = 1.5
  PlayerControlsSpeedSectionView(currentSpeed: $currentSpeed) { _ in }
}
