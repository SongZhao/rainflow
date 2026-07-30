import RainflowDomain
import SwiftUI
import UIKit

struct ManualTransactionFlowView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var ledgerStore: LedgerStore

    let receiptData: Data?
    let onComplete: () -> Void

    @State private var step = 1
    @State private var draft = TransactionDraft()
    @State private var amountText = ""
    @State private var didScanReceipt = false
    @State private var isScanningReceipt = false
    @State private var hasUserEditedDate = false
    @State private var receiptScanMessage: String?
    @State private var saveOutcome: TransactionSaveOutcome?
    @State private var saveError: String?
    @FocusState private var amountIsFocused: Bool

    private var currency: CurrencyCode { ledgerStore.currency }
    private var currencyCode: String { currency.rawValue }

    private var activeAccounts: [AccountRecord] {
        ledgerStore.accounts.filter { $0.archivedAt == nil }
    }

    private var sourceAccounts: [AccountRecord] {
        switch draft.kind {
        case .income:
            activeAccounts.filter { $0.type == .asset }
        case .expense, .transfer:
            activeAccounts.filter { $0.type == .asset || $0.type == .liability }
        }
    }

    private var destinationAccounts: [AccountRecord] {
        switch draft.kind {
        case .expense:
            activeAccounts.filter { $0.type == .expense }
        case .income:
            activeAccounts.filter { $0.type == .income }
        case .transfer:
            sourceAccounts.filter { $0.id != draft.accountID }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let saveOutcome {
                    successView(outcome: saveOutcome)
                } else {
                    VStack(spacing: 0) {
                        progressHeader
                        currentStep
                    }
                }
            }
            .background(RainflowColor.background.ignoresSafeArea())
            .toolbar {
                if saveOutcome == nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .principal) {
                        Text(stepTitle)
                            .font(.headline)
                    }
                }
            }
            .toolbarBackground(RainflowColor.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .onAppear {
            if step == 1, receiptData == nil {
                amountIsFocused = true
            }
            scanReceiptIfNeeded()
        }
        .onChange(of: amountText) { _, value in
            draft.amountMinorUnits = parseMinorUnits(value)
        }
        .onChange(of: draft.kind) { _, _ in
            draft.accountID = nil
            draft.categoryOrDestinationID = nil
        }
    }

    private var progressHeader: some View {
        HStack(spacing: 7) {
            ForEach(1...4, id: \.self) { item in
                Capsule()
                    .fill(item <= step ? RainflowColor.brandAccent : RainflowColor.border)
                    .frame(height: 4)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .accessibilityLabel("Step \(step) of 4")
    }

    @ViewBuilder
    private var currentStep: some View {
        switch step {
        case 1:
            amountStep
        case 2:
            detailsStep
        case 3:
            receiptStep
        default:
            reviewStep
        }
    }

    private var amountStep: some View {
        ScrollView {
                VStack(spacing: 22) {
                if receiptData != nil {
                    receiptScanBanner(hasReceipt: true)
                }

                Picker("Transaction type", selection: $draft.kind) {
                    ForEach(TransactionKind.allCases) { kind in
                        Text(kind.rawValue).tag(kind)
                    }
                }
                .pickerStyle(.segmented)

                VStack(spacing: 8) {
                    Text(currencyCode)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(RainflowColor.textSecondary)
                    HStack(spacing: 4) {
                        Text(currencySymbol)
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                            .foregroundStyle(RainflowColor.textSecondary)
                        TextField(currency.minorUnitScale == 0 ? "0" : "0.00", text: $amountText)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 52, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .multilineTextAlignment(.center)
                            .focused($amountIsFocused)
                            .accessibilityLabel("Transaction amount")
                    }
                    .minimumScaleFactor(0.55)
                    Text(amountHelpText)
                        .font(.caption)
                        .foregroundStyle(amountText.isEmpty || draft.amountMinorUnits != nil ? RainflowColor.textSecondary : RainflowColor.expense)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)

                primaryButton("Next", enabled: draft.amountMinorUnits != nil) {
                    amountIsFocused = false
                    step = 2
                }
            }
            .padding(16)
        }
    }

    private var detailsStep: some View {
        ScrollView {
            VStack(spacing: 16) {
                FinanceCard {
                    VStack(spacing: 14) {
                        Picker(accountLabel, selection: $draft.accountID) {
                            Text("Choose an account").tag(Optional<UUID>.none)
                            ForEach(sourceAccounts) { account in
                                Text(account.name).tag(Optional(account.id))
                            }
                        }
                        Divider().overlay(RainflowColor.border)
                        Picker(destinationLabel, selection: $draft.categoryOrDestinationID) {
                            Text(destinationPlaceholder).tag(Optional<UUID>.none)
                            ForEach(destinationAccounts) { account in
                                Text(account.name).tag(Optional(account.id))
                            }
                        }
                        Divider().overlay(RainflowColor.border)
                        DatePicker(
                            "Date",
                            selection: Binding(
                                get: { draft.accountingDate },
                                set: { newValue in
                                    draft.accountingDate = newValue
                                    hasUserEditedDate = true
                                }
                            ),
                            displayedComponents: .date
                        )
                        Divider().overlay(RainflowColor.border)
                        TextField(payeePlaceholder, text: $draft.payee)
                            .textContentType(.organizationName)
                        Divider().overlay(RainflowColor.border)
                        TextField("Notes (optional)", text: $draft.note, axis: .vertical)
                            .lineLimit(2...5)
                    }
                }

                if sourceAccounts.isEmpty || destinationAccounts.isEmpty {
                    Label("This ledger needs an active source account and matching category before this transaction can be saved.", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(RainflowColor.warning)
                }

                primaryButton(
                    "Next",
                    enabled: draft.accountID != nil
                        && draft.categoryOrDestinationID != nil
                        && draft.accountID != draft.categoryOrDestinationID
                ) {
                    step = 3
                }
            }
            .padding(16)
        }
    }

    private var receiptStep: some View {
        ScrollView {
            VStack(spacing: 16) {
                FinanceCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Receipt")
                            .font(.headline)
                        if let receiptData, let image = UIImage(data: receiptData) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 260)
                                .frame(maxWidth: .infinity)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                                .accessibilityLabel("Selected receipt image")
                            receiptScanBanner(hasReceipt: true)
                        } else {
                            EmptyStateView(
                                symbol: "doc.text.image",
                                title: "No receipt attached",
                                message: "That is fine. Manual transactions do not require a receipt."
                            )
                        }
                    }
                }

                FinanceCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("The image is copied into Rainflow-managed storage.", systemImage: "lock.fill")
                        Label("The transaction saves atomically before the receipt is finalized.", systemImage: "checkmark.shield.fill")
                        Label("A failed receipt upload is queued for retry.", systemImage: "arrow.clockwise.icloud.fill")
                    }
                    .font(.caption)
                    .foregroundStyle(RainflowColor.textSecondary)
                }

                primaryButton("Review", enabled: draft.canReview) { step = 4 }
            }
            .padding(16)
        }
    }

    private var reviewStep: some View {
        ScrollView {
            VStack(spacing: 16) {
                FinanceCard {
                    VStack(spacing: 14) {
                        reviewRow("Type", value: draft.kind.rawValue)
                        reviewRow("Amount", value: (draft.amountMinorUnits ?? 0).formattedCurrency(code: currencyCode))
                        reviewRow("Date", value: draft.accountingDate.formatted(date: .abbreviated, time: .omitted))
                        reviewRow("Account", value: sourceAccounts.first(where: { $0.id == draft.accountID })?.name ?? "—")
                        reviewRow(destinationLabel, value: destinationAccounts.first(where: { $0.id == draft.categoryOrDestinationID })?.name ?? "—")
                        if !draft.payee.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            reviewRow("Payee", value: draft.payee)
                        }
                        if !draft.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            reviewRow("Note", value: draft.note)
                        }
                        reviewRow("Receipt", value: receiptData == nil ? "None" : "Attached")
                        if let receiptScanMessage {
                            reviewRow("Receipt scan", value: receiptScanMessage)
                        }
                    }
                }

                if let saveError {
                    Label(saveError, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(RainflowColor.expense)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text("Rainflow sends the complete balanced transaction through one atomic server command. Individual postings are never saved from this screen.")
                    .font(.caption)
                    .foregroundStyle(RainflowColor.textSecondary)

                Button {
                    Task { await save() }
                } label: {
                    HStack {
                        if ledgerStore.isWorking { ProgressView().tint(.white) }
                        Text(ledgerStore.isWorking ? "Saving…" : "Save Transaction")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                }
                .buttonStyle(.borderedProminent)
                .tint(RainflowColor.brand)
                .disabled(!draft.canReview || ledgerStore.isWorking)
            }
            .padding(16)
        }
    }

    private func successView(outcome: TransactionSaveOutcome) -> some View {
        let presentation: (symbol: String, color: Color, message: String?) = switch outcome.receiptStatus {
        case .none:
            ("checkmark.circle.fill", RainflowColor.income, nil)
        case .uploaded:
            ("checkmark.circle.fill", RainflowColor.income, "The receipt is stored privately with this transaction.")
        case .queuedForRetry:
            ("checkmark.icloud.fill", RainflowColor.warning, "Your receipt is safely queued on this iPhone and will upload automatically when the connection recovers.")
        case .needsAttention:
            ("exclamationmark.icloud.fill", RainflowColor.warning, "The transaction is saved, but the receipt could not be queued. Keep the original image and attach it again when the device has storage and a connection.")
        }

        return VStack(spacing: 20) {
            Spacer()
            Image(systemName: presentation.symbol)
                .font(.system(size: 76))
                .foregroundStyle(presentation.color)
            Text("Transaction saved")
                .font(.title2.weight(.semibold))
            Text((draft.amountMinorUnits ?? 0).formattedCurrency(code: currencyCode))
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(draft.kind == .expense ? RainflowColor.expense : RainflowColor.income)
                .monospacedDigit()
            if let message = presentation.message {
                Text(message)
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(RainflowColor.textSecondary)
                    .padding(.horizontal, 28)
            }
            Spacer()
            Button("Done") { onComplete() }
                .buttonStyle(.borderedProminent)
                .tint(RainflowColor.brand)
                .frame(maxWidth: .infinity)
                .padding(16)
        }
    }

    private var stepTitle: String {
        switch step {
        case 1: "Amount"
        case 2: "Details"
        case 3: "Receipt"
        default: "Review"
        }
    }

    private var accountLabel: String {
        switch draft.kind {
        case .expense: "Payment account"
        case .income: "Deposit account"
        case .transfer: "From account"
        }
    }

    private var destinationLabel: String {
        switch draft.kind {
        case .expense: "Category"
        case .income: "Income category"
        case .transfer: "To account"
        }
    }

    private var destinationPlaceholder: String {
        switch draft.kind {
        case .expense: "Choose a category"
        case .income: "Choose an income category"
        case .transfer: "Choose a destination"
        }
    }

    private var payeePlaceholder: String {
        switch draft.kind {
        case .expense: "Merchant or payee (optional)"
        case .income: "Income source (optional)"
        case .transfer: "Transfer description (optional)"
        }
    }

    private var currencySymbol: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.locale = .autoupdatingCurrent
        return formatter.currencySymbol ?? currencyCode
    }

    private var amountHelpText: String {
        if isScanningReceipt {
            return "Scanning receipt for total and merchant..."
        }
        if amountText.isEmpty {
            return currency.minorUnitScale == 0 ? "Enter a whole-unit amount." : "Enter up to \(currency.minorUnitScale) decimal places."
        }
        return draft.amountMinorUnits == nil ? "Enter a positive amount with valid currency precision." : "Stored exactly as integer minor units."
    }

    private func receiptScanBanner(hasReceipt: Bool) -> some View {
        Label {
            Text(receiptScanMessage ?? (isScanningReceipt ? "Scanning receipt..." : "Receipt attached"))
        } icon: {
            Image(systemName: isScanningReceipt ? "text.viewfinder" : "doc.text.image")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(isScanningReceipt ? RainflowColor.brandAccent : RainflowColor.textSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RainflowColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(RainflowColor.border, lineWidth: 1)
        }
        .accessibilityHidden(!hasReceipt)
    }

    private func primaryButton(_ title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.borderedProminent)
            .tint(RainflowColor.brand)
            .disabled(!enabled)
            .frame(maxWidth: .infinity)
            .controlSize(.large)
    }

    private func reviewRow(_ label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundStyle(RainflowColor.textSecondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
    }

    private func parseMinorUnits(_ value: String) -> Int64? {
        let normalized = value
            .replacingOccurrences(of: currencySymbol, with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let decimal = Decimal(string: normalized), decimal > 0 else { return nil }

        let multiplier = Decimal(sign: .plus, exponent: currency.minorUnitScale, significand: 1)
        var scaled = decimal * multiplier
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .bankers)
        guard rounded == scaled,
              rounded <= Decimal(Int64.max) else { return nil }
        return NSDecimalNumber(decimal: rounded).int64Value
    }

    @MainActor
    private func save() async {
        saveError = nil
        do {
            saveOutcome = try await ledgerStore.saveTransaction(draft: draft, receiptData: receiptData)
        } catch {
            saveError = error.localizedDescription
        }
    }

    @MainActor
    private func scanReceiptIfNeeded() {
        guard !didScanReceipt, let receiptData else { return }
        didScanReceipt = true
        isScanningReceipt = true
        receiptScanMessage = "Scanning receipt..."

        Task {
            let result = await ReceiptTextExtractor.extract(from: receiptData, currency: currency)
            applyReceiptExtraction(result)
        }
    }

    @MainActor
    private func applyReceiptExtraction(_ result: ReceiptExtractionResult) {
        isScanningReceipt = false

        var filled: [String] = []
        if let amountMinorUnits = result.amountMinorUnits, draft.amountMinorUnits == nil {
            draft.amountMinorUnits = amountMinorUnits
            amountText = decimalText(for: amountMinorUnits)
            filled.append("amount")
        }

        if let merchantName = result.merchantName,
           draft.payee.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft.payee = merchantName
            filled.append("merchant")
        }

        if let accountingDate = result.accountingDate, !hasUserEditedDate {
            draft.accountingDate = accountingDate
            filled.append("date")
        }

        if !result.lineItems.isEmpty,
           draft.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft.note = "Receipt lines: " + result.lineItems.joined(separator: "; ")
            filled.append("receipt lines")
        }

        receiptScanMessage = filled.isEmpty
            ? "Receipt attached. I could not confidently read the amount."
            : "Autofilled " + filled.joined(separator: ", ") + ". Please review before saving."
    }

    private func decimalText(for minorUnits: Int64) -> String {
        if currency.minorUnitScale == 0 {
            return "\(minorUnits)"
        }

        let scale = Int64(pow(10.0, Double(currency.minorUnitScale)))
        let whole = minorUnits / scale
        let fraction = minorUnits % scale
        return "\(whole)." + String(format: "%0\(currency.minorUnitScale)lld", fraction)
    }
}
