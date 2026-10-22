// Purpose: Typed event structs for JS → Swift messages from the Foliate-js bridge.
// These represent parsed payloads from webkit.messageHandlers callbacks.
//
// @coordinates-with: FoliateMessageParser.swift, FoliateSearchAdapter.swift, FoliateViewCoordinator.swift

import Foundation
import CoreGraphics

// MARK: - Relocate Event

/// Position change reported by Foliate-js `relocate` message handler.
/// Contains CFI, progress fraction, section info, and optional TOC context.
struct FoliateRelocateEvent: Sendable, Equatable {
    let cfi: String
    let fraction: Double
    let sectionIndex: Int
    let sectionTotal: Int
    let tocLabel: String?
    let tocHref: String?
}

// MARK: - Selection Event

/// Text selection reported by Foliate-js `selection` message handler.
/// Contains CFI, selected text, bounding rect, and section index.
struct FoliateSelectionEvent: Sendable, Equatable {
    let cfi: String
    let text: String
    let rect: CGRect
    let sectionIndex: Int
    var context: String? = nil
}

// MARK: - Book Info

/// Metadata + TOC reported by Foliate-js `book-ready` message handler.
/// Emitted once after the book file is successfully parsed.
struct FoliateBookInfo: Sendable, Equatable {
    let title: String
    let author: String
    let language: String
    let sections: Int
    let layout: String
    let toc: [FoliateTOCItem]
}

// MARK: - TOC Item

/// A single table-of-contents entry from Foliate-js.
/// Supports nested subitems for hierarchical TOCs.
struct FoliateTOCItem: Sendable, Equatable {
    let label: String
    let href: String
    let subitems: [FoliateTOCItem]
}

// MARK: - Search Result

/// A single search hit from Foliate-js search.
/// Contains the CFI for navigation, an excerpt for display, and an optional section label.
struct FoliateSearchResult: Sendable, Equatable {
    let cfi: String
    let excerpt: String
    let sectionLabel: String?
}
