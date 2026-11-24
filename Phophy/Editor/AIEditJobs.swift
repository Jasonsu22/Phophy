import Photos
import SwiftUI
import UIKit
import UserNotifications

/// AI photo edits run here, not in the editor screen, so they keep going when
/// the editor closes or the app goes to the background.
///
/// If the editor is still open when the result arrives, it takes the result
/// and the user carries on editing. If the editor was closed, the result is
/// saved to the library as a new photo and the user is told: by the status
/// pill in the app, and by a notification when the app isn't in front.
@MainActor @Observable
final class AIEditJobs {
    static let shared = AIEditJobs()

    struct Job: Identifiable, Equatable {
        enum State: Equatable {
            case running
            /// Saved to the library as a new photo (the editor had closed).
            case saved(localID: String)
            /// Handed to the open editor.
            case delivered
            case failed(String)
        }

        let id = UUID()
        let sourceID: String
        let instruction: String
        let provider: String
        let started = Date.now
        var finished: Date?
        var state = State.running
        /// The editor that started it is gone: save the result as a copy.
        var detached = false
    }

    private(set) var jobs: [Job] = []
    private var results: [UUID: UIImage] = [:]

    /// The job to show in the status pill: one running, or one just finished.
    var current: Job? {
        jobs.last { $0.state == .running } ?? jobs.last { job in
            guard let finished = job.finished, job.state != .delivered else { return false }
            return Date.now.timeIntervalSince(finished) < 8
        }
    }

    /// Starts an edit and returns its id; `result(of:)` waits for it.
    func start(source: UIImage, sourceID: String, instruction: String, service: ImageEditService) -> UUID {
        let job = Job(sourceID: sourceID, instruction: instruction, provider: service.provider.title)
        jobs.append(job)
        requestNotificationPermission()
        let id = job.id
        // Ask iOS for time to finish if the app goes to the background.
        let background = UIApplication.shared.beginBackgroundTask(withName: "AI photo edit")
        Task.detached(priority: .userInitiated) {
            let outcome: Result<UIImage, Error>
            do {
                outcome = .success(try await service.edit(source, instruction: instruction))
            } catch {
                outcome = .failure(error)
            }
            await self.finish(id, with: outcome)
            await MainActor.run { UIApplication.shared.endBackgroundTask(background) }
        }
        return id
    }

    /// Waits for a job's picture. Nil if it failed or the editor let it go.
    func result(of id: UUID) async -> UIImage? {
        while let job = jobs.first(where: { $0.id == id }), job.state == .running, !job.detached, results[id] == nil {
            try? await Task.sleep(for: .milliseconds(200))
        }
        guard let index = jobs.firstIndex(where: { $0.id == id }), !jobs[index].detached else { return nil }
        if let image = results.removeValue(forKey: id) {
            jobs[index].state = .delivered
            return image
        }
        return nil
    }

    func error(of id: UUID) -> String? {
        if case let .failed(message) = jobs.first(where: { $0.id == id })?.state { return message }
        return nil
    }

    /// The editor closed while the job runs: keep going, save the result.
    func detach(_ id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }), jobs[index].state == .running else { return }
        jobs[index].detached = true
    }

    private func finish(_ id: UUID, with outcome: Result<UIImage, Error>) async {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].finished = .now
        switch outcome {
        case let .failure(error):
            jobs[index].state = .failed(error.localizedDescription)
            if jobs[index].detached {
                notify(title: "AI edit didn't work", body: error.localizedDescription)
            }
        case let .success(image):
            if !jobs[index].detached {
                // The open editor picks it up. If nobody does (the editor
                // closed without saying so), it's saved like a detached one.
                results[id] = image
                try? await Task.sleep(for: .seconds(2))
                guard results[id] != nil, let i = jobs.firstIndex(where: { $0.id == id }) else { return }
                results[id] = nil
                jobs[i].detached = true
            }
            guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
            do {
                let localID = try await Self.saveCopy(image, like: jobs[index].sourceID)
                if let i = jobs.firstIndex(where: { $0.id == id }) { jobs[i].state = .saved(localID: localID) }
                notify(title: "AI edit done", body: "“\(jobs[index].instruction)” was saved to your library as a new photo.")
            } catch {
                if let i = jobs.firstIndex(where: { $0.id == id }) {
                    jobs[i].state = .failed("The edit finished but couldn't be saved: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Saves the result next to the original (same date), as a new photo.
    private static func saveCopy(_ image: UIImage, like sourceID: String) async throws -> String {
        guard let data = image.pngData() else { throw ImageEditError.noImage }
        let created = PHAsset.fetchAssets(withLocalIdentifiers: [sourceID], options: nil).firstObject?.creationDate
        var localID: String?
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            let options = PHAssetResourceCreationOptions()
            options.uniformTypeIdentifier = "public.png"
            request.addResource(with: .photo, data: data, options: options)
            request.creationDate = created
            localID = request.placeholderForCreatedAsset?.localIdentifier
        }
        return localID ?? ""
    }

    // MARK: Notifications

    private var askedForNotifications = false

    private func requestNotificationPermission() {
        guard !askedForNotifications else { return }
        askedForNotifications = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Only when the app isn't in front; in the app the status pill says it.
    private func notify(title: String, body: String) {
        guard UIApplication.shared.applicationState != .active else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }
}

/// A small pill above the ask bar while an AI edit runs or just finished,
/// so the user knows it's working wherever they are in the app.
struct AIEditStatusPill: View {
    @State private var jobs = AIEditJobs.shared
    @Environment(PhotoViewerModel.self) private var viewer

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let job = jobs.current {
                content(job, now: context.date)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.smooth, value: jobs.current)
    }

    @ViewBuilder
    private func content(_ job: AIEditJobs.Job, now: Date) -> some View {
        HStack(spacing: 10) {
            switch job.state {
            case .running:
                ProgressView().controlSize(.small)
                Text("Editing with \(job.provider) · \(Int(now.timeIntervalSince(job.started)))s")
                    .monospacedDigit()
            case let .saved(localID):
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("AI edit saved as a new photo")
                if !localID.isEmpty {
                    Button("View") { open(localID) }
                        .fontWeight(.semibold)
                }
            case let .failed(message):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                Text(message).lineLimit(1)
            case .delivered:
                EmptyView()
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
    }

    private func open(_ localID: String) {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [localID], options: nil).firstObject else { return }
        // Already looking at a photo: close it first so the new one opens fresh.
        if viewer.presentation != nil {
            viewer.close()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { viewer.open(.assets([asset]), at: 0) }
        } else {
            viewer.open(.assets([asset]), at: 0)
        }
    }
}
