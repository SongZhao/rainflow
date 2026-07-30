import Charts
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var authStore: AuthStore
    @EnvironmentObject private var ledgerStore: LedgerStore
    @Binding var destination: AppDestination
    @State private var selectedTransaction: TransactionRecord?

    private var currencyCode: String { ledgerStore.snapshot?.ledger.currencyCode ?? "USD" }
    private var transactions: [TransactionSummary] { ledgerStore.transactions }
    private var cashFlowPoints: [CashFlowPoint] { ledgerStore.snapshot?.cashFlowPoints ?? [] }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header
                    netWorthCard
                    cashFlowCard
                    recentTransactionsCard
                }
                .padding(.bottom, 24)
            }
            .refreshable { await ledgerStore.refresh() }
            .scrollIndicators(.hidden)
            .background(RainflowColor.background)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $selectedTransaction) { transaction in
                TransactionEditorView(transaction: transaction)
                    .environmentObject(ledgerStore)
            }
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "drop.fill")
                .foregroundStyle(RainflowColor.brandAccent)
            VStack(alignment: .leading, spacing: 1) {
                Text("Dashboard")
                    .font(.title2.weight(.semibold))
                Text(ledgerStore.snapshot?.ledger.name ?? "Rainflow")
                    .font(.caption)
                    .foregroundStyle(RainflowColor.textSecondary)
            }
            Spacer()
            Menu {
                Button {
                    Task { await ledgerStore.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                Button(role: .destructive) {
                    Task { await authStore.signOut() }
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            } label: {
                Image(systemName: "person.crop.circle.fill")
                    .font(.title2)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Account menu")
        }
        .foregroundStyle(RainflowColor.textPrimary)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var netWorthCard: some View {
        FinanceCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Net Worth")
                    .font(.headline)
                Text((ledgerStore.snapshot?.netWorthMinorUnits ?? 0).formattedCurrency(code: currencyCode))
                    .font(.largeTitle.weight(.semibold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.72)

                if cashFlowPoints.isEmpty || cashFlowPoints.allSatisfy({ $0.net == 0 }) {
                    EmptyStateView(
                        symbol: "chart.line.uptrend.xyaxis",
                        title: "Your trend starts here",
                        message: "Add transactions and Rainflow will build your net-worth history."
                    )
                    .padding(.vertical, -8)
                } else {
                    Chart(cashFlowPoints) { point in
                        LineMark(
                            x: .value("Month", point.label),
                            y: .value("Net cash flow", point.net)
                        )
                        .foregroundStyle(RainflowColor.brandAccent)
                        .interpolationMethod(.catmullRom)
                        AreaMark(
                            x: .value("Month", point.label),
                            y: .value("Net cash flow", point.net)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [RainflowColor.brand.opacity(0.32), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .frame(height: 120)
                    .accessibilityLabel("Six month cash-flow trend")
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private var cashFlowCard: some View {
        FinanceCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Cash Flow")
                        .font(.headline)
                    Spacer()
                    Text("This Month")
                        .font(.caption)
                        .foregroundStyle(RainflowColor.textSecondary)
                }
                metricRow(label: "Income", value: ledgerStore.cashFlow.incomeMinorUnits, color: RainflowColor.income)
                metricRow(label: "Expenses", value: -ledgerStore.cashFlow.expenseMinorUnits, color: RainflowColor.expense)
                metricRow(
                    label: "Net",
                    value: ledgerStore.cashFlow.netMinorUnits,
                    color: ledgerStore.cashFlow.netMinorUnits >= 0 ? RainflowColor.income : RainflowColor.expense
                )

                GeometryReader { geometry in
                    let income = max(Double(ledgerStore.cashFlow.incomeMinorUnits), 0)
                    let expense = max(Double(ledgerStore.cashFlow.expenseMinorUnits), 0)
                    let total = max(income + expense, 1)
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(RainflowColor.income)
                            .frame(width: geometry.size.width * income / total)
                        Rectangle().fill(RainflowColor.expense)
                    }
                    .clipShape(Capsule())
                }
                .frame(height: 8)
            }
        }
        .padding(.horizontal, 16)
    }

    private var recentTransactionsCard: some View {
        FinanceCard {
            VStack(spacing: 0) {
                HStack {
                    Text("Recent Transactions")
                        .font(.headline)
                    Spacer()
                    Button("Open ledger") { destination = .ledgers }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(RainflowColor.brandAccent)
                }
                .padding(.bottom, 8)

                if transactions.isEmpty {
                    EmptyStateView(
                        symbol: "camera.fill",
                        title: "No transactions yet",
                        message: "Use the center Capture button to add your first expense or income."
                    )
                } else {
                    ForEach(Array(transactions.prefix(4).enumerated()), id: \.element.id) { index, transaction in
                        TransactionRow(transaction: transaction, currencyCode: currencyCode)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedTransaction = fullTransaction(for: transaction.id)
                            }
                            .accessibilityAddTraits(.isButton)
                        if index < min(transactions.count, 4) - 1 {
                            Divider().overlay(RainflowColor.border)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func metricRow(label: String, value: Int64, color: Color) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(RainflowColor.textSecondary)
            Spacer()
            Text(value.formattedCurrency(code: currencyCode))
                .foregroundStyle(color)
                .fontWeight(.semibold)
            .monospacedDigit()
        }
    }

    private func fullTransaction(for id: UUID) -> TransactionRecord? {
        ledgerStore.snapshot?.activeTransactions.first { $0.id == id }
    }
}
