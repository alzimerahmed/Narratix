//
//  LibraryRootView.swift
//  BookPlayer
//
//  Created by Gianni Carlo on 10/8/25.
//  Copyright © 2025 BookPlayer LLC. All rights reserved.
//

import BookPlayerKit
import DirectoryWatcher
import SwiftUI

struct LibraryRootView: View {
  let showSecondOnboarding: () -> Void
  let showImport: () -> Void

  @State private var path = [LibraryNode]()

  @State private var newFolderName: String = ""
  @State private var isFirstLoad = true
  /// The Library tab is on screen: an import's placement prompt can't be presented from a hidden tab
  @State private var isVisible = false

  @State private var importOperationState = ImportOperationState()
  @State private var loadingState = LoadingOverlayState()
  /// The duplicate warning on screen — `pendingDuplicates` hands it the next
  /// queued import once nothing covers the library, same posture as the
  /// placement prompt
  @State private var duplicatePrompt: PendingDuplicateImport?

  @StateObject private var documentFolderWatcher = DirectoryWatcher.watch(
    DataManager.getDocumentsFolderURL(),
    ignoreDirectories: false
  )!
  @StateObject private var sharedFolderWatcher = DirectoryWatcher.watch(
    DataManager.getSharedFilesFolderURL(),
    ignoreDirectories: false
  )!

  /// Environment
  @StateObject private var theme = ThemeViewModel()

  @EnvironmentObject private var playerManager: PlayerManager
  @EnvironmentObject private var importManager: ImportManager
  @EnvironmentObject private var externalImportEvents: ExternalImportEvents
  @EnvironmentObject private var singleFileDownloadService: SingleFileDownloadService
  @EnvironmentObject private var listSyncRefreshService: ListSyncRefreshService

