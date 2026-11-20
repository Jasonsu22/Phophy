import BackgroundTasks
import Foundation

/// Lets iOS run indexing and describing at night, while the iPhone is on
/// the charger and not in use, so the costly work never drains the battery
/// or slows the app.
enum BackgroundWork {
    static let identifier = "app.phophy.describe"

    /// Must run before the app finishes launching.
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let task = task as? BGProcessingTask else { return }
            let work = Task.detached(priority: .background) {
                let indexStatus = await IndexStatus()
                let describeStatus = await DescribeStatus()
                await PhotoIndexer.shared.run(status: indexStatus)
                await DescriptionService.shared.run(status: describeStatus)
                let left = await describeStatus.toDescribe - describeStatus.described
                if left > 0 { schedule() }
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = {
                work.cancel()
                schedule()
            }
        }
    }

    /// Asks iOS for a run on the charger. Called when the app goes to the background.
    static func schedule() {
        guard AppSettings.describer != .off else { return }
        let request = BGProcessingTaskRequest(identifier: identifier)
        request.requiresExternalPower = true
        request.requiresNetworkConnectivity = AppSettings.describer.isCloud
        try? BGTaskScheduler.shared.submit(request)
    }
}
