import SwiftUI
import UIKit

struct AppRootView: View {
    @EnvironmentObject private var ledgerStore: LedgerStore
    @State private var destination: AppDestination = .dashboard
    @State private var isCapturePresented = false
    @State private var isCameraPresented = false
    @State private var transactionEntry: TransactionEntryContext?
    @State private var shouldOpenManualAfterCaptureDismissal = false
    @State private var shouldOpenCameraAfterCaptureDismissal = false
    @State private var pendingCaptureReceiptData: Data?
    @State private var pendingCameraReceiptData: Data?

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                if case .ready(isOffline: true) = ledgerStore.phase {
                    Label("Offline copy — new entries require a connection", systemImage: "wifi.slash")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(RainflowColor.warning.opacity(0.18))
                        .foregroundStyle(RainflowColor.warning)
                }

                Group {
                    switch destination {
                    case .dashboard:
                        DashboardView(destination: $destination)
                    case .ledgers:
                        LedgersView()
                    case .accounts:
                        AccountsView()
                    case .reports:
                        ReportsView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(RainflowColor.background.ignoresSafeArea())
            .safeAreaPadding(.bottom, 78)

            BottomNavigationBar(
                selection: $destination,
                captureAction: { isCapturePresented = true }
            )
        }
        .sheet(isPresented: $isCapturePresented, onDismiss: {
            if shouldOpenManualAfterCaptureDismissal {
                shouldOpenManualAfterCaptureDismissal = false
                transactionEntry = TransactionEntryContext(receiptData: pendingCaptureReceiptData)
                pendingCaptureReceiptData = nil
            } else if shouldOpenCameraAfterCaptureDismissal {
                shouldOpenCameraAfterCaptureDismissal = false
                isCameraPresented = true
            }
        }) {
            CaptureHubView(
                onTakePhoto: {
                    openCameraAfterCaptureDismissal()
                },
                onManualEntry: {
                    openManualTransactionAfterCaptureDismissal(receiptData: nil)
                },
                onReceiptEntry: { data in
                    openManualTransactionAfterCaptureDismissal(receiptData: data)
                }
            )
                .presentationDetents([.height(360)])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $isCameraPresented, onDismiss: {
            guard let pendingCameraReceiptData else { return }
            transactionEntry = TransactionEntryContext(receiptData: pendingCameraReceiptData)
            self.pendingCameraReceiptData = nil
        }) {
            CameraPicker { image in
                if let data = image.normalizedReceiptJPEGData() {
                    pendingCameraReceiptData = data
                }
                isCameraPresented = false
            } onCancel: {
                pendingCameraReceiptData = nil
                isCameraPresented = false
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(item: $transactionEntry) { entry in
            ManualTransactionFlowView(receiptData: entry.receiptData) {
                transactionEntry = nil
            }
        }
        .alert("Rainflow", isPresented: Binding(
            get: { ledgerStore.noticeMessage != nil },
            set: { if !$0 { ledgerStore.noticeMessage = nil } }
        )) {
            Button("OK", role: .cancel) { ledgerStore.noticeMessage = nil }
        } message: {
            Text(ledgerStore.noticeMessage ?? "")
        }
    }

    private func openManualTransactionAfterCaptureDismissal(receiptData: Data?) {
        pendingCaptureReceiptData = receiptData
        shouldOpenManualAfterCaptureDismissal = true
        isCapturePresented = false
    }

    private func openCameraAfterCaptureDismissal() {
        shouldOpenCameraAfterCaptureDismissal = true
        isCapturePresented = false
    }
}

private struct TransactionEntryContext: Identifiable {
    let id = UUID()
    let receiptData: Data?
}

enum AppDestination: String, CaseIterable, Identifiable {
    case dashboard
    case ledgers
    case accounts
    case reports

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .ledgers: "Ledgers"
        case .accounts: "Accounts"
        case .reports: "Reports"
        }
    }

    var symbol: String {
        switch self {
        case .dashboard: "house.fill"
        case .ledgers: "book.closed.fill"
        case .accounts: "square.3.layers.3d.top.filled"
        case .reports: "chart.pie.fill"
        }
    }
}