  @Environment(\.listState) private var listState
  @Environment(\.playerState) private var playerState
  @Environment(\.libraryService) private var libraryService
  @Environment(\.playbackService) private var playbackService
  @Environment(\.syncService) private var syncService
  @Environment(\.hardcoverService) private var hardcoverService
  @Environment(\.listeningQueueService) private var listeningQueueService
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    NavigationStack(path: $path) {
      ItemListView {
        ItemListViewModel(
          libraryNode: .root,
          libraryService: libraryService,
          playbackService: playbackService,
          playerManager: playerManager,
          syncService: syncService,
          listSyncRefreshService: listSyncRefreshService,
          loadingState: loadingState,
          listState: listState,
          singleFileDownloadService: singleFileDownloadService,
          listeningQueueService: listeningQueueService
        )
      }
      .navigationDestination(for: LibraryNode.self) { node in
        ItemListView {
          ItemListViewModel(
            libraryNode: node,
            libraryService: libraryService,
            playbackService: playbackService,
            playerManager: playerManager,
            syncService: syncService,
            listSyncRefreshService: listSyncRefreshService,
            loadingState: loadingState,
            listState: listState,
            singleFileDownloadService: singleFileDownloadService,
            listeningQueueService: listeningQueueService
          )
        }
        .navigationBarTitleDisplayMode(.inline)
        .errorAlert(error: loadingState.errorBinding)
      }
      .errorAlert(error: loadingState.errorBinding)
      .loadingOverlay(loadingState.show, message: loadingState.message)
      .onAppear {
        guard isFirstLoad else { return }

        isFirstLoad = false

        Task {
          await handleLibraryLoaded()
        }
      }
      .onChange(of: scenePhase) {
        guard scenePhase == .active else { return }
        showImport()
      }
      .onReceive(syncService.downloadErrorPublisher) { (relativePath, error) in
        let errorMessage = "\(relativePath)\n\(error.localizedDescription)"
        loadingState.error = BookPlayerError.networkError(errorMessage)
      }
      .onReceive(importManager.observeFiles()) { files in
        guard !files.isEmpty, !singleFileDownloadService.isDownloading else { return }

        showImport()
      }
      .onReceive(documentFolderWatcher.newFilesPublisher) { files in
        files.forEach { importManager.process($0) }
      }
      .onReceive(sharedFolderWatcher.newFilesPublisher) { files in
        files.forEach { importManager.process($0) }
      }
      .onReceive(importManager.operationPublisher) { operation in
        importOperationState.isOperationActive = true
        importOperationState.processingTitle = String.localizedStringWithFormat(
          "import_processing_description".localized,
          operation.files.count
        )
        operation.completionBlock = {
          DispatchQueue.main.async {
            self.importOperationState.isOperationActive = false
            self.importOperationState.processingTitle = ""
            self.handleOperationCompletion(.local(files: operation.processedFiles), suggestedFolderName: operation.suggestedFolderName)
          }
        }

        importManager.start(operation)
      }
      .onReceive(externalImportEvents.confirmedBatches) { externalResources in
        Task {
          self.handleOperationCompletion(.external(files: externalResources), suggestedFolderName: nil)
        }
      }
    }
    .modifier(
      ImportPlacementPrompt(
        model: ImportPlacementModel(
          libraryService: libraryService,
          syncService: syncService,
          playerManager: playerManager
        ),
        importOperationState: importOperationState,
        loadingState: loadingState,
        isLibraryVisible: isVisible,
        isImportScreenShown: importManager.isImportScreenShown
      )
    )
    /// Same gate as the placement prompt's, in miniature: a warning raised under
    /// a cover (the transfer/WebDAV sheet, the player) would be dropped and its
    /// pending import lost, so it waits for an uncovered, visible library — and
    /// `promptShowing` in the gate refires this when the current warning's
    /// dismissal frees the slot for a queued one
    .onChange(of: duplicateGate) { _, gate in
      guard gate.isOpen, !importOperationState.pendingDuplicates.isEmpty
      else { return }
      /// A pass later: handed over in the same update the closing alert would
      /// take it for its own contents changing
      Task { @MainActor in
        guard duplicatePrompt == nil,
          let pending = importOperationState.pendingDuplicates.first
        else { return }
        importOperationState.pendingDuplicates.removeFirst()
        duplicatePrompt = pending
      }
    }
    .alert(
      "import_duplicates_title",
      isPresented: Binding(
        get: { duplicatePrompt != nil },
        set: { if !$0 { duplicatePrompt = nil } }
      ),
      presenting: duplicatePrompt
    ) { pending in
      Button("import_duplicates_skip") {
        resolveDuplicateImport(pending, action: .skip)
      }
      Button("import_duplicates_replace", role: .destructive) {
        resolveDuplicateImport(pending, action: .replace)
      }
      Button("import_duplicates_import_anyway") {
        resolveDuplicateImport(pending, action: .importAnyway)
      }
    } message: { pending in
      Text(duplicateMessage(for: pending))
    }
    .onAppear { isVisible = true }
    .onDisappear { isVisible = false }
    .tint(theme.linkColor)
    .environmentObject(theme)
    .environment(\.loadingState, loadingState)
    .environment(\.importOperationState, importOperationState)
  }

  func handleLibraryLoaded() async {
    await loadLastBookIfNeeded()
    importManager.notifyPendingFiles()
    /// Open the player on launch when enabled and a book is loaded. Checked here, after the load above,
    /// so it covers both a plain cold launch (where `loadLastBookIfNeeded` just loaded the last book)
    /// and the case where the book was already loaded by another scene (e.g. CarPlay) — which makes the
    /// `currentItem == nil` guard inside `loadLastBookIfNeeded` return early. Files waiting to be
    /// imported take the screen instead: their import screen and the player can't both present
    if UserDefaults.standard.bool(forKey: Constants.UserDefaults.openPlayerOnAppLaunch),
       playerManager.currentItem != nil,
       !importManager.hasPendingFiles() {
      playerState.showPlayer = true
    }
    showSecondOnboarding()

    let pendingActions = AppServices.shared.pendingURLActions
    AppServices.shared.pendingURLActions.removeAll()
    for action in pendingActions {
      ActionParserService.handleAction(action)
    }
  }

  func loadLastBookIfNeeded() async {
    guard
      playerManager.currentItem == nil,
      let libraryItem = libraryService.getLibraryLastItem()
    else { return }

    do {
      try await AppServices.shared.coreServices?.playerLoaderService.loadPlayer(
        libraryItem.relativePath,
        autoplay: false,
        recordAsLastBook: false
      )
      if UserDefaults.standard.bool(forKey: Constants.UserActivityPlayback) {
        UserDefaults.standard.removeObject(forKey: Constants.UserActivityPlayback)
        playerManager.play()
      }

      if UserDefaults.standard.bool(forKey: Constants.UserDefaults.showPlayer) {
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaults.showPlayer)
        playerState.showPlayer = true
      }
    } catch BPPlayerError.fileMissing {
      // Silent preload: if the last-played file is missing on disk,
      // swallow the error. The user will see the proper alert if/when
      // they explicitly try to play this book. Surfacing it here would
      // race with other cold-launch presentations (e.g. the import sheet).
    } catch {
      loadingState.error = error
    }
  }

  func handleOperationCompletion(_ importSource: ImportSource, suggestedFolderName: String?) {
    let filesCount: Int
    switch importSource {
    case .local(let files):
      filesCount = files.count
    case .external(let externals):
      filesCount = externals.count
    }
    
    guard filesCount > 0 else {
      return
    }

    /// Where the import lands: the location browsed now, not after the network calls below
    let importNode = path.last ?? .root

    let isStream: Bool = {
      if case .external = importSource { return true }
      return false
    }()
    let streamTitle = String.localizedStringWithFormat("import_processing_description".localized, filesCount)
    if isStream {
      // A file import shows its copying; a stream import has none, so its insert and Hardcover's
      // match get the same spinner
      importOperationState.isOperationActive = true
      importOperationState.processingTitle = streamTitle
    }

    Task { @MainActor in
      defer {
        // Unless a file import or a download has taken the spinner over since
        if isStream, importOperationState.processingTitle == streamTitle {
          importOperationState.isOperationActive = false
          importOperationState.processingTitle = ""
        }
      }

      /// The browsed folder as it is now: a sync pull can rename it while it's open, or replace it
      /// (the folder at its path then has another uuid, which the sync move must name), or delete
      /// it, which lands the import at the root
      let landing = importNode.folderRelativePath.flatMap { currentFolder(uuid: importNode.uuid, path: $0) }

      let processedItems: [SimpleLibraryItem]
      switch importSource {
      case .local(let files):
        processedItems = await libraryService.insertItems(from: files)
      case .external(let externals):
        // Created in the browsed folder; file imports are copied to the root and moved there below
        processedItems = await libraryService.insertItems(
          fromResources: externals,
          inside: landing?.relativePath
        )
      }

      /// Nothing created (no item in the batch could become a book): nothing to place
      guard !processedItems.isEmpty else { return }

      /// Duplicates are asked about BEFORE anything uploads or moves: a skipped
      /// duplicate is then never pushed, and "Replace existing" can take the old
      /// item down with its cloud copy. File imports only — a stream item has
      /// no local file to collide with
      if case .local = importSource {
        let matches = ImportDuplicateDetector.findDuplicates(
          of: processedItems,
          libraryService: libraryService
        )
        if !matches.isEmpty {
          importOperationState.pendingDuplicates.append(
            PendingDuplicateImport(
              items: processedItems,
              matches: matches,
              node: importNode,
              suggestedFolderName: suggestedFolderName
            )
          )
          return
        }
      }

      await finishImport(
        processedItems: processedItems,
        isStream: isStream,
        importNode: importNode,
        suggestedFolderName: suggestedFolderName
      )
    }
  }

  /// The import tail, shared between a clean completion and the duplicate
  /// warning's resolutions: upload scheduling, the move into the browsed
  /// folder, and the placement prompt
  private func finishImport(
    processedItems: [SimpleLibraryItem],
    isStream: Bool,
    importNode: LibraryNode,
    suggestedFolderName: String?
  ) async {
    let landing = importNode.folderRelativePath.flatMap { currentFolder(uuid: importNode.uuid, path: $0) }
    /// Where the import ends up: a stream is created there, a file import is moved there below
    var landed = isStream ? landing : nil

    var itemIdentifiers = processedItems.map({ $0.relativePath })
    let itemIdentifiersPairs = processedItems.map({ LibraryItemRef(relativePath: $0.relativePath, uuid: $0.uuid) })
    var nameTakenError: Error?
    do {
      await syncService.scheduleUpload(items: processedItems)
      /// Move imported files to current selected folder so the user can see them. Found again
      /// here, with nothing awaited before the moves: the copy and insert above can take seconds
      if !isStream,
        let landing,
        let destination = currentFolder(uuid: landing.uuid, path: landing.relativePath) {
        let folderRelativePath = destination.relativePath
        // One whose name is taken in that folder stays at the root
        let outcome = try libraryService.moveItems(itemIdentifiersPairs, inside: folderRelativePath)
        if !outcome.moved.isEmpty {
          syncService.scheduleMove(
            items: outcome.moved,
            to: LibraryItemRef(relativePath: folderRelativePath, uuid: destination.uuid)
          )
        }
        /// Update identifiers after moving for the follow up action alert
        let movedPaths = Set(outcome.moved.map(\.relativePath))
        itemIdentifiers = itemIdentifiers.map { movedPaths.contains($0) ? "\(folderRelativePath)/\($0)" : $0 }
        nameTakenError = outcome.notMoved.first.map {
          LibraryService.nameTakenError(moving: $0.relativePath, into: folderRelativePath)
        }
        landed = destination
      }
    } catch {
      loadingState.error = error
      return
    }

    /// Reload all items
    listState.reloadAll(padding: itemIdentifiers.count)

    await hardcoverService.processAutoMatch(for: processedItems)

    /// Some names were taken in the folder, so the batch is split between it and the root: said
    /// instead of the placement prompt
    if let nameTakenError {
      loadingState.error = nameTakenError
      return
    }

    let availableFolders =
      self.libraryService.getItems(
        notIn: itemIdentifiers,
        parentFolder: landed?.relativePath
      )?.filter({ $0.type == .folder }) ?? []

    let singleFolder: SimpleLibraryItem? =
      processedItems.count == 1 && processedItems.allSatisfy({ $0.type == .folder })
      ? processedItems.first : nil
    let hasOnlyBooks = processedItems.allSatisfy({ $0.type == .book })

    var firstTitle: String?
    if let suggestedFolderName {
      firstTitle = suggestedFolderName
    } else if let relativePath = itemIdentifiers.first {
      /// Xcode Cloud is throwing an error on #keyPath(BookPlayerKit.LibraryItem.title)
      firstTitle =
        libraryService.getItemProperty(
          "title",
          relativePath: relativePath
        ) as? String
    }

    importOperationState.pendingPlacement = ImportPlacement(
      itemUuids: processedItems.map(\.uuid),
      hasOnlyBooks: hasOnlyBooks,
      singleFolderUuid: singleFolder?.uuid,
      availableFolders: availableFolders,
      suggestedFolderName: firstTitle,
      node: landed.map { .folder(title: $0.title, relativePath: $0.relativePath, uuid: $0.uuid) } ?? .root
    )
  }

  /// The browsed folder as it is now: a sync pull can rename it while it's open, or replace it
  /// (the folder at its path then has another uuid, which the sync move must name), or delete
  /// it, which lands the import at the root
  private func currentFolder(uuid: String, path: String) -> SimpleLibraryItem? {
    let currentPath = libraryService.getItemRefs(forUuids: [uuid]).first?.relativePath ?? path
    return libraryService.getSimpleItem(with: currentPath).flatMap { $0.type == .folder ? $0 : nil }
  }

  /// What decides when the duplicate warning can show, watched as one value so a
  /// pending import set while covered presents on the cover's close — and a
  /// queued one presents when the warning on screen dismisses (`promptShowing`
  /// flipping off is itself a gate change)
  private struct DuplicateGate: Equatable {
    let hasPending: Bool
    let promptShowing: Bool
    let isCovered: Bool
    let isImportScreenShown: Bool
    let isLibraryVisible: Bool

    var isOpen: Bool {
      hasPending && !promptShowing && !isCovered && !isImportScreenShown && isLibraryVisible
    }
  }

  private var duplicateGate: DuplicateGate {
    DuplicateGate(
      hasPending: !importOperationState.pendingDuplicates.isEmpty,
      promptShowing: duplicatePrompt != nil,
      isCovered: !listState.coversOnScreen.isEmpty,
      isImportScreenShown: importManager.isImportScreenShown,
      isLibraryVisible: isVisible
    )
  }

  /// The warning's names — up to three matched titles, then a count
  private func duplicateMessage(for pending: PendingDuplicateImport) -> String {
    let names = pending.matches.prefix(3).map(\.imported.title)
    var message = names.joined(separator: ", ")
    let extra = pending.matches.count - names.count
    if extra > 0 {
      message += " " + String.localizedStringWithFormat(
        "import_duplicates_more_format".localized, extra
      )
    }
    return String.localizedStringWithFormat(
      "import_duplicates_description".localized, message
    )
  }

  /// The duplicate warning's choices. The imports stay in `items` whatever is
  /// picked — the difference is what happens to the records they shadow
  private func resolveDuplicateImport(
    _ pending: PendingDuplicateImport,
    action: DuplicateImportAction
  ) {
    /// Imports whose delete failed stay in the batch — filtering them out
    /// anyway would strand records the delete never removed
    var skipDeleted = false
    switch action {
    case .importAnyway:
      break
    case .skip:
      /// Nothing of the imports uploaded yet: a plain delete drops the new
      /// record and its file in Processed, with no sync delete to schedule
      let duplicates = pending.matches.map(\.imported)
      do {
        try libraryService.delete(duplicates, mode: .deep)
        skipDeleted = true
      } catch {
        loadingState.error = error
      }
    case .replace:
      /// The pre-existing items are the ones to go — record, file, and cloud
      /// copy (they may have synced long ago), matching what a list delete does
      var seen = Set<String>()
      let existing = pending.matches.map(\.existing).filter { seen.insert($0.uuid).inserted }
      /// Same guard the list's delete has: never pull the file under a live player
      if existing.contains(where: { $0.relativePath == playerManager.currentItem?.relativePath }) {
        playerManager.stop()
      }
      do {
        try libraryService.delete(existing, mode: .deep)
        /// Only what actually deleted gets a cloud delete — a failed delete
        /// must not take the server's copy down with it
        syncService.scheduleDelete(existing, mode: .deep)
      } catch {
        loadingState.error = error
      }
    }

    /// "Skip" can empty an imported folder out: a folder left with no contents
    /// goes too, and an empty remainder means there's nothing to place
    let remaining = pending.items.filter { item in
      if action == .skip, skipDeleted {
        if pending.matches.contains(where: { $0.imported.uuid == item.uuid }) {
          return false
        }
        if item.type != .book {
          let contents = libraryService.filterContents(
            at: item.relativePath,
            query: nil,
            scope: nil,
            limit: nil,
            offset: nil
          ) ?? []
          if contents.isEmpty {
            do {
              try libraryService.delete([item], mode: .deep)
              return false
            } catch {
              loadingState.error = error
              return true
            }
          }
        }
      }
      return true
    }

    guard !remaining.isEmpty else {
      listState.reloadAll()
      return
    }

    Task { @MainActor in
      await finishImport(
        processedItems: remaining,
        isStream: false,
        importNode: pending.node,
        suggestedFolderName: pending.suggestedFolderName
      )
    }
  }
}

extension LibraryRootView {
  @MainActor
  final class Model {
    init() {}
  }
}

#Preview {
  LibraryRootView {
  } showImport: {
  }
}
