import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import Vision

/// Everything the user changed in the editor, as settings rather than
/// pixels. Saved with the photo as adjustment data, so Photos keeps the
/// original and the edit can be reopened, changed or reverted later.
nonisolated struct EditRecipe: Codable, Equatable, Sendable {
    static let formatIdentifier = "app.phophy.edit"
    static let formatVersion = "1"

    var autoEnhance = false
    /// Exposure in stops, -2...2.
    var exposure: Double = 0
    /// -1...1 for each of these.
    var contrast: Double = 0
    var saturation: Double = 0
    var warmth: Double = 0
    var look: Look = .none
    /// Clockwise quarter turns, 0...3.
    var quarterTurns = 0
    var aspect: CropAspect = .original
    var background: BackgroundMode = .keep
    /// True when an AI image service produced the starting picture. Such an
    /// edit cannot be replayed from the original, so Photos stores it flat.
    var includesGenerated = false

    var isIdentity: Bool {
        var plain = EditRecipe()
        plain.includesGenerated = includesGenerated
        return self == plain && !includesGenerated
    }

    enum Look: String, Codable, CaseIterable, Identifiable, Sendable {
        case none, vivid, mono, noir, chrome, fade, instant, process, transfer
        var id: Self { self }
        var title: String {
            switch self {
            case .none: "Original"
            case .vivid: "Vivid"
            case .mono: "Mono"
            case .noir: "Noir"
            case .chrome: "Chrome"
            case .fade: "Fade"
            case .instant: "Instant"
            case .process: "Process"
            case .transfer: "Transfer"
            }
        }
        fileprivate var filterName: String? {
            switch self {
            case .none, .vivid: nil
            case .mono: "CIPhotoEffectMono"
            case .noir: "CIPhotoEffectNoir"
            case .chrome: "CIPhotoEffectChrome"
            case .fade: "CIPhotoEffectFade"
            case .instant: "CIPhotoEffectInstant"
            case .process: "CIPhotoEffectProcess"
            case .transfer: "CIPhotoEffectTransfer"
            }
        }
    }

    enum CropAspect: String, Codable, CaseIterable, Identifiable, Sendable {
        case original, square, fourThree, threeFour, sixteenNine, nineSixteen
        var id: Self { self }
        var title: String {
            switch self {
            case .original: "Original"
            case .square: "Square"
            case .fourThree: "4:3"
            case .threeFour: "3:4"
            case .sixteenNine: "16:9"
            case .nineSixteen: "9:16"
            }
        }
        /// Width divided by height, or nil to keep the photo's own shape.
        fileprivate var ratio: CGFloat? {
            switch self {
            case .original: nil
            case .square: 1
            case .fourThree: 4.0 / 3
            case .threeFour: 3.0 / 4
            case .sixteenNine: 16.0 / 9
            case .nineSixteen: 9.0 / 16
            }
        }
    }

    enum BackgroundMode: String, Codable, CaseIterable, Identifiable, Sendable {
        case keep, transparent, white, black, blur
        var id: Self { self }
        var title: String {
            switch self {
            case .keep: "Keep"
            case .transparent: "Cut out"
            case .white: "White"
            case .black: "Black"
            case .blur: "Blur"
            }
        }
        /// A cut-out has see-through pixels, which a JPEG cannot hold, so it
        /// is saved as a new PNG photo instead of changing the original.
        var needsTransparency: Bool { self == .transparent }
    }
}

/// Turns a picture plus a recipe into the edited picture. Pure Core Image,
/// on the device, free.
nonisolated enum EditPipeline {
    static func apply(_ recipe: EditRecipe, to base: CIImage, mask: CIImage?) -> CIImage {
        var image = base
        let extent = base.extent

        // 1. Background, while the mask still lines up with the photo.
        if recipe.background != .keep, let mask {
            let fitted = mask.transformed(by: CGAffineTransform(
                scaleX: extent.width / mask.extent.width,
                y: extent.height / mask.extent.height
            ))
            let backdrop: CIImage = switch recipe.background {
            case .keep, .transparent: CIImage(color: .clear).cropped(to: extent)
            case .white: CIImage(color: .white).cropped(to: extent)
            case .black: CIImage(color: .black).cropped(to: extent)
            case .blur:
                image.clampedToExtent()
                    .applyingGaussianBlur(sigma: max(extent.width, extent.height) / 60)
                    .cropped(to: extent)
            }
            let blend = CIFilter.blendWithMask()
            blend.inputImage = image
            blend.backgroundImage = backdrop
            blend.maskImage = fitted
            image = blend.outputImage?.cropped(to: extent) ?? image
        }

        // 2. Light and colour.
        if recipe.autoEnhance {
            for filter in image.autoAdjustmentFilters(options: [.redEye: false]) {
                filter.setValue(image, forKey: kCIInputImageKey)
                image = filter.outputImage ?? image
            }
        }
        if recipe.exposure != 0 {
            let filter = CIFilter.exposureAdjust()
            filter.inputImage = image
            filter.ev = Float(recipe.exposure)
            image = filter.outputImage ?? image
        }
        let vividBoost = recipe.look == .vivid ? 0.35 : 0
        if recipe.contrast != 0 || recipe.saturation != 0 || vividBoost != 0 {
            let filter = CIFilter.colorControls()
            filter.inputImage = image
            filter.contrast = Float(1 + recipe.contrast * 0.5 + vividBoost * 0.2)
            filter.saturation = Float(max(0, 1 + recipe.saturation + vividBoost))
            filter.brightness = 0
            image = filter.outputImage ?? image
        }
        if recipe.warmth != 0 {
            // Telling Core Image the light was bluer than it was warms the
            // picture up, and the other way round.
            let filter = CIFilter.temperatureAndTint()
            filter.inputImage = image
            filter.neutral = CIVector(x: 6500 + recipe.warmth * 2500, y: 0)
            filter.targetNeutral = CIVector(x: 6500, y: 0)
            image = filter.outputImage ?? image
        }
        if let name = recipe.look.filterName, let filter = CIFilter(name: name) {
            filter.setValue(image, forKey: kCIInputImageKey)
            image = filter.outputImage ?? image
        }
        image = image.cropped(to: extent)

        // 3. Rotate, then crop to the chosen shape around the centre.
        let turns = ((recipe.quarterTurns % 4) + 4) % 4
        if turns != 0 {
            let orientation: CGImagePropertyOrientation = [.up, .right, .down, .left][turns]
            image = image.oriented(orientation)
        }
        if let ratio = recipe.aspect.ratio {
            let box = image.extent
            var width = box.width, height = box.height
            if width / height > ratio { width = height * ratio } else { height = width / ratio }
            let crop = CGRect(
                x: box.midX - width / 2, y: box.midY - height / 2, width: width, height: height
            ).integral
            image = image.cropped(to: crop)
        }
        // Start at the origin, which savers and Vision expect.
        return image.transformed(by: CGAffineTransform(
            translationX: -image.extent.origin.x, y: -image.extent.origin.y
        ))
    }

    /// The main subject of a photo (people, pets, objects) as a grayscale
    /// mask: white where the subject is. Uses Vision on the device.
    static func subjectMask(for image: CGImage) throws -> CIImage? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image)
        try handler.perform([request])
        guard let observation = request.results?.first,
              !observation.allInstances.isEmpty
        else { return nil }
        let buffer = try observation.generateScaledMaskForImage(
            forInstances: observation.allInstances, from: handler
        )
        return CIImage(cvPixelBuffer: buffer)
    }
}
