import Foundation
import ImageIO
import RainflowDomain
import UIKit
import Vision

struct ReceiptExtractionResult: Sendable {
    let amountMinorUnits: Int64?
    let merchantName: String?
    let accountingDate: Date?
    let lineItems: [String]
}

enum ReceiptTextExtractor {
    private struct ParsedAmount {
        let minorUnits: Int64
        let hasCurrencySymbol: Bool
        let hasFraction: Bool
    }

    static func extract(from imageData: Data, currency: CurrencyCode) async -> ReceiptExtractionResult {
        guard let image = UIImage(data: imageData),
              let cgImage = image.cgImage else {
            return ReceiptExtractionResult(amountMinorUnits: nil, merchantName: nil, accountingDate: nil, lineItems: [])
        }

        let lines = (try? await recognizeText(in: cgImage, orientation: image.cgImageOrientation)) ?? []
        return parse(lines: lines, currency: currency)
    }

    static func parse(lines: [String], currency: CurrencyCode) -> ReceiptExtractionResult {
        let cleanedLines = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let merchant = likelyMerchant(from: cleanedLines)
        let amount = likelyTotalMinorUnits(from: cleanedLines, currency: currency)
        let date = likelyReceiptDate(from: cleanedLines)
        let items = likelyLineItems(from: cleanedLines)

        return ReceiptExtractionResult(
            amountMinorUnits: amount,
            merchantName: merchant,
            accountingDate: date,
            lineItems: items
        )
    }

