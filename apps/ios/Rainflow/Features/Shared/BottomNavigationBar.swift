import SwiftUI

struct BottomNavigationBar: View {
    @Binding var selection: AppDestination
    let captureAction: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            item(.dashboard)
            item(.ledgers)
            captureButton
            item(.accounts)
            item(.reports)
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Divider().overlay(RainflowColor.border)
        }
    }

    private func item(_ destination: AppDestination) -> some View {
        Button {
            selection = destination
        } label: {
            VStack(spacing: 4) {
                Image(systemName: destination.symbol)
                    .font(.system(size: 18, weight: .semibold))
                Text(destination.title)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .foregroundStyle(selection == destination ? RainflowColor.textPrimary : RainflowColor.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
        }
        .buttonStyle(.plain)
    }

    private var captureButton: some View {
        Button(action: captureAction) {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(RainflowColor.brand)
                        .frame(width: 50, height: 50)
                    Circle()
                        .stroke(RainflowColor.brandAccent.opacity(0.65), lineWidth: 3)
                        .frame(width: 58, height: 58)
                    Image(systemName: "camera.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                }
                Text("Capture")
                    .font(.caption2)
                    .foregroundStyle(RainflowColor.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .offset(y: -12)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Capture receipt or add transaction")
    }
}
