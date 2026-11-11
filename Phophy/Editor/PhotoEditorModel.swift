import CoreImage
import Photos
import SwiftUI

/// Wraps Core Image values so they can move to a background task. Core
/// Image images are immutable and its context is thread-safe.
private nonisolated final class Unchecked<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

nonisolated enum EditRendering {
    static let context = CIContext(options: [.cacheIntermediates: false])

    static func cgImage(_ image: CIImage) -> CGImage? {
        context.createCGImage(image, from: image.extent)
    }

    static func downscaled(_ image: CIImage, longSide: CGFloat) -> CIImage {
        let factor = longSide / max(image.extent.width, image.extent.height)
        guard factor < 1 else { return image }
        return image.transformed(by: CGAffineTransform(scaleX: factor, y: factor), highQualityDownsample: true)
    }
}

/// State and work behind the photo editor: loads the photo, renders the
/// preview as settings change, finds the subject, calls the AI image service
/// when asked, and saves back to Photos.
@Observable
final class PhotoEditorModel {
    enum Phase: Equatable {
        case loading
        case ready
        case working(String)
        case failed(String)
    }

    let asset: PHAsset
    var recipe = EditRecipe() { didSet { if recipe != oldValue { recipeChanged(from: oldValue) } } }
    private(set) var phase = Phase.loading
    private(set) var preview: UIImage?
    /// The untouched picture, for press-and-hold comparison.
    private(set) var originalPreview: UIImage?
    /// One-line feedback after a typed request or a failed step.
    var message: String?
    private(set) var canUndoGenerated = false
    private(set) var hasSavedEdits = false

    @ObservationIgnored private var input: PHContentEditingInput?
    @ObservationIgnored private var previewBase: CIImage?
    @ObservationIgnored private var previewMask: CIImage?
    /// Set once an AI service has produced a new starting picture.
    @ObservationIgnored private var generatedBase: CIImage?
    @ObservationIgnored private var generatedHistory: [CIImage?] = []
    @ObservationIgnored private var renderTask: Task<Void, Never>?

    static let previewLongSide: CGFloat = 1600

    init(asset: PHAsset) {
        self.asset = asset
    }

    var isBusy: Bool {
        if case .working = phase { return true }
        return phase == .loading
    }

    var hasChanges: Bool { !recipe.isIdentity || generatedBase != nil }

    // MARK: Loading

    func load() async {
        let options = PHContentEditingInputRequestOptions()
        options.isNetworkAccessAllowed = true
        // Reopen our own earlier edits as settings, unless an AI service made
        // them: those can't be replayed, so we start from the saved picture.
        options.canHandleAdjustmentData = { data in
            guard data.formatIdentifier == EditRecipe.formatIdentifier,
                  data.formatVersion == EditRecipe.formatVersion,
                  let recipe = try? JSONDecoder().decode(EditRecipe.self, from: data.data)
            else { return false }
            return !recipe.includesGenerated
        }
        let input = await withCheckedContinuation { continuation in
            asset.requestContentEditingInput(with: options) { input, _ in
                continuation.resume(returning: input)
            }
        }
        guard let input, let url = input.fullSizeImageURL,
              let full = CIImage(contentsOf: url, options: [.applyOrientationProperty: true])
        else {
            phase = .failed("This photo couldn't be opened for editing. If it is only in iCloud, check your connection.")
            return
        }
        self.input = input
        hasSavedEdits = PHAssetResource.assetResources(for: asset).contains { $0.type == .adjustmentData }

        if let data = input.adjustmentData,
           data.formatIdentifier == EditRecipe.formatIdentifier,
           let saved = try? JSONDecoder().decode(EditRecipe.self, from: data.data) {
            recipe = saved
        }

        let base = EditRendering.downscaled(full, longSide: Self.previewLongSide)
        previewBase = base
        let boxed = Unchecked(base)
        originalPreview = await Task.detached { EditRendering.cgImage(boxed.value).map { UIImage(cgImage: $0) } }.value
        phase = .ready
        if recipe.background != .keep { await ensurePreviewMask() }
        render()
    }

    // MARK: Preview

    private func recipeChanged(from old: EditRecipe) {
        guard previewBase != nil else { return }
        if recipe.background != .keep && previewMask == nil {
            Task {
                await ensurePreviewMask()
                render()
            }
        }
        render()
    }

