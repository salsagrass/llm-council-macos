//
//  WorkspaceChromeState.swift
//  LLM Council
//
//  Created by Codex on 2026-03-08.
//

import Combine
import SwiftUI

enum WorkspaceSidebarSelection: Hashable {
    case workspace
    case providers
    case provider(ProviderID)
    case history
    case presets
    case savedSessions
}

@MainActor
final class WorkspaceChromeState: ObservableObject {
    @Published var sidebarSelection: WorkspaceSidebarSelection? = .workspace
    @Published var selectedProviderID: ProviderID?
    @Published var inspectorPresented = true
    @Published var councilMode: CouncilMode = .compare
    @Published private(set) var activatedProviderIDs: Set<ProviderID> = []

    func selectWorkspace() {
        sidebarSelection = .workspace
        selectedProviderID = nil
    }

    func selectProviders() {
        sidebarSelection = .providers
    }

    func selectProvider(_ providerID: ProviderID) {
        sidebarSelection = .provider(providerID)
        selectedProviderID = providerID
    }

    func revealSection(_ selection: WorkspaceSidebarSelection) {
        sidebarSelection = selection
    }

    func activateProvider(_ providerID: ProviderID) {
        activatedProviderIDs.insert(providerID)
    }

    func activateProviders(_ providerIDs: [ProviderID]) {
        activatedProviderIDs.formUnion(providerIDs)
    }

    func syncActivatedProviders(from paneStates: [ProviderID: ProviderPaneState]) {
        let active = paneStates.values.compactMap { paneState -> ProviderID? in
            if let url = paneState.lastKnownURLString?.trimmingCharacters(in: .whitespacesAndNewlines),
               !url.isEmpty
            {
                return paneState.providerID
            }
            return nil
        }
        activatedProviderIDs.formUnion(active)
    }

    func isProviderActivated(_ providerID: ProviderID) -> Bool {
        activatedProviderIDs.contains(providerID)
    }
}
