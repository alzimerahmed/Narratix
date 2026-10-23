//
//  ProfileScreen.swift
//  BookPlayer
//
//  Created by Gianni Carlo on 31/7/25.
//  Copyright © 2025 BookPlayer LLC. All rights reserved.
//

import Foundation

enum ProfileScreen: Hashable {
  case account
  /// Every queued task, one collapsible section per lane
  case queueTasks
  /// Streaks, daily goal, monthly chart and per-book listening time
  case stats
}