    private static func recognizeText(in image: CGImage, orientation: CGImagePropertyOrientation) async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let lines = (request.results as? [VNRecognizedTextObservation])?
                    .compactMap { $0.topCandidates(1).first?.string } ?? []
                continuation.resume(returning: lines)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: image, orientation: orientation)
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private static func likelyMerchant(from lines: [String]) -> String? {
        for line in lines.prefix(8) {
            let normalized = line.lowercased()
            if normalized.contains("receipt")
                || normalized.contains("invoice")
                || normalized.contains("welcome")
                || normalized.contains("thank")
                || normalized.contains("www.")
                || normalized.contains("http")
                || normalized.contains("tel")
                || normalized.contains("phone")
                || normalized.contains("@")
                || containsAmount(line)
                || containsDateLikeText(line) {
                continue
            }

            let trimmed = line
                .replacingOccurrences(of: "#", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count >= 2 {
                return String(trimmed.prefix(40))
            }
        }
        return nil
    }

    private static func likelyTotalMinorUnits(from lines: [String], currency: CurrencyCode) -> Int64? {
        var best: (score: Int, amount: Int64)?

        for (index, line) in lines.enumerated() {
            guard !isNeverMoneyLine(line),
                  !containsDateLikeText(line) else { continue }

            for amount in parsedAmounts(in: line, currency: currency) {
                let score = amountScore(line: line, amount: amount, index: index)
                guard score > 0 else { continue }

                if let current = best {
                    if score > current.score || (score == current.score && amount.minorUnits > current.amount) {
                        best = (score, amount.minorUnits)
                    }
                } else {
                    best = (score, amount.minorUnits)
                }
            }
        }

        if let best {
            return best.amount
        }

        // Last resort for very plain receipts without labels: choose the largest
        // decimal/currency-looking value, but still ignore metadata contexts.
        return lines
            .filter { !isNeverMoneyLine($0) && !containsDateLikeText($0) }
            .flatMap { parsedAmounts(in: $0, currency: currency) }
            .filter { $0.hasCurrencySymbol || $0.hasFraction }
            .map(\.minorUnits)
            .max()
    }

    private static func likelyLineItems(from lines: [String]) -> [String] {
        return lines
            .filter { line in
                let normalized = line.lowercased()
                return containsAmount(line)
                    && !isNeverMoneyLine(line)
                    && !isAdjustmentOrTenderLine(normalized)
                    && !isAmountOnlyLine(line)
                    && !containsDateLikeText(line)
            }
            .prefix(5)
            .map { String($0.prefix(80)) }
    }

    private static func likelyReceiptDate(from lines: [String], referenceDate: Date = .now) -> Date? {
        var best: (score: Int, date: Date)?

        for (index, line) in lines.enumerated() {
            guard !isNeverDateLine(line) else { continue }

            for date in parsedDates(in: line, referenceDate: referenceDate) {
                var score = dateScore(line: line, index: index)
                if score <= 0 { score = 1 }

                if let current = best {
                    if score > current.score {
                        best = (score, date)
                    }
                } else {
                    best = (score, date)
                }
            }
        }

        return best?.date
    }

    private static func amounts(in line: String, currency: CurrencyCode) -> [Int64] {
        parsedAmounts(in: line, currency: currency).map(\.minorUnits)
    }

    private static func parsedAmounts(in line: String, currency: CurrencyCode) -> [ParsedAmount] {
        let normalizedLine = line
            .replacingOccurrences(of: "O", with: "0")
            .replacingOccurrences(of: "o", with: "0")
        let pattern = #"(?<!\d)([$€£¥])?\s*([0-9]{1,3}(?:,[0-9]{3})*|[0-9]+)(?:[\.,]([0-9]{1,2}))?(?!\d)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsLine = normalizedLine as NSString
        return regex.matches(in: normalizedLine, range: NSRange(location: 0, length: nsLine.length)).compactMap { match in
            let hasCurrencySymbol = match.range(at: 1).location != NSNotFound
            let whole = nsLine.substring(with: match.range(at: 2)).replacingOccurrences(of: ",", with: "")
            let fraction = match.range(at: 3).location == NSNotFound ? nil : nsLine.substring(with: match.range(at: 3))

            guard let wholeUnits = Int64(whole) else { return nil }
            if currency.minorUnitScale == 0 {
                return ParsedAmount(minorUnits: wholeUnits, hasCurrencySymbol: hasCurrencySymbol, hasFraction: fraction != nil)
            }

            let scaleMultiplier = Int64(pow(10.0, Double(currency.minorUnitScale)))
            let paddedFraction = String((fraction ?? "").prefix(currency.minorUnitScale)).padding(toLength: currency.minorUnitScale, withPad: "0", startingAt: 0)
            guard let fractionUnits = Int64(paddedFraction) else { return nil }
            return ParsedAmount(
                minorUnits: wholeUnits * scaleMultiplier + fractionUnits,
                hasCurrencySymbol: hasCurrencySymbol,
                hasFraction: fraction != nil
            )
        }
        .filter { $0.minorUnits > 0 && $0.minorUnits < 10_000_000 }
    }

    private static func containsAmount(_ line: String) -> Bool {
        !amounts(in: line, currency: .usd).isEmpty
    }

    private static func containsDateLikeText(_ line: String) -> Bool {
        line.range(of: #"\b\d{1,2}[/-]\d{1,2}([/-]\d{2,4})?\b"#, options: .regularExpression) != nil
            || line.range(
                of: #"\b(jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*\.?\s+\d{1,2},?\s+\d{2,4}\b"#,
                options: [.regularExpression, .caseInsensitive]
            ) != nil
    }

    private static func parsedDates(in line: String, referenceDate: Date) -> [Date] {
        var dates: [Date] = []
        dates.append(contentsOf: numericDates(in: line, referenceDate: referenceDate))
        dates.append(contentsOf: monthNameDates(in: line, referenceDate: referenceDate))
        return dates
    }

    private static func numericDates(in line: String, referenceDate: Date) -> [Date] {
        let pattern = #"(?<!\d)(\d{4})[/-](\d{1,2})[/-](\d{1,2})(?!\d)|(?<!\d)(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})(?!\d)|(?<!\d)(\d{1,2})[/-](\d{1,2})(?![/-]\d)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsLine = line as NSString

        return regex.matches(in: line, range: NSRange(location: 0, length: nsLine.length)).compactMap { match in
            if match.range(at: 1).location != NSNotFound {
                return makeDate(
                    year: Int(nsLine.substring(with: match.range(at: 1))),
                    month: Int(nsLine.substring(with: match.range(at: 2))),
                    day: Int(nsLine.substring(with: match.range(at: 3))),
                    referenceDate: referenceDate
                )
            }

            let monthRange = match.range(at: 4).location != NSNotFound ? match.range(at: 4) : match.range(at: 7)
            let dayRange = match.range(at: 5).location != NSNotFound ? match.range(at: 5) : match.range(at: 8)
            let yearRange = match.range(at: 6)
            let year = yearRange.location == NSNotFound ? nil : Int(nsLine.substring(with: yearRange))

            return makeDate(
                year: normalizedYear(year, referenceDate: referenceDate),
                month: Int(nsLine.substring(with: monthRange)),
                day: Int(nsLine.substring(with: dayRange)),
                referenceDate: referenceDate
            )
        }
    }

    private static func monthNameDates(in line: String, referenceDate: Date) -> [Date] {
        let pattern = #"\b(jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*\.?\s+(\d{1,2})(?:,?\s+(\d{2,4}))?\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let nsLine = line as NSString

        return regex.matches(in: line, range: NSRange(location: 0, length: nsLine.length)).compactMap { match in
            let monthText = nsLine.substring(with: match.range(at: 1)).lowercased()
            let yearRange = match.range(at: 3)
            let year = yearRange.location == NSNotFound ? nil : Int(nsLine.substring(with: yearRange))

            return makeDate(
                year: normalizedYear(year, referenceDate: referenceDate),
                month: monthNumber(from: monthText),
                day: Int(nsLine.substring(with: match.range(at: 2))),
                referenceDate: referenceDate
            )
        }
    }

    private static func normalizedYear(_ year: Int?, referenceDate: Date) -> Int? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let currentYear = calendar.component(.year, from: referenceDate)
        guard let year else { return currentYear }
        if year < 100 {
            return year >= 70 ? 1900 + year : 2000 + year
        }
        return year
    }

    private static func makeDate(year: Int?, month: Int?, day: Int?, referenceDate: Date) -> Date? {
        guard let year, let month, let day else { return nil }
        guard (2000...2100).contains(year), (1...12).contains(month), (1...31).contains(day) else {
            return nil
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12

        guard let date = calendar.date(from: components) else { return nil }
        let roundTrip = calendar.dateComponents([.year, .month, .day], from: date)
        guard roundTrip.year == year, roundTrip.month == month, roundTrip.day == day else {
            return nil
        }

        let thirtyDaysFromNow = calendar.date(byAdding: .day, value: 30, to: referenceDate) ?? referenceDate
        guard date <= thirtyDaysFromNow else { return nil }
        return date
    }

    private static func monthNumber(from value: String) -> Int? {
        switch value.prefix(3) {
        case "jan": 1
        case "feb": 2
        case "mar": 3
        case "apr": 4
        case "may": 5
        case "jun": 6
        case "jul": 7
        case "aug": 8
        case "sep": 9
        case "oct": 10
        case "nov": 11
        case "dec": 12
        default: nil
        }
    }

    private static func dateScore(line: String, index: Int) -> Int {
        let normalized = line.lowercased()
        var score = 0
        if normalized.contains("transaction date") { score += 90 }
        if normalized.contains("purchase date") || normalized.contains("order date") { score += 80 }
        if containsWord("date", in: normalized) { score += 60 }
        if containsWord("sale", in: normalized) || containsWord("paid", in: normalized) { score += 35 }
        if normalized.contains("posted date") { score -= 25 }
        if index < 12 { score += 5 }
        return score
    }

    private static func isNeverDateLine(_ line: String) -> Bool {
        let normalized = line.lowercased()
        let rejectedPhrases = [
            "reference", "authorization", "auth code", "confirmation",
            "transaction id", "order number", "card number", "card ending",
            "phone", "tel", "www.", "http"
        ]
        return rejectedPhrases.contains(where: normalized.contains)
    }

    private static func amountScore(line: String, amount: ParsedAmount, index: Int) -> Int {
        let normalized = line.lowercased()
        if isAdjustmentOrTenderLine(normalized) {
            return -1
        }

        var score = 0
        if normalized.contains("grand total") { score += 90 }
        if normalized.contains("amount due") || normalized.contains("amount paid") { score += 85 }
        if normalized.contains("total paid") || normalized.contains("total charge") { score += 80 }
        if containsWord("total", in: normalized) { score += 70 }
        if normalized.contains("transaction amount") || normalized.contains("purchase amount") { score += 70 }
        if containsWord("charge", in: normalized) || containsWord("charged", in: normalized) { score += 60 }
        if containsWord("paid", in: normalized) || containsWord("payment", in: normalized) { score += 50 }
        if containsWord("sale", in: normalized) || containsWord("purchase", in: normalized) { score += 35 }
        if amount.hasCurrencySymbol { score += 45 }
        if amount.hasFraction { score += 20 }
        if isAmountOnlyLine(line) { score += 30 }
        if index < 8 { score += 6 }

        return score
    }

    private static func isNeverMoneyLine(_ line: String) -> Bool {
        let normalized = line.lowercased()
        let rejectedPhrases = [
            "reward", "rewards", "points", "earned", "cashback", "cash back",
            "miles", "reference", "authorization", "auth code", "confirmation",
            "transaction id", "order number", "card number", "card ending",
            "phone", "tel", "www.", "http", "merchant type", "method"
        ]
        return rejectedPhrases.contains(where: normalized.contains)
    }

    private static func isAdjustmentOrTenderLine(_ normalized: String) -> Bool {
        let rejectedWords = [
            "subtotal", "sub total", "tax", "tip", "gratuity", "change",
            "cash tendered", "visa", "mastercard", "amex", "discover", "apple pay"
        ]
        return rejectedWords.contains(where: normalized.contains)
    }

    private static func isAmountOnlyLine(_ line: String) -> Bool {
        let stripped = line
            .replacingOccurrences(of: #"[$€£¥\s,.\d]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty
    }

    private static func containsWord(_ word: String, in value: String) -> Bool {
        value.range(of: #"\b\#(word)\b"#, options: .regularExpression) != nil
    }
}

private extension UIImage {
    var cgImageOrientation: CGImagePropertyOrientation {
        switch imageOrientation {
        case .up: .up
        case .upMirrored: .upMirrored
        case .down: .down
        case .downMirrored: .downMirrored
        case .left: .left
        case .leftMirrored: .leftMirrored
        case .right: .right
        case .rightMirrored: .rightMirrored
        @unknown default: .up
        }
    }
}
