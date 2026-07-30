import RainflowDomain
import SwiftUI

struct TransactionEditorView: View {
    @EnvironmentObject private var ledgerStore: LedgerStore
    @Environment(\.dismiss) private var dismiss

    let transaction: TransactionRecord

    @State private var draft = TransactionDraft()
    @State private var amountText = ""
    @State private var saveError: String?
    @State private var receiptError: String?
    @State private var receiptPreview: ReceiptPreview?
    @State private var isReceiptLoading = false
    @State private var isDeleteConfirmationPresented = false

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
            ScrollView {
                VStack(spacing: 16) {
                    FinanceCard {
                        VStack(spacing: 14) {
                            Picker("Transaction type", selection: $draft.kind) {
                                ForEach(TransactionKind.allCases) { kind in
                                    Text(kind.rawValue).tag(kind)
                                }
                            }
                            .pickerStyle(.segmented)

                            fieldLabel("Amount")
                            HStack(spacing: 4) {
                                Text(currencySymbol)
                                    .font(.title2.weight(.semibold))
                                    .foregroundStyle(RainflowColor.textSecondary)
                                TextField(currency.minorUnitScale == 0 ? "0" : "0.00", text: $amountText)
                                    .keyboardType(.decimalPad)
                                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                            }

                            Divider().overlay(RainflowColor.border)

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

                            DatePicker("Date", selection: $draft.accountingDate, displayedComponents: .date)

                            Divider().overlay(RainflowColor.border)

                            TextField(payeePlaceholder, text: $draft.payee)
                                .textContentType(.organizationName)

                            Divider().overlay(RainflowColor.border)

                            TextField("Notes (optional)", text: $draft.note, axis: .vertical)
                                .lineLimit(2...5)
                        }
                    }

                    if let attachment = ledgerStore.activeReceiptAttachment(for: transaction.id) {
                        receiptCard(attachment)
                    }

                    if let saveError {
                        Label(saveError, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(RainflowColor.expense)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button {
                        Task { await save() }
                    } label: {
                        HStack {
                            if ledgerStore.isWorking { ProgressView().tint(.white) }
                            Text(ledgerStore.isWorking ? "Saving..." : "Save Changes")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(RainflowColor.brand)
                    .disabled(!draft.canReview || ledgerStore.isWorking)

                    Button(role: .destructive) {
                        isDeleteConfirmationPresented = true
                    } label: {
                        Text("Remove Transaction")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                    }
                    .buttonStyle(.bordered)
                    .disabled(ledgerStore.isWorking)
                }
                .padding(16)
            }
            .background(RainflowColor.background.ignoresSafeArea())
            .navigationTitle("Edit Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .confirmationDialog(
                "Remove this transaction?",
                isPresented: $isDeleteConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button("Remove Transaction", role: .destructive) {
                    Task { await remove() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Rainflow will soft-delete the complete transaction. Its postings stop affecting balances.")
            }
            .sheet(item: $receiptPreview) { preview in
                NavigationStack {
                    ZStack {
                        RainflowColor.background.ignoresSafeArea()
                        AsyncImage(url: preview.url) { phase in
                            switch phase {
                            case .empty:
                                ProgressView("Loading receipt...")
                                    .foregroundStyle(RainflowColor.textSecondary)
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .padding()
                            case .failure:
                                EmptyStateView(
                                    symbol: "exclamationmark.triangle.fill",
                                    title: "Receipt could not load",
                                    message: "Close this preview and try again. The private viewing link may have expired."
                                )
                                .padding(28)
                            @unknown default:
                                EmptyView()
                            }
                        }
                    }
                    .navigationTitle(preview.name)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Close") { receiptPreview = nil }
                        }
                    }
                }
            }
            .alert("Receipt", isPresented: Binding(
                get: { receiptError != nil },
                set: { if !$0 { receiptError = nil } }
            )) {
                Button("OK", role: .cancel) { receiptError = nil }
            } message: {
                Text(receiptError ?? "")
            }
        }
        .onAppear(perform: loadDraft)
        .onChange(of: amountText) { _, value in
            draft.amountMinorUnits = parseMinorUnits(value)
        }
        .onChange(of: draft.kind) { _, _ in
            guard draft.accountID != nil || draft.categoryOrDestinationID != nil else { return }
            if !sourceAccounts.contains(where: { $0.id == draft.accountID }) {
                draft.accountID = nil
            }
            if !destinationAccounts.contains(where: { $0.id == draft.categoryOrDestinationID }) {
                draft.categoryOrDestinationID = nil
            }
        }
    }

    private func loadDraft() {
        let accountMap = Dictionary(uniqueKeysWithValues: activeAccounts.map { ($0.id, $0) })

        if let expensePosting = transaction.postings.first(where: {
            accountMap[$0.accountID]?.type == .expense && $0.amountMinorUnits > 0
        }) {
            let sourcePosting = transaction.postings.first(where: {
                let type = accountMap[$0.accountID]?.type
                return (type == .asset || type == .liability) && $0.amountMinorUnits < 0
            }) ?? transaction.postings.first(where: {
                let type = accountMap[$0.accountID]?.type
                return type == .asset || type == .liability
            })
            setDraft(
                kind: .expense,
                amount: absAmount(expensePosting.amountMinorUnits),
                sourceID: sourcePosting?.accountID,
                destinationID: expensePosting.accountID
            )
            return
        }

        if let incomePosting = transaction.postings.first(where: {
            accountMap[$0.accountID]?.type == .income && $0.amountMinorUnits < 0
        }) {
            let sourcePosting = transaction.postings.first(where: {
                let type = accountMap[$0.accountID]?.type
                return (type == .asset || type == .liability) && $0.amountMinorUnits > 0
            }) ?? transaction.postings.first(where: {
                let type = accountMap[$0.accountID]?.type
                return type == .asset || type == .liability
            })
            setDraft(
                kind: .income,
                amount: absAmount(incomePosting.amountMinorUnits),
                sourceID: sourcePosting?.accountID,
                destinationID: incomePosting.accountID
            )
            return
        }

        let sourcePosting = transaction.postings.first(where: {
            let type = accountMap[$0.accountID]?.type
            return (type == .asset || type == .liability) && $0.amountMinorUnits < 0
        }) ?? transaction.postings.first
        let destinationPosting = transaction.postings.first(where: {
            $0.accountID != sourcePosting?.accountID
                && (accountMap[$0.accountID]?.type == .asset || accountMap[$0.accountID]?.type == .liability)
        }) ?? transaction.postings.first(where: { $0.accountID != sourcePosting?.accountID })

        setDraft(
            kind: .transfer,
            amount: absAmount(sourcePosting?.amountMinorUnits ?? destinationPosting?.amountMinorUnits ?? 0),
            sourceID: sourcePosting?.accountID,
            destinationID: destinationPosting?.accountID
        )
    }

    private func setDraft(kind: TransactionKind, amount: Int64, sourceID: UUID?, destinationID: UUID?) {
        draft = TransactionDraft(
            kind: kind,
            amountMinorUnits: amount,
            accountID: sourceID,
            categoryOrDestinationID: destinationID,
            accountingDate: parseDate(transaction.accountingDate),
            payee: transaction.payee ?? transaction.description,
            note: transaction.note ?? ""
        )
        amountText = decimalText(for: amount)
    }

    private func save() async {
        saveError = nil
        do {
            try await ledgerStore.updateTransaction(transaction, draft: draft)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func remove() async {
        saveError = nil
        do {
            try await ledgerStore.deleteTransaction(transaction)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func receiptCard(_ attachment: AttachmentRecord) -> some View {
        FinanceCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Receipt attached", systemImage: "doc.text.image")
                    .font(.headline)
                Text(attachment.originalFileName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(RainflowColor.textPrimary)
                    .lineLimit(1)
                Text("\(byteSizeText(attachment.byteSize)) · Private storage")
                    .font(.caption)
                    .foregroundStyle(RainflowColor.textSecondary)
                Button {
                    Task { await openReceipt() }
                } label: {
                    HStack {
                        if isReceiptLoading {
                            ProgressView()
                        }
                        Text(isReceiptLoading ? "Opening..." : "View Receipt")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                }
                .buttonStyle(.bordered)
                .tint(RainflowColor.brandAccent)
                .disabled(isReceiptLoading)
            }
        }
    }

    @MainActor
    private func openReceipt() async {
        isReceiptLoading = true
        receiptError = nil
        defer { isReceiptLoading = false }

        do {
            let url = try await ledgerStore.receiptViewURL(for: transaction.id)
            let name = ledgerStore.activeReceiptAttachment(for: transaction.id)?.originalFileName ?? "Receipt"
            receiptPreview = ReceiptPreview(url: url, name: name)
        } catch {
            receiptError = error.localizedDescription
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
        case .expense: "Merchant or payee"
        case .income: "Income source"
        case .transfer: "Transfer description"
        }
    }

    private var currencySymbol: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.locale = .autoupdatingCurrent
        return formatter.currencySymbol ?? currencyCode
    }

    private func fieldLabel(_ value: String) -> some View {
        Text(value)
            .font(.caption.weight(.semibold))
            .foregroundStyle(RainflowColor.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
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

    private func decimalText(for minorUnits: Int64) -> String {
        if currency.minorUnitScale == 0 {
            return "\(minorUnits)"
        }

        let scale = Int64(pow(10.0, Double(currency.minorUnitScale)))
        let whole = minorUnits / scale
        let fraction = minorUnits % scale
        return "\(whole)." + String(format: "%0\(currency.minorUnitScale)lld", fraction)
    }

    private func parseDate(_ value: String) -> Date {
        let parts = value.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]),
              let date = Calendar.current.date(from: DateComponents(year: year, month: month, day: day)) else {
            return .now
        }
        return date
    }

    private func absAmount(_ value: Int64) -> Int64 {
        if value == .min { return .max }
        return Swift.abs(value)
    }

    private func byteSizeText(_ byteSize: Int64) -> String {
        let value = ByteCountFormatter.string(fromByteCount: byteSize, countStyle: .file)
        return value
    }
}

private struct ReceiptPreview: Identifiable {
    let id = UUID()
    let url: URL
    let name: String
}
