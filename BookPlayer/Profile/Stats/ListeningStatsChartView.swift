//
//  ListeningStatsChartView.swift
//  BookPlayer
//
//  Created by Gianni Carlo on 3/8/26.
//  Copyright © 2026 BookPlayer LLC. All rights reserved.
//
//

import BookPlayerKit
import Charts
import SwiftUI

/// Minutes-listened-per-day bar chart for the last `days` days. Swift Charts
/// (system framework, iOS 16+; our floor is 26) — kept to a single BarMark
/// series so the visual weight matches the grouped-list sections around it.
/// Zero-listening days render as gaps, not fabricated bars.
struct ListeningStatsChartView: View {
  let records: [SimplePlaybackRecord]
  let accentColor: Color
  let secondaryColor: Color

  private static let minutesAxisStride = 6

  var body: some View {
    Chart(records) { record in
      BarMark(
        x: .value("day", record.date, unit: .day),
        y: .value("minutes", record.time / 60)
      )
      .foregroundStyle(accentColor)
      .cornerRadius(2)
    }
    .chartXAxis {
      AxisMarks(values: .stride(by: .day, count: Self.minutesAxisStride)) { _ in
        AxisValueLabel(format: .dateTime.day(.defaultDigits))
          .foregroundStyle(secondaryColor)
      }
    }
    .chartYAxis {
      AxisMarks(position: .leading) { _ in
        AxisGridLine()
        AxisValueLabel()
          .foregroundStyle(secondaryColor)
      }
    }
    .frame(height: 160)
    /// A chart of numbers is opaque to VoiceOver — announce the summary
    /// instead and hide the glyph-level detail
    .accessibilityElement()
    .accessibilityLabel("stats_chart_accessibility")
  }
}
