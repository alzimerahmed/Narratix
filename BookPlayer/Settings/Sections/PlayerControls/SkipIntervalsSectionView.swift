//
//  SkipIntervalsSectionView.swift
//  BookPlayer
//
//  Created by Gianni Carlo on 27/7/25.
//  Copyright © 2025 BookPlayer LLC. All rights reserved.
//

import BookPlayerKit
import MediaPlayer
import SwiftUI

struct SkipIntervalsSectionView: View {
  @AppStorage(Constants.UserDefaults.rewindInterval) var rewindInterval: TimeInterval = 30
  @AppStorage(Constants.UserDefaults.forwardInterval) var forwardInterval: TimeInterval = 30
  @EnvironmentObject var theme: ThemeViewModel

  /// The "Custom…" alert: one free-form seconds field per direction
  @State private var showsCustomIntervalAlert = false
  @State private var customRewindText = ""
  @State private var customForwardText = ""

  /// Free-form stays inside one second and one hour — outside that the picker's range is
  /// the saner choice
  static let customIntervalRange: ClosedRange<TimeInterval> = 1...3600

  private let intervals: [TimeInterval] = [
    2.0,
    5.0,
    10.0,
    15.0,
    20.0,
    30.0,
    45.0,
    60.0,
    90.0,
    120.0,
    180.0,
    240.0,
    300.0,
  ]

  var body: some View {
    ThemedSection {
      Picker(selection: $rewindInterval) {
        ForEach(intervals, id: \.self) { interval in
          Text(TimeParser.formatDuration(interval))
            .bpFont(.body)
            .tag(interval)
            .foregroundStyle(theme.linkColor)
        }
        Text("chapters_previous_title")
          .bpFont(.body)
          .tag(Constants.SkipInterval.chapterSkipValue)
          .foregroundStyle(theme.linkColor)
      } label: {
        Text("settings_skip_rewind_title")
          .bpFont(.body)
      }
      .pickerStyle(.menu)
      .onChange(of: rewindInterval) {
        let center = MPRemoteCommandCenter.shared()
        if rewindInterval == Constants.SkipInterval.chapterSkipValue {
          center.skipBackwardCommand.isEnabled = false
        } else {
          center.skipBackwardCommand.isEnabled = true
          center.skipBackwardCommand.preferredIntervals = [rewindInterval] as [NSNumber]
        }
      }

      Picker(selection: $forwardInterval) {
        ForEach(intervals, id: \.self) { interval in
          Text(TimeParser.formatDuration(interval))
            .bpFont(.body)
            .tag(interval)
            .foregroundStyle(theme.linkColor)
        }
        Text("chapters_next_title")
          .bpFont(.body)
          .tag(Constants.SkipInterval.chapterSkipValue)
          .foregroundStyle(theme.linkColor)
      } label: {
        Text("settings_skip_forward_title")
          .bpFont(.body)
      }
      .pickerStyle(.menu)
      .onChange(of: forwardInterval) {
        let center = MPRemoteCommandCenter.shared()
        if forwardInterval == Constants.SkipInterval.chapterSkipValue {
          center.skipForwardCommand.isEnabled = false
        } else {
          center.skipForwardCommand.isEnabled = true
          center.skipForwardCommand.preferredIntervals = [forwardInterval] as [NSNumber]
        }
      }

      /// A seconds value no preset covers. The row echoes the custom value(s) once one is
      /// set — a picker selection that matches no tag would otherwise show nothing
      Button {
        customRewindText = intervalText(rewindInterval)
        customForwardText = intervalText(forwardInterval)
        showsCustomIntervalAlert = true
      } label: {
        HStack {
          Text("settings_skip_custom_button")
            .bpFont(.body)
            .foregroundStyle(theme.primaryColor)
          Spacer()
          if let customSummary {
            Text(customSummary)
              .bpFont(.body)
              .foregroundStyle(theme.secondaryColor)
          }
        }
      }
      .alert("settings_skip_custom_title", isPresented: $showsCustomIntervalAlert) {
        TextField("settings_skip_rewind_title", text: $customRewindText)
          .keyboardType(.decimalPad)
        TextField("settings_skip_forward_title", text: $customForwardText)
          .keyboardType(.decimalPad)
        Button("ok_button") { applyCustomIntervals() }
        Button("cancel_button", role: .cancel) {}
      } message: {
        Text("settings_skip_custom_description")
      }
    } header: {
      Text("settings_skip_title".localized.capitalized)
        .bpFont(.subheadline)
        .foregroundStyle(theme.secondaryColor)
    } footer: {
      Text("settings_skip_description")
        .bpFont(.caption)
        .foregroundStyle(theme.secondaryColor)
    }
  }

  /// A positive, non-preset interval as the field's text (fractions keep theirs); chapter
  /// skip and presets start blank — re-typing the preset's number is the field's own job
  private func intervalText(_ interval: TimeInterval) -> String {
    guard interval > 0, !intervals.contains(interval) else { return "" }
    return String(format: "%g", interval)
  }

  /// Echoes the custom intervals on the row once one is set, e.g. "42 seconds / 1.5 minutes"
  private var customSummary: String? {
    var parts: [String] = []
    if rewindInterval > 0, !intervals.contains(rewindInterval) {
      parts.append(TimeParser.formatDuration(rewindInterval))
    }
    if forwardInterval > 0, !intervals.contains(forwardInterval) {
      parts.append(TimeParser.formatDuration(forwardInterval))
    }
    return parts.isEmpty ? nil : parts.joined(separator: " / ")
  }

  /// Lenient parse: comma decimals count, blanks keep the current value. Assigning the
  /// AppStorage runs the picker's `.onChange`, which updates the lock-screen commands
  private func applyCustomIntervals() {
    if let rewind = Self.parseSeconds(customRewindText) {
      rewindInterval = rewind
    }
    if let forward = Self.parseSeconds(customForwardText) {
      forwardInterval = forward
    }
  }

  /// Nil only when there's no number at all: an out-of-range one clamps to the
  /// nearest bound rather than being dropped without a word
  static func parseSeconds(_ text: String) -> TimeInterval? {
    guard
      let value = Double(text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
    else { return nil }
    return min(max(value, customIntervalRange.lowerBound), customIntervalRange.upperBound)
  }
}

#Preview {
  Form {
    SkipIntervalsSectionView()
  }
  .environmentObject(ThemeViewModel())
}
