import SwiftUI

struct TransactionRow: View {
    let transaction: TransactionSummary
    var currencyCode = "USD"

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: transaction.symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 40, height: 40)
                .background(iconColor.opacity(0.13))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(transaction.payee)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    if transaction.hasReceipt {
                        Image(systemName: "paperclip")
                            .font(.caption2)
                            .foregroundStyle(RainflowColor.textSecondary)
                            .accessibilityLabel("Receipt attached")
                    }
                }
                Text(transaction.category)
                    .font(.caption)
                    .foregroundStyle(RainflowColor.textSecondary)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(transaction.amountMinorUnits.formattedCurrency(
                    code: currencyCode,
                    showPlus: transaction.kind == .income
                ))
                .font(.body.weight(.semibold))
                .foregroundStyle(amountColor)
                .monospacedDigit()
                Text(transaction.date, format: .dateTime.month(.abbreviated).day())
                    .font(.caption2)
                    .foregroundStyle(RainflowColor.textSecondary)
            }
        }
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    private var amountColor: Color {
        switch transaction.kind {
        case .income: RainflowColor.income
        case .expense: RainflowColor.expense
        case .transfer: RainflowColor.textPrimary
        }
    }

    private var iconColor: Color {
        switch transaction.kind {
        case .income: RainflowColor.income
        case .expense: RainflowColor.brandAccent
        case .transfer: RainflowColor.brand
        }
    }
}
