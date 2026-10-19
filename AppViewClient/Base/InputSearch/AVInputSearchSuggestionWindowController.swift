//
//  AVInputSearchSuggestionWindowController.swift
//  AppView
//

import AppKit

class AVInputSearchSuggestionWindowController: AVWindowController {
    var suggestionsView: AVInputSearchSuggestionsContentView!

    convenience init() {
        let view = AVInputSearchSuggestionsContentView()
        let suggestionPanel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 100),
            styleMask: [.utilityWindow],
            backing: .buffered,
            defer: true
        )
        suggestionPanel.contentView = view
        suggestionPanel.isFloatingPanel = true
        suggestionPanel.becomesKeyOnlyIfNeeded = true
        suggestionPanel.backgroundColor = .clear
        self.init(window: suggestionPanel)
        suggestionsView = view
    }
}
