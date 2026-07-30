import RainflowDomain
import SwiftUI

struct LedgersView: View {
    @EnvironmentObject private var ledgerStore: LedgerStore
    @State private var isCreateLedgerPresented = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header
                    activeLedgerCard
                    ledgersList
                }
                .padding(.bottom, 24)
            }
            .refreshable { await ledgerStore.refresh() }
            .background(RainflowColor.background)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $isCreateLedgerPresented) {
                CreateLedgerSheet()
                    .environmentObject(ledgerStore)
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Ledgers")
                    .font(.title2.weight(.semibold))
                Text("Personal and shared books")
                    .font(.caption)
                    .foregroundStyle(RainflowColor.textSecondary)
            }
            Spacer()
            Button {
                Task { await ledgerStore.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 38, height: 38)
            }
            .accessibilityLabel("Refresh ledgers")
            Button {
                isCreateLedgerPresented = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .frame(width: 38, height: 38)
            }
            .accessibilityLabel("Create ledger")
        }
        .foregroundStyle(RainflowColor.textPrimary)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var activeLedgerCard: some View {
        FinanceCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Active Ledger", systemImage: "book.closed.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(RainflowColor.brandAccent)
                Text(ledgerStore.snapshot?.ledger.name ?? "No ledger selected")
                    .font(.largeTitle.weight(.semibold))
                    .minimumScaleFactor(0.68)
                Text(activeLedgerSubtitle)
                    .font(.caption)
                    .foregroundStyle(RainflowColor.textSecondary)
                Text((ledgerStore.snapshot?.netWorthMinorUnits ?? 0).formattedCurrency(code: currencyCode))
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 16)
    }

    private var ledgersList: some View {
        FinanceCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("All Ledgers")
                        .font(.headline)
                    Spacer()
                    Text("\(ledgerStore.ledgers.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(RainflowColor.textSecondary)
                }

                if ledgerStore.ledgers.isEmpty {
                    EmptyStateView(
                        symbol: "book.closed",
                        title: "No ledger yet",
                        message: "Create a ledger to start tracking accounts and transactions."
                    )
                } else {
                    ForEach(Array(ledgerStore.ledgers.enumerated()), id: \.element.id) { index, ledger in
                        NavigationLink {
                            LedgerDetailRouteView(ledger: ledger)
                                .environmentObject(ledgerStore)
                        } label: {
                            ledgerRow(ledger)
                        }
                        .buttonStyle(.plain)

                        if index < ledgerStore.ledgers.count - 1 {
                            Divider().overlay(RainflowColor.border)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private var currencyCode: String {
        ledgerStore.snapshot?.ledger.currencyCode ?? "USD"
    }

    private var activeLedgerSubtitle: String {
        guard let ledger = ledgerStore.snapshot?.ledger else { return "Create or select a ledger" }
        return "\(ledger.displayType) · \(ledger.currencyCode)"
    }

    private func ledgerRow(_ ledger: LedgerRecord) -> some View {
        let isActive = ledgerStore.activeLedgerID == ledger.id || ledgerStore.snapshot?.ledger.id == ledger.id

        return HStack(spacing: 12) {
            Image(systemName: ledger.ledgerType == "shared" ? "person.2.fill" : "book.closed.fill")
                .foregroundStyle(RainflowColor.brandAccent)
                .frame(width: 40, height: 40)
                .background(RainflowColor.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text(ledger.name)
                    .fontWeight(.medium)
                Text("\(ledger.displayType) · \(ledger.currencyCode)")
                    .font(.caption)
                    .foregroundStyle(RainflowColor.textSecondary)
            }
            Spacer()
            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(RainflowColor.income)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(RainflowColor.textSecondary)
        }
        .foregroundStyle(RainflowColor.textPrimary)
        .padding(.vertical, 11)
    }
}

private struct LedgerDetailRouteView: View {
    @EnvironmentObject private var ledgerStore: LedgerStore
    let ledger: LedgerRecord

    var body: some View {
        Group {
            if ledgerStore.snapshot?.ledger.id == ledger.id, let activeLedger = ledgerStore.snapshot?.ledger {
                LedgerDetailView(ledger: activeLedger)
                    .environmentObject(ledgerStore)
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading ledger")
                        .font(.subheadline)
                        .foregroundStyle(RainflowColor.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RainflowColor.background)
            }
        }
        .task {
            await ledgerStore.switchLedger(ledger)
        }
    }
}

private struct CreateLedgerSheet: View {
    @EnvironmentObject private var ledgerStore: LedgerStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var currency: CurrencyCode = .usd
    @State private var kind: LedgerKindOption = .personal
    @State private var isSubmitting = false
    @State private var localErrorMessage: String?

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Ledger") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)

                    Picker("Type", selection: $kind) {
                        ForEach(LedgerKindOption.allCases) { option in
                            VStack(alignment: .leading) {
                                Text(option.title)
                                Text(option.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .tag(option)
                        }
                    }

                    Picker("Currency", selection: $currency) {
                        ForEach(CurrencyCode.allCases) { code in
                            Text(code.rawValue).tag(code)
                        }
                    }
                }

                if kind == .shared {
                    Section {
                        Text("Invite people from the Mac web app after this ledger is created.")
                            .foregroundStyle(.secondary)
                    }
                }

                if let localErrorMessage {
                    Section {
                        Label(localErrorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(RainflowColor.expense)
                    }
                }
            }
            .navigationTitle("New Ledger")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task {
                            isSubmitting = true
                            localErrorMessage = nil
                            let didCreate = await ledgerStore.createLedger(
                                name: trimmedName.isEmpty ? defaultLedgerName : trimmedName,
                                currency: currency,
                                kind: kind
                            )
                            isSubmitting = false
                            if didCreate {
                                dismiss()
                            } else {
                                localErrorMessage = ledgerStore.errorMessage ?? "Rainflow could not create this ledger. Try again."
                            }
                        }
                    }
                    .disabled(isSubmitting || ledgerStore.isWorking)
                }
            }
            .overlay {
                if isSubmitting {
                    ZStack {
                        Color.black.opacity(0.12)
                            .ignoresSafeArea()
                        ProgressView("Creating ledger")
                            .padding(18)
                            .background(.regularMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var defaultLedgerName: String {
        kind == .shared ? "Shared Ledger" : "Personal"
    }
}

private struct LedgerDetailView: View {
    @EnvironmentObject private var ledgerStore: LedgerStore
    let ledger: LedgerRecord
    @State private var selectedTransaction: TransactionRecord?
    @State private var selectedCalendarDay: LedgerCalendarDay?
    @State private var isMonthPickerPresented = false
    @State private var visibleMonth = LedgerCalendar.currentMonthStart()

    private var currencyCode: String { ledger.currencyCode }
    private var transactions: [TransactionSummary] { ledgerStore.transactions }
    private var totalBalance: Int64 {
        ledgerStore.accountSummaries.reduce(Int64.zero) { $0 + $1.balanceMinorUnits }
    }
    private var categoryBreakdown: [LedgerCategoryBreakdown] {
        var totals: [String: (amount: Int64, symbol: String, count: Int)] = [:]

        for transaction in transactions where transaction.kind == .expense {
            let amount = positiveMagnitude(transaction.amountMinorUnits)
            let current = totals[transaction.category] ?? (0, transaction.symbol, 0)
            totals[transaction.category] = (
                addingClamped(current.amount, amount),
                current.symbol,
                current.count + 1
            )
        }

        return totals.map { category, value in
            LedgerCategoryBreakdown(
                name: category,
                amountMinorUnits: value.amount,
                transactionCount: value.count,
                symbol: value.symbol
            )
        }
        .sorted { $0.amountMinorUnits > $1.amountMinorUnits }
        .prefix(5)
        .map { $0 }
    }
    private var maxCategoryAmount: Int64 {
        max(categoryBreakdown.map(\.amountMinorUnits).max() ?? 1, 1)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                summaryHeader
                summaryMetrics
                categoryBreakdownCard
                calendarCard
                transactionList(title: "Ledger Transactions", transactions: transactions)
            }
            .padding(16)
        }
        .background(RainflowColor.background)
        .navigationTitle(ledger.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedTransaction) { transaction in
            TransactionEditorView(transaction: transaction)
                .environmentObject(ledgerStore)
        }
        .sheet(item: $selectedCalendarDay) { day in
            LedgerDayTransactionsView(day: day, currencyCode: currencyCode)
                .environmentObject(ledgerStore)
        }
        .sheet(isPresented: $isMonthPickerPresented) {
            LedgerMonthPickerSheet(visibleMonth: $visibleMonth)
        }
    }

    private var summaryHeader: some View {
        FinanceCard {
            VStack(alignment: .leading, spacing: 12) {
                Label(ledger.displayType, systemImage: ledger.ledgerType == "shared" ? "person.2.fill" : "book.closed.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(RainflowColor.brandAccent)
                Text(ledger.name)
                    .font(.largeTitle.weight(.semibold))
                    .minimumScaleFactor(0.7)
                HStack {
                    detailMetric("Currency", ledger.currencyCode)
                    Spacer()
                    detailMetric("Accounts", "\(ledgerStore.accountSummaries.count)")
                    Spacer()
                    detailMetric("Transactions", "\(transactions.count)")
                }
                Text(totalBalance.formattedCurrency(code: currencyCode))
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
            }
        }
    }

    private var summaryMetrics: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            metricCard(
                title: "Cash Flow",
                value: ledgerStore.cashFlow.netMinorUnits,
                color: ledgerStore.cashFlow.netMinorUnits >= 0 ? RainflowColor.income : RainflowColor.expense,
                symbol: "arrow.up.arrow.down"
            )
            metricCard(
                title: "Spending",
                value: -ledgerStore.cashFlow.expenseMinorUnits,
                color: RainflowColor.expense,
                symbol: "chart.pie.fill"
            )
            metricCard(
                title: "Income",
                value: ledgerStore.cashFlow.incomeMinorUnits,
                color: RainflowColor.income,
                symbol: "arrow.down.circle.fill"
            )
            metricCard(
                title: "Net Worth",
                value: totalBalance,
                color: totalBalance >= 0 ? RainflowColor.income : RainflowColor.expense,
                symbol: "building.columns.fill"
            )
        }
    }

    private var categoryBreakdownCard: some View {
        FinanceCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Top Categories")
                        .font(.headline)
                    Spacer()
                    Text("By spending")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(RainflowColor.textSecondary)
                }

                if categoryBreakdown.isEmpty {
                    EmptyStateView(
                        symbol: "chart.bar.xaxis",
                        title: "No category breakdown yet",
                        message: "Expense categories will appear after transactions are added."
                    )
                } else {
                    ForEach(categoryBreakdown) { item in
                        categoryRow(item)
                    }
                }
            }
        }
    }

    private var calendarCard: some View {
        FinanceCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Calendar")
                            .font(.headline)
                        Text("Daily cash flow")
                            .font(.caption)
                            .foregroundStyle(RainflowColor.textSecondary)
                    }
                    Spacer()
                    Button {
                        moveVisibleMonth(by: -1)
                    } label: {
                        Image(systemName: "chevron.left")
                            .frame(width: 34, height: 34)
                    }
                    .accessibilityLabel("Previous month")

                    Button {
                        isMonthPickerPresented = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "calendar")
                            Text(LedgerCalendar.monthTitle(for: visibleMonth))
                        }
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .frame(height: 34)
                        .background(RainflowColor.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Choose month")

                    Button {
                        moveVisibleMonth(by: 1)
                    } label: {
                        Image(systemName: "chevron.right")
                            .frame(width: 34, height: 34)
                    }
                    .accessibilityLabel("Next month")
                }

                HStack {
                    ForEach(LedgerCalendar.weekdaySymbols, id: \.self) { weekday in
                        Text(weekday)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(RainflowColor.textSecondary)
                            .frame(maxWidth: .infinity)
                    }
                }

                LazyVGrid(columns: LedgerCalendar.gridColumns, spacing: 8) {
                    ForEach(0..<LedgerCalendar.leadingEmptySlots(for: visibleMonth), id: \.self) { _ in
                        Color.clear
                            .frame(height: 70)
                    }

                    ForEach(calendarDays) { day in
                        Button {
                            selectedCalendarDay = day
                        } label: {
                            ledgerCalendarCell(day)
                        }
                        .buttonStyle(.plain)
                        .disabled(day.transactions.isEmpty)
                        .accessibilityLabel(LedgerCalendar.accessibilityLabel(for: day, currencyCode: currencyCode))
                    }
                }

                if calendarDays.allSatisfy(\.transactions.isEmpty) {
                    Text("No transactions in this month yet.")
                        .font(.caption)
                        .foregroundStyle(RainflowColor.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func metricCard(title: String, value: Int64, color: Color, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(color)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(RainflowColor.textSecondary)
            Text(value.formattedCurrency(code: currencyCode))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .minimumScaleFactor(0.75)
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RainflowColor.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func categoryRow(_ item: LedgerCategoryBreakdown) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: item.symbol)
                    .foregroundStyle(RainflowColor.brandAccent)
                    .frame(width: 32, height: 32)
                    .background(RainflowColor.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.subheadline.weight(.semibold))
                    Text("\(item.transactionCount) transaction\(item.transactionCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(RainflowColor.textSecondary)
                }
                Spacer()
                Text(item.amountMinorUnits.formattedCurrency(code: currencyCode))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }

            GeometryReader { geometry in
                Capsule()
                    .fill(RainflowColor.surfaceElevated)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(RainflowColor.brandAccent)
                            .frame(width: geometry.size.width * CGFloat(Double(item.amountMinorUnits) / Double(maxCategoryAmount)))
                    }
            }
            .frame(height: 7)
        }
        .padding(.vertical, 6)
    }

    private var calendarDays: [LedgerCalendarDay] {
        LedgerCalendar.days(in: visibleMonth, transactions: transactions)
    }

    private func ledgerCalendarCell(_ day: LedgerCalendarDay) -> some View {
        let hasTransactions = !day.transactions.isEmpty

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(LedgerCalendar.dayNumber(for: day.date))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(LedgerCalendar.isToday(day.date) ? RainflowColor.brandAccent : RainflowColor.textPrimary)
                Spacer()
            }

            Spacer(minLength: 0)

            Text(hasTransactions ? day.netMinorUnits.formattedCurrency(code: currencyCode, showPlus: day.netMinorUnits > 0) : "—")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .monospacedDigit()
                .foregroundStyle(hasTransactions ? cashFlowColor(day.netMinorUnits) : RainflowColor.textSecondary)

            Text(hasTransactions ? "\(day.transactions.count) tx" : " ")
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .lineLimit(1)
                .foregroundStyle(RainflowColor.textSecondary)
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
        .background(hasTransactions ? RainflowColor.surfaceElevated : RainflowColor.surface.opacity(0.45))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(LedgerCalendar.isToday(day.date) ? RainflowColor.brandAccent : RainflowColor.border.opacity(0.65), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func cashFlowColor(_ value: Int64) -> Color {
        if value > 0 { return RainflowColor.income }
        if value < 0 { return RainflowColor.expense }
        return RainflowColor.textSecondary
    }

    private func moveVisibleMonth(by value: Int) {
        visibleMonth = LedgerCalendar.month(byAdding: value, to: visibleMonth)
    }

    private func transactionList(title: String, transactions: [TransactionSummary]) -> some View {
        FinanceCard {
            VStack(spacing: 0) {
                HStack {
                    Text(title)
                        .font(.headline)
                    Spacer()
                    Text("\(transactions.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(RainflowColor.textSecondary)
                }
                .padding(.bottom, 8)

                if transactions.isEmpty {
                    EmptyStateView(
                        symbol: "list.bullet.rectangle",
                        title: "No transactions",
                        message: "Transactions posted to this ledger will appear here."
                    )
                } else {
                    ForEach(Array(transactions.enumerated()), id: \.element.id) { index, transaction in
                        TransactionRow(transaction: transaction, currencyCode: currencyCode)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedTransaction = fullTransaction(for: transaction.id)
                            }
                            .accessibilityAddTraits(.isButton)
                        if index < transactions.count - 1 {
                            Divider().overlay(RainflowColor.border)
                        }
                    }
                }
            }
        }
    }

    private func detailMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundStyle(RainflowColor.textSecondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
        }
    }

    private func positiveMagnitude(_ value: Int64) -> Int64 {
        value == .min ? .max : Swift.abs(value)
    }

    private func addingClamped(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        let (value, overflow) = lhs.addingReportingOverflow(rhs)
        if !overflow { return value }
        return rhs >= 0 ? .max : .min
    }

    private func fullTransaction(for id: UUID) -> TransactionRecord? {
        ledgerStore.snapshot?.activeTransactions.first { $0.id == id }
    }
}

