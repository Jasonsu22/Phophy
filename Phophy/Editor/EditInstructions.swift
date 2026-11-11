import Foundation

/// Reads a typed edit request such as "make it brighter and remove the
/// background" and does what it can with the free on-device tools. Only
/// the parts it does not understand are offered to a paid AI image service.
nonisolated enum EditInstructions {
    struct Plan: Equatable {
        var recipe: EditRecipe
        /// Short descriptions of what was applied, for the user.
        var applied: [String] = []
        /// Parts of the request that need an AI image service.
        var leftover: [String] = []
    }

    static func plan(_ request: String, from recipe: EditRecipe) -> Plan {
        var plan = Plan(recipe: recipe)
        for clause in clauses(of: request) {
            if !apply(clause, to: &plan) {
                plan.leftover.append(clause)
            }
        }
        return plan
    }

    /// Splits on "and", "then", commas and full stops.
    static func clauses(of request: String) -> [String] {
        var text = " " + request.lowercased() + " "
        // Keep phrases that contain "and" in one piece.
        for phrase in ["black and white", "black & white"] {
            text = text.replacingOccurrences(of: phrase, with: "black-white")
        }
        for joiner in [" and then ", " and ", " then ", " also ", " plus "] {
            text = text.replacingOccurrences(of: joiner, with: ",")
        }
        return text
            .split(whereSeparator: { ",.;!\n".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static func has(_ text: String, _ words: [String]) -> Bool {
        words.contains { text.contains($0) }
    }

    /// Returns false when the clause is not something the on-device tools do.
    private static func apply(_ clause: String, to plan: inout Plan) -> Bool {
        let strong = has(clause, ["much ", "a lot", "way ", "very ", "really "])
        let gentle = has(clause, ["a bit", "a little", "slightly", "a touch"])
        let step = strong ? 2.0 : gentle ? 0.5 : 1.0
        let reduce = has(clause, ["less ", "reduce", "lower", "decrease", "tone down", "remove the color", "no color"])

        // Background: remove, replace or blur it.
        if has(clause, ["background", "backdrop", "cut out", "cutout", "cut-out", "sticker"]) {
            if has(clause, ["blur", "bokeh", "portrait"]) {
                plan.recipe.background = .blur
                plan.applied.append("blurred the background")
            } else if has(clause, ["white"]) {
                plan.recipe.background = .white
                plan.applied.append("white background")
            } else if has(clause, ["black"]) {
                plan.recipe.background = .black
                plan.applied.append("black background")
            } else if has(clause, ["remove", "delete", "get rid", "cut out", "cutout", "cut-out", "sticker", "transparent", "erase"]) {
                plan.recipe.background = .transparent
                plan.applied.append("removed the background")
            } else {
                // "Make the background a beach": a job for the AI service.
                return false
            }
            return true
        }

        if has(clause, ["black-white", "b&w", "b/w", "monochrome", "grayscale", "greyscale", "mono"]) {
            plan.recipe.look = .mono
            plan.applied.append("black and white")
            return true
        }
        if has(clause, ["noir"]) { plan.recipe.look = .noir; plan.applied.append("noir look"); return true }
        if has(clause, ["vintage", "retro", "film", "sepia", "old photo"]) {
            plan.recipe.look = .instant
            plan.applied.append("vintage look")
            return true
        }
        if has(clause, ["faded", "fade", "washed out"]) { plan.recipe.look = .fade; plan.applied.append("faded look"); return true }

        if has(clause, ["enhance", "auto", "fix the light", "fix lighting", "improve", "better", "fix it", "fix this"]) {
            plan.recipe.autoEnhance = true
            plan.applied.append("auto enhance")
            return true
        }
        if has(clause, ["brighter", "brighten", "lighter", "lighten", "too dark", "more light", "exposure up"]) {
            plan.recipe.exposure = min(2, plan.recipe.exposure + 0.4 * step)
            plan.applied.append("brighter")
            return true
        }
        if has(clause, ["darker", "darken", "too bright", "dimmer", "exposure down"]) {
            plan.recipe.exposure = max(-2, plan.recipe.exposure - 0.4 * step)
            plan.applied.append("darker")
            return true
        }
        if has(clause, ["contrast", "punch", "pop"]) {
            let change = (reduce || has(clause, ["flatter", "softer"])) ? -0.2 : 0.2
            plan.recipe.contrast = min(1, max(-1, plan.recipe.contrast + change * step))
            plan.applied.append(change > 0 ? "more contrast" : "less contrast")
            return true
        }
        if has(clause, ["saturat", "colorful", "colourful", "vivid", "vibrant", "more color", "more colour", "muted", "dull"]) {
            let down = reduce || has(clause, ["muted", "dull", "desaturat"])
            plan.recipe.saturation = min(1, max(-1, plan.recipe.saturation + (down ? -0.25 : 0.25) * step))
            plan.applied.append(down ? "softer colours" : "richer colours")
            return true
        }
        if has(clause, ["warmer", "warm ", "warm", "golden", "sunnier"]) && !has(clause, ["less warm"]) {
            plan.recipe.warmth = min(1, plan.recipe.warmth + 0.3 * step)
            plan.applied.append("warmer")
            return true
        }
        if has(clause, ["cooler", "colder", "cool ", "bluer", "less warm"]) {
            plan.recipe.warmth = max(-1, plan.recipe.warmth - 0.3 * step)
            plan.applied.append("cooler")
            return true
        }
        if has(clause, ["rotate", "turn it", "sideways", "upside down"]) {
            let turns = has(clause, ["upside down", "180"]) ? 2 : has(clause, ["left", "counter", "anti"]) ? 3 : 1
            plan.recipe.quarterTurns = (plan.recipe.quarterTurns + turns) % 4
            plan.applied.append("rotated")
            return true
        }
        if has(clause, ["square"]) { plan.recipe.aspect = .square; plan.applied.append("square crop"); return true }
        if has(clause, ["16:9", "widescreen", "wide crop"]) { plan.recipe.aspect = .sixteenNine; plan.applied.append("16:9 crop"); return true }
        if has(clause, ["9:16", "story", "vertical crop", "portrait crop"]) { plan.recipe.aspect = .nineSixteen; plan.applied.append("9:16 crop"); return true }
        if has(clause, ["4:3"]) { plan.recipe.aspect = .fourThree; plan.applied.append("4:3 crop"); return true }

        // Filler like "please" or "make this" on its own.
        let filler: Set<String> = ["please", "make it", "make this", "can you", "thanks", "thank you"]
        if filler.contains(clause) { return true }
        return false
    }
}
