//
//  CouncilRunPersistence.swift
//  LLM Council
//

import Foundation

protocol CouncilRunPersisting {
    func loadRuns() -> [CouncilRun]
    func saveRuns(_ runs: [CouncilRun])
}

struct FileCouncilRunPersistence: CouncilRunPersisting {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.fileURL = applicationSupport
                .appendingPathComponent("LLM Council", isDirectory: true)
                .appendingPathComponent("council-runs.json", isDirectory: false)
        }
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder = JSONDecoder()
    }

    func loadRuns() -> [CouncilRun] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? decoder.decode([CouncilRun].self, from: data)) ?? []
    }

    func saveRuns(_ runs: [CouncilRun]) {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try encoder.encode(runs)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // A persistence failure must never corrupt or stop an active council run.
        }
    }
}
