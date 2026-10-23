//
//  ProgressData.swift
//  BookPlayer
//
//  Created by Pedro Iñiguez on 10/2/26.
//  Copyright © 2026 BookPlayer LLC. All rights reserved.
//

import Foundation
import BookPlayerKit

struct ProgressData: Equatable {
  var currentTime: TimeInterval = 0.0
  var progress: String?
  var maxTime: TimeInterval?
  var sliderValue: Double = 0.0
  var chapterTitle: String = ""
  /// Chapter ticks for the scrubber: book-level fractions, only when the slider spans the
  /// whole book (in chapter context they wouldn't map onto the track)
  var chapterMarkers: [ChapterMarker] = []

  var formattedCurrentTime: String {
    return TimeParser.formatTime(self.currentTime)
  }

  var formattedMaxTime: String? {
    guard let maxTime = self.maxTime else { return nil }

    let formattedTime = TimeParser.formatTime(abs(maxTime))

    if maxTime < 0 {
      return "-".appending(formattedTime)
    } else {
      return formattedTime
    }
  }
}
