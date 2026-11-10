import Accelerate
import CoreML
import Foundation
import Vision

/// Turns photos and search phrases into vectors that can be compared.
/// Uses Apple's MobileCLIP Core ML models, which are not in git: see
/// PLAN.md ("MobileCLIP models") for the download step. Without them the
/// app still builds and falls back to text-and-label search only.
actor CLIPEncoder {
    static let shared = CLIPEncoder()

    /// The one place the model is chosen. "mobileclip_s0" is small and fast;
    /// switch to "mobileclip_s2" for better accuracy on a real phone.
    nonisolated static let modelName = "mobileclip_s0"

    nonisolated static var isAvailable: Bool {
        modelURL("image") != nil && modelURL("text") != nil
    }

    private var imageModel: MLModel?
    private var textModel: MLModel?
    private var tokenizer: CLIPTokenizer?

    private nonisolated static func modelURL(_ kind: String) -> URL? {
        Bundle.main.url(forResource: "\(modelName)_\(kind)", withExtension: "mlmodelc")
    }

    func embed(image: CGImage) throws -> [Float]? {
        if imageModel == nil, let url = Self.modelURL("image") {
            imageModel = try MLModel(contentsOf: url)
        }
        guard let imageModel,
              let constraint = imageModel.modelDescription.inputDescriptionsByName["image"]?.imageConstraint
        else { return nil }

        let input = try MLFeatureValue(
            cgImage: image,
            constraint: constraint,
            options: [.cropAndScale: VNImageCropAndScaleOption.centerCrop.rawValue]
        )
        let output = try imageModel.prediction(from: MLDictionaryFeatureProvider(dictionary: ["image": input]))
        return Self.normalizedVector(from: output)
    }

    func embed(text: String) throws -> [Float]? {
        if textModel == nil, let url = Self.modelURL("text") {
            textModel = try MLModel(contentsOf: url)
        }
        guard let textModel else { return nil }
        if tokenizer == nil { tokenizer = CLIPTokenizer() }
        guard let tokenizer else { return nil }

        // CLIP reads 77 tokens: a start marker, up to 75 word pieces, an end
        // marker, then zero padding.
        let startToken = 49406, endToken = 49407
        let pieces = tokenizer.encode(text: text).prefix(tokenizer.contextLength - 2)
        let ids = [startToken] + pieces + [endToken]

        let array = try MLMultiArray(shape: [1, NSNumber(value: tokenizer.contextLength)], dataType: .int32)
        for index in 0..<tokenizer.contextLength {
            array[index] = NSNumber(value: index < ids.count ? ids[index] : 0)
        }
        let output = try textModel.prediction(
            from: MLDictionaryFeatureProvider(dictionary: ["text": MLFeatureValue(multiArray: array)])
        )
        return Self.normalizedVector(from: output)
    }

    /// Reads the embedding and scales it to length 1, so that a dot product
    /// between two embeddings is their cosine similarity.
    private static func normalizedVector(from output: MLFeatureProvider) -> [Float]? {
        guard let array = output.featureValue(for: "final_emb_1")?.multiArrayValue else { return nil }
        var vector = (0..<array.count).map { array[$0].floatValue }
        var length: Float = 0
        vDSP_svesq(vector, 1, &length, vDSP_Length(vector.count))
        length = length.squareRoot()
        guard length > 0 else { return nil }
        vDSP_vsdiv(vector, 1, &length, &vector, 1, vDSP_Length(vector.count))
        return vector
    }
}
