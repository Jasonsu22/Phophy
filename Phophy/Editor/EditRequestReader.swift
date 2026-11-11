import Foundation
import FoundationModels

/// Reads a typed edit request with Apple Intelligence, on the iPhone and for
/// free, and turns it into editor settings. It understands free wording and
/// other languages, which the word rules in `EditInstructions` don't.
/// Phones without Apple Intelligence, or any failure here, use those rules.
enum EditRequestReader {
    enum Source { case appleIntelligence, wordRules }

    static var canUseAppleIntelligence: Bool {
        AppleIntelligenceStatus.current.isAvailable && AppSettings.useAppleIntelligence
    }

    static func plan(_ request: String, from recipe: EditRecipe) async -> (EditInstructions.Plan, Source) {
        let rules = EditInstructions.plan(request, from: recipe)
        guard canUseAppleIntelligence,
              let reading = try? await askAppleIntelligence(request, from: recipe)
        else { return (rules, .wordRules) }
        return (merge(reading, rules, start: recipe), .appleIntelligence)
    }

    /// Apple's small model understands free wording and other languages but
    /// sometimes misses a part of a request; the word rules are exact but
    /// narrow. Keep everything the model did, add what only the rules caught,
    /// and drop requests for the AI service that the rules can do for free.
    static func merge(_ model: EditInstructions.Plan, _ rules: EditInstructions.Plan, start: EditRecipe) -> EditInstructions.Plan {
        var recipe = model.recipe
        func fill<T: Equatable>(_ keyPath: WritableKeyPath<EditRecipe, T>) {
            if model.recipe[keyPath: keyPath] == start[keyPath: keyPath] {
                recipe[keyPath: keyPath] = rules.recipe[keyPath: keyPath]
            }
        }
        fill(\.autoEnhance); fill(\.exposure); fill(\.contrast); fill(\.saturation); fill(\.warmth)
        fill(\.look); fill(\.quarterTurns); fill(\.aspect)
        // Background words are exact ("remove", "blur", "white"), so the rules win here.
        if rules.recipe.background != start.background { recipe.background = rules.recipe.background }

        let leftover = model.leftover.filter { item in
            let check = EditInstructions.plan(item, from: start)
            return !(check.leftover.isEmpty && !check.applied.isEmpty)
        }
        return EditInstructions.Plan(recipe: recipe, applied: describe(recipe, from: start), leftover: leftover)
    }

    /// What changed, in the user's terms.
    static func describe(_ recipe: EditRecipe, from start: EditRecipe) -> [String] {
        var out: [String] = []
        if recipe.autoEnhance && !start.autoEnhance { out.append("auto enhance") }
        if recipe.exposure != start.exposure { out.append(recipe.exposure > start.exposure ? "brighter" : "darker") }
        if recipe.contrast != start.contrast { out.append(recipe.contrast > start.contrast ? "more contrast" : "less contrast") }
        if recipe.saturation != start.saturation { out.append(recipe.saturation > start.saturation ? "richer colours" : "softer colours") }
        if recipe.warmth != start.warmth { out.append(recipe.warmth > start.warmth ? "warmer" : "cooler") }
        if recipe.look != start.look {
            out.append(recipe.look == .mono ? "black and white" : recipe.look == .instant ? "vintage look" : "\(recipe.look.title.lowercased()) look")
        }
        if recipe.quarterTurns != start.quarterTurns { out.append("rotated") }
        if recipe.aspect != start.aspect { out.append("\(recipe.aspect.title.lowercased()) crop") }
        if recipe.background != start.background {
            switch recipe.background {
            case .keep: break
            case .transparent: out.append("removed the background")
            case .white: out.append("white background")
            case .black: out.append("black background")
            case .blur: out.append("blurred the background")
            }
        }
        return out
    }

    private static let instructions = """
        You turn a person's request for editing one photo into a short list of changes for a \
        simple photo editor. The request may be in any language.

        Kinds of change:
        - enhance: a general fix or improvement.
        - brighter, darker, moreContrast, lessContrast, moreColour, lessColour, warmer, cooler: \
        with strength little, normal or lot.
        - look, with option vivid, mono (black and white), noir, chrome, fade, instant (vintage or film), \
        process or transfer.
        - rotate, with option left, right or upsideDown.
        - crop, with option square, 4:3, 3:4, 16:9 or 9:16.
        - background (everything behind the main subject), with option remove, white, black or blur.

        List every change the person asked for and nothing else. Only use rotate, crop, look or \
        background when the request asks for that.

        Anything else, such as removing or adding a particular person or object, replacing the \
        background with a scene, or fixing faces or text, goes in otherEdits, using the person's \
        own words translated to English. Removing one particular person or object is never a \
        background change.

        Examples:
        "too dark" -> brighter normal
        "make it pop" -> moreContrast normal, moreColour normal
        "it's gloomy, cheer it up" -> brighter normal, warmer little, moreColour little
        "a bit less saturated and cooler" -> lessColour little, cooler normal
        "让它暖一点，背景虚化" -> warmer little, background blur
        "black and white, square for instagram" -> look mono, crop square
        "crop for an instagram story" -> crop 9:16
        "brighter and remove the man on the left" -> brighter normal; otherEdits: remove the man on the left
        "remove the person behind me" -> no changes; otherEdits: remove the person behind me
        "put me on a beach" -> no changes; otherEdits: put me on a beach
        """