private struct LedgerCategoryBreakdown: Identifiable {
    var id: String { name }
    let name: String
    let amountMinorUnits: Int64
    let transactionCount: Int
    let symbol: String
}

private struct LedgerCalendarDay: Identifiable, Hashable {
    let date: Date
    let transactions: [TransactionSummary]
    let incomeMinorUnits: Int64
    let expenseMinorUnits: Int64

    var id: String { LedgerCalendar.dayID(for: date) }
    var netMinorUnits: Int64 { incomeMinorUnits - expenseMinorUnits }
}

private enum LedgerCalendar {
    static let calendar: Calendar = {
        var calendar = Calendar.current
        calendar.timeZone = .current
        return calendar
    }()

    static let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    static var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let offset = calendar.firstWeekday - 1
        return Array(symbols[offset..<symbols.count]) + Array(symbols[0..<offset])
    }

    static func currentMonthStart() -> Date {
        monthStart(for: .now)
    }

    static func monthStart(for date: Date) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date
    }

    static func month(byAdding value: Int, to date: Date) -> Date {
        calendar.date(byAdding: .month, value: value, to: monthStart(for: date)) ?? date
    }

    static func monthTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = .current
        formatter.dateFormat = "MMM yyyy"
        return formatter.string(from: date)
    }

    static func fullDateTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = .current
        formatter.dateStyle = .full
        return formatter.string(from: date)
    }

    static func dayID(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }

    static func dayNumber(for date: Date) -> Int {
        calendar.component(.day, from: date)
    }

    static func isToday(_ date: Date) -> Bool {
        calendar.isDateInToday(date)
    }

    static func leadingEmptySlots(for date: Date) -> Int {
        let firstWeekday = calendar.component(.weekday, from: monthStart(for: date))
        return (firstWeekday - calendar.firstWeekday + 7) % 7
    }

    static func days(in month: Date, transactions: [TransactionSummary]) -> [LedgerCalendarDay] {
        let start = monthStart(for: month)
        guard let range = calendar.range(of: .day, in: .month, for: start) else { return [] }

        return range.compactMap { day -> LedgerCalendarDay? in
            guard let date = calendar.date(byAdding: .day, value: day - 1, to: start) else { return nil }
            let dayTransactions = transactions.filter { calendar.isDate($0.date, inSameDayAs: date) }
            let income = dayTransactions
                .filter { $0.kind == .income }
                .reduce(Int64.zero) { addingClamped($0, absMagnitude($1.amountMinorUnits)) }
            let expense = dayTransactions
                .filter { $0.kind == .expense }
                .reduce(Int64.zero) { addingClamped($0, absMagnitude($1.amountMinorUnits)) }

            return LedgerCalendarDay(
                date: date,
                transactions: dayTransactions,
                incomeMinorUnits: income,
                expenseMinorUnits: expense
            )
        }
    }

    static func accessibilityLabel(for day: LedgerCalendarDay, currencyCode: String) -> String {
        let cashFlow = day.netMinorUnits.formattedCurrency(code: currencyCode, showPlus: day.netMinorUnits > 0)
        return "\(fullDateTitle(for: day.date)), cash flow \(cashFlow), \(day.transactions.count) transactions"
    }

    private static func absMagnitude(_ value: Int64) -> Int64 {
        value == .min ? .max : Swift.abs(value)
    }

    private static func addingClamped(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        let (value, overflow) = lhs.addingReportingOverflow(rhs)
        if !overflow { return value }
        return rhs >= 0 ? .max : .min
    }
}

