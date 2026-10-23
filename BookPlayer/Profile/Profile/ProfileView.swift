//
//  ProfileView.swift
//  BookPlayer
//
//  Created by gianni.carlo on 17/1/23.
//  Copyright © 2023 BookPlayer LLC. All rights reserved.
//

import BookPlayerKit
import SwiftUI

struct ProfileView: View {
  @State private var path = NavigationPath()
  @State private var showLogin = false
  @Environment(\.accountService) private var accountService
  @Environment(\.playerState) private var playerState
  @Environment(\.listeningStatsService) private var listeningStatsService
  @Environment(\.playbackHistoryService) private var playbackHistoryService
  @EnvironmentObject private var theme: ThemeViewModel
  
  var body: some View {
    NavigationStack(path: $path) {
      VStack(spacing: 0) {
        Form {
          ProfileCardSectionView(action: showLoginOrAccount)
            .listSectionSpacing(Spacing.S1)
          ProfileListenedSectionView {
            path.append(ProfileScreen.stats)
          }
        }

        Spacer()
        
        if !accountService.account.id.isEmpty {
          ProfileSyncTasksSectionView()
        }
      }
      .miniPlayerSafeAreaInset()
      .applyListStyle(with: theme, background: theme.systemBackgroundColor)
      .navigationTitle("profile_title")
      .navigationBarTitleDisplayMode(.inline)
      .navigationDestination(for: ProfileScreen.self) { destination in
        switch destination {
        case .account:
          AccountView()
        case .queueTasks:
          QueuedTasksView()
            .miniPlayerSafeAreaInset()
        case .stats:
          ListeningStatsView {
            ListeningStatsViewModel(
              statsService: listeningStatsService,
              playbackHistoryService: playbackHistoryService
            )
          }
          .miniPlayerSafeAreaInset()
        }
      }
      .sheet(isPresented: $showLogin) {
        NavigationStack {
          LoginView()
        }
      }
    }
    .foregroundStyle(theme.primaryColor)
    .tint(theme.linkColor)
  }

  func showLoginOrAccount() {
    if accountService.account.id.isEmpty {
      showLogin = true
    } else {
      path.append(ProfileScreen.account)
    }
  }
}
