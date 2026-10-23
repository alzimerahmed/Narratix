//
//  WebDAVConnection.swift
//  BookPlayer
//
//  Copyright © 2026 BookPlayer LLC. All rights reserved.
//

import Foundation

/// A WebDAV server the app imports from. Stored in the Keychain as a whole —
/// `webdav_connection` — so the password never touches UserDefaults or logs.
///
/// `url` is the directory the browser opens on; it may point at a subdirectory
/// of the server (e.g. Nextcloud's `remote.php/dav/files/<user>/Audiobooks`).
struct WebDAVConnection: Codable, Sendable {
  var url: URL
  var username: String
  var password: String
}
