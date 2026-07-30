import Charts
import SwiftUI

struct ReportsView: View {
    @EnvironmentObject private var ledgerStore: LedgerStore
    @State private var report: ReportKind = .cashFlow

    private var currencyCode: String { ledgerStore.snapshot?.ledger.currencyCode ?? "USD" }
    private var cashFlowPoints: [CashFlowPoint] { ledgerStore.snapshot?.cashFlowPoints ?? [] }
    private var spending: [SpendingSlice] { ledgerStore.snapshot?.currentMonthSpending ?? [] }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ScreenHeader(title: "Reports", trailingSymbol: "arrow.clockwise", trailingAccessibilityLabel: "Refresh") {
                        Task { await ledgerStore.refresh() }
                    }
                    Picker("Report", selection: $report) {
                        ForEach(ReportKind.allCases) { kind in
                            Text(kind.rawValue).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)

                    switch report {
                    case .cashFlow:
                        cashFlowReport
                    case .spending:
                        categoryReport(title: "Spending by Category", slices: spending, positiveColor: RainflowColor.expense)
                    case .income:
                        incomeReport
                    }
                }
                .padding(.bottom, 24)
            }
            .refreshable { await ledgerStore.refresh() }
            .background(RainflowColor.background)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var cashFlowReport: some View {
        VStack(spacing: 16) {
            FinanceCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Six-Month Cash Flow")
                        .font(.headline)
                    if cashFlowPoints.isEmpty || cashFlowPoints.allSatisfy({ $0.income == 0 && $0.expense == 0 }) {
                        EmptyStateView(
                            symbol: "chart.bar.xaxis",
                            title: "Not enough data",
                            message: "Cash-flow charts will appear as you record income and expenses."
                        )
                    } else {
                        Chart(cashFlowPoints) { point in
                            BarMark(
                                x: .value("Month", point.label),
                                y: .value("Income", point.income)
                            )
                            .foregroundStyle(RainflowColor.income)
                            BarMark(
                                x: .value("Month", point.label),
                                y: .value("Expense", -point.expense)
                            )
                            .foregroundStyle(RainflowColor.expense)
                        }
                        .chartLegend(.hidden)
                        .frame(height: 230)
                    }
                }
            }
            summaryCard
        }
        .padding(.horizontal, 16)
    }

    private var summaryCard: some View {
        FinanceCard {
            VStack(spacing: 13) {
                reportRow("Income", value: ledgerStore.cashFlow.incomeMinorUnits, color: RainflowColor.income)
                reportRow("Spending", value: -ledgerStore.cashFlow.expenseMinorUnits, color: RainflowColor.expense)
                Divider().overlay(RainflowColor.border)
                reportRow(
                    "Net Cash Flow",
                    value: ledgerStore.cashFlow.netMinorUnits,
                    color: ledgerStore.cashFlow.netMinorUnits >= 0 ? RainflowColor.income : RainflowColor.expense
                )
            }
        }
    }

    private func categoryReport(title: String, slices: [SpendingSlice], positiveColor: Color) -> some View {
        FinanceCard {
            VStack(alignment: .leading, spacing: 16) {
                Text(title)
                    .font(.headline)
                if slices.isEmpty {
                    EmptyStateView(
                        symbol: "chart.pie",
                        title: "No category activity",
                        message: "This month has no matching transactions yet."
                    )
                } else {
                    Chart(slices) { slice in
                        SectorMark(
                            angle: .value("Amount", slice.amountMinorUnits),
                            innerRadius: .ratio(0.62),
                            angularInset: 2
                        )
                        .foregroundStyle(by: .value("Category", slice.name))
                    }
                    .frame(height: 230)
                    .chartLegend(position: .bottom, alignment: .leading, spacing: 8)

                    ForEach(slices.prefix(6)) { slice in
                        HStack {
                            Text(slice.name)
                                .foregroundStyle(RainflowColor.textSecondary)
                            Spacer()
                            Text(slice.amountMinorUnits.formattedCurrency(code: currencyCode))
                                .foregroundStyle(positiveColor)
                                .fontWeight(.semibold)
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private var incomeReport: some View {
        FinanceCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Income")
                    .font(.headline)
                Text(ledgerStore.cashFlow.incomeMinorUnits.formattedCurrency(code: currencyCode))
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(RainflowColor.income)
                    .monospacedDigit()
                Text("Income category details will expand as more income transactions are recorded.")
                    .font(.callout)
                    .foregroundStyle(RainflowColor.textSecondary)
            }
        }
        .padding(.horizontal, 16)
    }

    private func reportRow(_ label: String, value: Int64, color: Color) -> some View {
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
}

enum ReportKind: String, CaseIterable, Identifiable {
    case cashFlow = "Cash Flow"
    case spending = "Spending"
    case income = "Income"
    var id: String { rawValue }
}
