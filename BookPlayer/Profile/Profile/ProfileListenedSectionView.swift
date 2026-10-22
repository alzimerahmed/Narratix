//
//  ProfileListenedSectionView.swift
//  BookPlayer
//
//  Created by Gianni Carlo on 31/7/25.
//  Copyright © 2025 BookPlayer LLC. All rights reserved.
//

import BookPlayerKit
import SwiftUI

struct ProfileListenedSectionView: View {
  @State private var formattedListeningTime: String = ""

  @EnvironmentObject private var theme: ThemeViewModel
  @Environment(\.libraryService) private var libraryService
  /// Tapping the section opens the listening-stats screen
  var action: (() -> Void)?

  var body: some View {
    Section {
      if let action {
        Button(action: action) {
          listenedBlock
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.primaryColor)
        .accessibilityHint("stats_open_hint".localized)
      } else {
        listenedBlock
          .accessibilityElement(children: .combine)
      }
    }
    .listRowBackground(Color.clear)
    .onReceive(NotificationCenter.default.publisher(for: .bookPaused)) { _ in
      reloadListeningTime()
    }
    .onAppear {
      reloadListeningTime()
    }
  }

  /// The big total over the caption — shared by the plain and tappable
  /// variants so they read identically
  private var listenedBlock: some View {
    VStack {
      Text(formattedListeningTime)
        .bpFont(.title)
      Text("total_listening_title".localized)
        .bpFont(.subheadline)
        .foregroundStyle(theme.secondaryColor)
    }
    .frame(maxWidth: .infinity)
  }

  func reloadListeningTime() {
    let time = libraryService.getTotalListenedTime()
    
    guard let formattedTime = formatTime(time) else { return }
    
    formattedListeningTime = formattedTime
  }

  func formatTime(
    _ time: Double,
    units: NSCalendar.Unit = [.year, .day, .hour, .minute]
  ) -> String? {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = units
    formatter.unitsStyle = .abbreviated

    return formatter.string(from: time)
  }
}

#Preview {
  @Previewable var accountService: AccountService = {
    let accountService = AccountService()
    let dataManager = DataManager(coreDataStack: CoreDataStack(testPath: ""))
    accountService.setup(dataManager: dataManager)
    accountService.accessLevel = .free

    return accountService
  }()

  @Previewable var libraryService: LibraryService = {
    let libraryService = LibraryService()
    let dataManager = DataManager(coreDataStack: CoreDataStack(testPath: ""))
    let audioMetadataService = AudioMetadataService()
    libraryService.setup(dataManager: dataManager, audioMetadataService: audioMetadataService)

    return libraryService
  }()

  Form {
    ProfileListenedSectionView()
  }
  .environmentObject(ThemeViewModel())
  .environment(\.accountService, accountService)
  .environment(\.libraryService, libraryService)
}