private struct LedgerDayTransactionsView: View {
    @EnvironmentObject private var ledgerStore: LedgerStore
    @Environment(\.dismiss) private var dismiss
    let day: LedgerCalendarDay
    let currencyCode: String
    @State private var selectedTransaction: TransactionRecord?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    FinanceCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Daily Cash Flow", systemImage: "calendar")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(RainflowColor.brandAccent)
                            Text(LedgerCalendar.fullDateTitle(for: day.date))
                                .font(.title2.weight(.semibold))
                            HStack {
                                dayMetric("Income", value: day.incomeMinorUnits, color: RainflowColor.income)
                                Spacer()
                                dayMetric("Spending", value: day.expenseMinorUnits, color: RainflowColor.expense)
                                Spacer()
                                dayMetric("Net", value: day.netMinorUnits, color: day.netMinorUnits >= 0 ? RainflowColor.income : RainflowColor.expense)
                            }
                        }
                    }

                    FinanceCard {
                        VStack(spacing: 0) {
                            HStack {
                                Text("Transactions")
                                    .font(.headline)
                                Spacer()
                                Text("\(day.transactions.count)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(RainflowColor.textSecondary)
                            }
                            .padding(.bottom, 8)

                            ForEach(Array(day.transactions.enumerated()), id: \.element.id) { index, transaction in
                                TransactionRow(transaction: transaction, currencyCode: currencyCode)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedTransaction = fullTransaction(for: transaction.id)
                                    }
                                    .accessibilityAddTraits(.isButton)
                                if index < day.transactions.count - 1 {
                                    Divider().overlay(RainflowColor.border)
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(RainflowColor.background)
            .navigationTitle("Day Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $selectedTransaction) { transaction in
                TransactionEditorView(transaction: transaction)
                    .environmentObject(ledgerStore)
            }
        }
    }

    private func dayMetric(_ label: String, value: Int64, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundStyle(RainflowColor.textSecondary)
            Text(value.formattedCurrency(code: currencyCode))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
                .monospacedDigit()
                .minimumScaleFactor(0.75)
        }
    }

    private func fullTransaction(for id: UUID) -> TransactionRecord? {
        ledgerStore.snapshot?.activeTransactions.first { $0.id == id }
    }
}