    private var currentBase: CIImage? { generatedBase ?? previewBase }

    /// Re-renders the preview, dropping a render that is overtaken.
    func render() {
        guard let base = currentBase else { return }
        renderTask?.cancel()
        let inputs = Unchecked((recipe, base, previewMask))
        renderTask = Task {
            let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
                let (recipe, base, mask) = inputs.value
                let edited = EditPipeline.apply(recipe, to: base, mask: recipe.background == .keep ? nil : mask)
                return EditRendering.cgImage(edited).map { UIImage(cgImage: $0) }
            }.value
            guard !Task.isCancelled, let image else { return }
            preview = image
        }
    }

    private func ensurePreviewMask() async {
        guard previewMask == nil, let base = currentBase else { return }
        let previous = phase
        phase = .working("Finding the subject…")
        let boxed = Unchecked(base)
        let outcome = await Task.detached(priority: .userInitiated) { () -> Unchecked<(CIImage?, Bool)> in
            guard let cg = EditRendering.cgImage(boxed.value) else { return Unchecked((nil, false)) }
            do {
                return Unchecked((try EditPipeline.subjectMask(for: cg), false))
            } catch {
                #if DEBUG
                fputs("subject mask failed: \(error)\n", stderr)
                #endif
                return Unchecked((nil, true))
            }
        }.value.value
        phase = previous == .loading ? .ready : (previous.isWorking ? .ready : previous)
        if let mask = outcome.0 {
            previewMask = mask
        } else {
            // Vision throws when it can't run at all, as in the simulator.
            message = outcome.1
                ? "Subject detection isn't available on this device."
                : "Couldn't find a clear subject to separate from the background."
            recipe.background = .keep
        }
    }

    // MARK: Typed requests

    /// Applies what the free tools can do. Returns the parts that need an AI
    /// image service, for the view to offer (each costs money).
    func applyRequest(_ text: String) async -> [String] {
        phase = .working(EditRequestReader.canUseAppleIntelligence ? "Reading your request…" : "Applying…")
        let (plan, source) = await EditRequestReader.plan(text, from: recipe)
        phase = .ready
        recipe = plan.recipe
        if plan.applied.isEmpty && plan.leftover.isEmpty {
            message = "Nothing in that request matched what the editor can do. Try describing the light, colours, crop or background."
        } else if plan.applied.isEmpty {
            message = nil
        } else {
            message = "Done on your iPhone: " + plan.applied.joined(separator: ", ") + "."
        }
        #if DEBUG
        fputs("edit request (\(source)): \(text) -> applied \(plan.applied), leftover \(plan.leftover)\n", stderr)
        #endif
        return plan.leftover
    }

    /// Sends the current starting picture and the request to the AI image
    /// service. The result becomes the new starting picture; light, colour,
    /// crop and background settings still apply on top.
    func generate(_ instruction: String) async {
        guard let base = currentBase else { return }
        let service: ImageEditService
        do {
            service = try ImageEditService.current()
        } catch {
            message = error.localizedDescription
            return
        }
        phase = .working("Editing with \(service.provider.title)…")
        defer { if phase.isWorking { phase = .ready } }

        let boxed = Unchecked(base)
        let source = await Task.detached { EditRendering.cgImage(boxed.value).map { UIImage(cgImage: $0) } }.value
        guard let source else { return }
        do {
            let result = try await service.edit(source, instruction: instruction)
            guard let cg = result.cgImage ?? CIImage(image: result).flatMap(EditRendering.cgImage) else {
                throw ImageEditError.noImage
            }
            generatedHistory.append(generatedBase)
            generatedBase = CIImage(cgImage: cg)
            canUndoGenerated = true
            previewMask = nil
            recipe.includesGenerated = true
            if recipe.background != .keep { await ensurePreviewMask() }
            message = "Edited with \(service.provider.title): \(instruction)."
            render()
        } catch {
            message = error.localizedDescription
        }
    }

    func undoGenerated() {
        guard let previous = generatedHistory.popLast() else { return }
        generatedBase = previous
        canUndoGenerated = !generatedHistory.isEmpty
        message = "Undid the AI edit."
        recipe.includesGenerated = generatedBase != nil
        previewMask = nil
        if recipe.background != .keep {
            Task { await ensurePreviewMask(); render() }
        }
        render()
    }

    func resetAll() {
        generatedBase = nil
        generatedHistory = []
        canUndoGenerated = false
        previewMask = nil
        recipe = EditRecipe()
        message = nil
        render()
    }

    // MARK: Saving

    enum SaveResult { case updatedOriginal, savedCopy }

    /// Writes the edit. Normally the photo itself is updated and Photos keeps
    /// the original, so the edit can be reverted. A cut-out needs see-through
    /// pixels, which a JPEG can't hold, so it is added as a new PNG photo.
    func save() async -> SaveResult? {
        guard let input, let url = input.fullSizeImageURL else { return nil }
        phase = .working("Saving…")
        defer { if phase.isWorking { phase = .ready } }

        let recipe = self.recipe
        let generated = generatedBase.map(Unchecked.init)
        let rendered = await Task.detached(priority: .userInitiated) { () -> Unchecked<CIImage?> in
            // Full resolution unless an AI service made the picture; its result
            // is already at the size the service works at.
            let base: CIImage
            if let generated {
                base = generated.value
            } else if let full = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) {
                base = full
            } else {
                return Unchecked(nil)
            }
            var mask: CIImage?
            if recipe.background != .keep {
                // Find the subject on a smaller copy; the mask is scaled to fit.
                let small = EditRendering.downscaled(base, longSide: 2048)
                if let cg = EditRendering.cgImage(small) { mask = try? EditPipeline.subjectMask(for: cg) }
            }
            return Unchecked(EditPipeline.apply(recipe, to: base, mask: mask))
        }.value.value

        guard let rendered else {
            message = "The edit couldn't be rendered."
            return nil
        }

        do {
            if recipe.background.needsTransparency {
                try await saveCopy(rendered)
                message = "Saved the cut-out as a new photo. The original is unchanged."
                return .savedCopy
            }
            try await saveOver(rendered, input: input, recipe: recipe)
            hasSavedEdits = true
            return .updatedOriginal
        } catch {
            message = "Couldn't save: \(error.localizedDescription)"
            return nil
        }
    }

    private func saveOver(_ image: CIImage, input: PHContentEditingInput, recipe: EditRecipe) async throws {
        let output = PHContentEditingOutput(contentEditingInput: input)
        output.adjustmentData = PHAdjustmentData(
            formatIdentifier: EditRecipe.formatIdentifier,
            formatVersion: EditRecipe.formatVersion,
            data: try JSONEncoder().encode(recipe)
        )
        let boxed = Unchecked(image)
        let destination = output.renderedContentURL
        try await Task.detached(priority: .userInitiated) {
            let space = CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
            guard let jpeg = EditRendering.context.jpegRepresentation(
                of: boxed.value, colorSpace: space,
                options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.92]
            ) else { throw ImageEditError.noImage }
            try jpeg.write(to: destination)
        }.value
        let asset = self.asset
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest(for: asset).contentEditingOutput = output
        }
        Self.announceEdit(of: asset)
    }

    /// Tells the rest of the app the picture changed, so thumbnails,
    /// previews and the search index catch up.
    private static func announceEdit(of asset: PHAsset) {
        NotificationCenter.default.post(
            name: .phophyPhotoEdited, object: nil, userInfo: ["localIDs": [asset.localIdentifier]]
        )
    }

    private func saveCopy(_ image: CIImage) async throws {
        let boxed = Unchecked(image)
        let png = await Task.detached(priority: .userInitiated) { () -> Data? in
            let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
            return EditRendering.context.pngRepresentation(of: boxed.value, format: .RGBA8, colorSpace: space)
        }.value
        guard let png else { throw ImageEditError.noImage }
        let created = asset.creationDate
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCreationRequest.forAsset()
            let options = PHAssetResourceCreationOptions()
            options.uniformTypeIdentifier = "public.png"
            request.addResource(with: .photo, data: png, options: options)
            request.creationDate = created
        }
    }

    /// Puts the photo back as it was taken, in Photos too.
    func revertToOriginal() async -> Bool {
        let asset = self.asset
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest(for: asset).revertAssetContentToOriginal()
            }
            Self.announceEdit(of: asset)
            hasSavedEdits = false
            return true
        } catch {
            message = "Couldn't revert: \(error.localizedDescription)"
            return false
        }
    }
}

private extension PhotoEditorModel.Phase {
    var isWorking: Bool {
        if case .working = self { return true }
        return false
    }
}