    private static func askAppleIntelligence(_ request: String, from recipe: EditRecipe) async throws -> EditInstructions.Plan {
        let session = LanguageModelSession(instructions: instructions)
        let reading = try await session.respond(
            to: "Request: \(request)",
            generating: GeneratedEdit.self
        ).content
        return reading.apply(to: recipe)
    }
}

@Generable
nonisolated struct GeneratedEdit {
    @Guide(description: "Every change the person asked for, and nothing else")
    var changes: [GeneratedChange]
    @Guide(description: "Requested edits the editor cannot do, in the person's words translated to English. Empty if none.")
    var otherEdits: [String]
}

@Generable
nonisolated struct GeneratedChange {
    @Guide(description: "What to change", .anyOf([
        "enhance", "brighter", "darker", "moreContrast", "lessContrast", "moreColour", "lessColour",
        "warmer", "cooler", "look", "rotate", "crop", "background",
    ]))
    var kind: String
    @Guide(description: "How much, for the light and colour changes", .anyOf(["little", "normal", "lot"]))
    var strength: String
    @Guide(description: "For look, rotate, crop and background: the chosen option. Otherwise empty.")
    var option: String
}

extension GeneratedEdit {
    nonisolated func apply(to start: EditRecipe) -> EditInstructions.Plan {
        var recipe = start
        var applied: [String] = []

        func adjust(_ keyPath: WritableKeyPath<EditRecipe, Double>, by step: Double, limit: Double, label: String) {
            recipe[keyPath: keyPath] = min(limit, max(-limit, recipe[keyPath: keyPath] + step))
            if !applied.contains(label) { applied.append(label) }
        }

        for change in changes {
            let option = change.option.trimmingCharacters(in: .whitespaces).lowercased()
            let size = ["little": 0.5, "lot": 1.8][change.strength] ?? 1.0
            switch change.kind {
            case "enhance":
                recipe.autoEnhance = true
                if !applied.contains("auto enhance") { applied.append("auto enhance") }
            case "brighter": adjust(\.exposure, by: 0.4 * size, limit: 2, label: "brighter")
            case "darker": adjust(\.exposure, by: -0.4 * size, limit: 2, label: "darker")
            case "moreContrast": adjust(\.contrast, by: 0.2 * size, limit: 1, label: "more contrast")
            case "lessContrast": adjust(\.contrast, by: -0.2 * size, limit: 1, label: "less contrast")
            case "moreColour": adjust(\.saturation, by: 0.25 * size, limit: 1, label: "richer colours")
            case "lessColour": adjust(\.saturation, by: -0.25 * size, limit: 1, label: "softer colours")
            case "warmer": adjust(\.warmth, by: 0.3 * size, limit: 1, label: "warmer")
            case "cooler": adjust(\.warmth, by: -0.3 * size, limit: 1, label: "cooler")
            case "look":
                let name = option == "black and white" || option == "bw" ? "mono" : option
                if let look = EditRecipe.Look(rawValue: name), look != .none {
                    recipe.look = look
                    applied.append(look == .mono ? "black and white" : "\(look.title.lowercased()) look")
                }
            case "rotate":
                let turns = ["left": 3, "right": 1, "upsidedown": 2, "upside down": 2][option] ?? 0
                if turns != 0 {
                    recipe.quarterTurns = (recipe.quarterTurns + turns) % 4
                    applied.append("rotated")
                }
            case "crop":
                let aspects: [String: EditRecipe.CropAspect] = [
                    "square": .square, "4:3": .fourThree, "3:4": .threeFour, "16:9": .sixteenNine, "9:16": .nineSixteen,
                ]
                if let aspect = aspects[option] {
                    recipe.aspect = aspect
                    applied.append("\(aspect.title.lowercased()) crop")
                }
            case "background":
                switch option {
                case "remove", "transparent", "cut out": recipe.background = .transparent; applied.append("removed the background")
                case "white": recipe.background = .white; applied.append("white background")
                case "black": recipe.background = .black; applied.append("black background")
                case "blur": recipe.background = .blur; applied.append("blurred the background")
                default: break
                }
            default:
                break
            }
        }

        let leftover = otherEdits
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return EditInstructions.Plan(recipe: recipe, applied: applied, leftover: leftover)
    }
}