private struct LedgerMonthPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var visibleMonth: Date
    @State private var selectedYear: Int

    init(visibleMonth: Binding<Date>) {
        _visibleMonth = visibleMonth
        _selectedYear = State(initialValue: LedgerCalendar.calendar.component(.year, from: visibleMonth.wrappedValue))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Picker("Year", selection: $selectedYear) {
                    ForEach(yearRange, id: \.self) { year in
                        Text("\(year)").tag(year)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 120)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    ForEach(1...12, id: \.self) { month in
                        Button {
                            setMonth(month, year: selectedYear)
                            dismiss()
                        } label: {
                            Text(monthName(month))
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 46)
                                .background(isSelected(month: month, year: selectedYear) ? RainflowColor.brandAccent : RainflowColor.surfaceElevated)
                                .foregroundStyle(isSelected(month: month, year: selectedYear) ? Color.white : RainflowColor.textPrimary)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(18)
            .background(RainflowColor.background)
            .navigationTitle("Choose Month")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("This Month") {
                        visibleMonth = LedgerCalendar.currentMonthStart()
                        selectedYear = LedgerCalendar.calendar.component(.year, from: visibleMonth)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var yearRange: ClosedRange<Int> {
        let currentYear = LedgerCalendar.calendar.component(.year, from: .now)
        return (currentYear - 10)...(currentYear + 10)
    }

    private func monthName(_ month: Int) -> String {
        DateFormatter().shortMonthSymbols[month - 1]
    }

    private func setMonth(_ month: Int, year: Int) {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        visibleMonth = LedgerCalendar.calendar.date(from: components) ?? visibleMonth
    }

    private func isSelected(month: Int, year: Int) -> Bool {
        let components = LedgerCalendar.calendar.dateComponents([.year, .month], from: visibleMonth)
        return components.year == year && components.month == month
    }
}
