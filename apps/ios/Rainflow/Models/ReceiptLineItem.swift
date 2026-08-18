import Foundation
import RainflowDomain

/// Provider-neutral receipt detail that can be persisted in Supabase today and
/// mapped to another relational backend (for example D1) without changing the
/// app-facing model.
struct ReceiptLineItem: Codable, Equatable, Hashable, Sendable {
    let description: String
    let amountMinorUnits: Int64?
    let quantity: Double?
    let unitPriceMinorUnits: Int64?
}

enum ReceiptLineItemParser {
    private static let amountPattern = #"[$€£¥]?\s*([0-9]{1,3}(?:,[0-9]{3})*|[0-9]+)(?:[\.,]([0-9]{1,2}))?"#

    static func parse(lines: [String], currency: CurrencyCode) -> [ReceiptLineItem] {
        lines
            .compactMap { parse(line: $0, currency: currency) }
            .prefix(50)
            .map { $0 }
    }

    static func parse(line: String, currency: CurrencyCode) -> ReceiptLineItem? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let regex = try? NSRegularExpression(pattern: amountPattern),
              let amountMatch = regex.matches(
                in: trimmed,
                range: NSRange(trimmed.startIndex..., in: trimmed)
              ).last,
              let amountRange = Range(amountMatch.range, in: trimmed),
              let amountMinorUnits = minorUnits(from: String(trimmed[amountRange]), currency: currency) else {
            return nil
        }

        var detailText = trimmed
        detailText.removeSubrange(amountRange)
        detailText = detailText.trimmingCharacters(in: .whitespacesAndNewlines)

        let quantityInfo = parseQuantityAndUnitPrice(detailText, currency: currency)
        let description = sanitizeDescription(quantityInfo?.description ?? detailText)
        guard !description.isEmpty else { return nil }

        return ReceiptLineItem(
            description: description,
            amountMinorUnits: amountMinorUnits,
            quantity: quantityInfo?.quantity,
            unitPriceMinorUnits: quantityInfo?.unitPriceMinorUnits
        )
    }

    private static func parseQuantityAndUnitPrice(
        _ text: String,
        currency: CurrencyCode
    ) -> (description: String, quantity: Double, unitPriceMinorUnits: Int64)? {
        let patterns = [
            #"(?i)^(.+?)\s+(\d+(?:\.\d+)?)\s*[x@]\s*([$€£¥]?\s*\d+(?:[\.,]\d{1,2})?)$"#,
            #"(?i)^(\d+(?:\.\d+)?)\s*[x@]\s*([$€£¥]?\s*\d+(?:[\.,]\d{1,2})?)\s+(.+)$"#
        ]

        for (index, pattern) in patterns.enumerated() {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(
                    in: text,
                    range: NSRange(text.startIndex..., in: text)
                  ),
                  match.range.location != NSNotFound else { continue }

            let descriptionGroup = index == 0 ? 1 : 3
            let quantityGroup = index == 0 ? 2 : 1
            let unitPriceGroup = index == 0 ? 3 : 2

            guard let descriptionRange = Range(match.range(at: descriptionGroup), in: text),
                  let quantityRange = Range(match.range(at: quantityGroup), in: text),
                  let unitPriceRange = Range(match.range(at: unitPriceGroup), in: text),
                  let quantity = Double(text[quantityRange]),
                  quantity > 0,
                  let unitPriceMinorUnits = minorUnits(
                    from: String(text[unitPriceRange]),
                    currency: currency
                  ) else { continue }

            return (
                String(text[descriptionRange]),
                quantity,
                unitPriceMinorUnits
            )
        }

        return nil
    }

    private static func minorUnits(from value: String, currency: CurrencyCode) -> Int64? {
        var normalized = value
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: "£", with: "")
            .replacingOccurrences(of: "¥", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if currency.minorUnitScale == 0 {
            normalized = normalized.components(separatedBy: ".").first ?? normalized
            return Int64(normalized)
        }

        let components = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count <= 2,
              let whole = Int64(components[0]) else { return nil }

        let fractionText = components.count == 2 ? String(components[1]) : ""
        let padded = String(fractionText.prefix(currency.minorUnitScale))
            .padding(toLength: currency.minorUnitScale, withPad: "0", startingAt: 0)
        guard let fraction = Int64(padded) else { return nil }

        let scale = Int64(pow(10.0, Double(currency.minorUnitScale)))
        let (wholeScaled, overflow) = whole.multipliedReportingOverflow(by: scale)
        guard !overflow else { return nil }
        let (total, addOverflow) = wholeScaled.addingReportingOverflow(fraction)
        guard !addOverflow, total > 0 else { return nil }
        return total
    }

    private static func sanitizeDescription(_ value: String) -> String {
        String(
            value
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: " -–—:@xX"))
                .prefix(240)
        )
    }
}
