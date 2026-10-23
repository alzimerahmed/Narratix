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
    /// A chart of numbers is opaque to VoiceOver — the descriptor turns it
    /// into a real chart element: summary first, then each day's bar as a
    /// data point the chart rotor can visit
    .accessibilityElement(children: .ignore)
    .accessibilityChartDescriptor(StatsChartDescriptor(records: records))
  }
}

/// VoiceOver's read on the chart: axes, and one data point per day — the
/// same numbers the bars draw, no fabricated points for zero-listening days
private struct StatsChartDescriptor: AXChartDescriptorRepresentable {
  let records: [SimplePlaybackRecord]

  /// Day labels for the categorical x axis ("Mar 8") — medium style, no year,
  /// matching what the on-screen axis shows every sixth day
  private static let dayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.setLocalizedDateFormatFromTemplate("MMMd")
    return formatter
  }()

  func makeChartDescriptor() -> AXChartDescriptor {
    let sorted = records.sorted { $0.date < $1.date }
    let minutes = sorted.map { $0.time / 60 }

    let xAxis = AXCategoricalDataAxisDescriptor(
      title: "stats_chart_day_axis".localized,
      categoryOrder: sorted.map { Self.dayFormatter.string(from: $0.date) }
    )
    let yAxis = AXNumericDataAxisDescriptor(
      title: "minutes".localized,
      range: 0...(minutes.max() ?? 0),
      gridlinePositions: []
    ) { value in
      VoiceOverService.secondsToMinutes(value * 60)
    }
    let series = AXDataSeriesDescriptor(
      name: "minutes".localized,
      isContinuous: false,
      dataPoints: zip(sorted, minutes).map { record, value in
        AXDataPoint(
          x: Self.dayFormatter.string(from: record.date),
          y: value
        )
      }
    )
    return AXChartDescriptor(
      title: "stats_chart_accessibility".localized,
      xAxis: xAxis,
      yAxis: yAxis,
      series: [series]
    )
  }
}
