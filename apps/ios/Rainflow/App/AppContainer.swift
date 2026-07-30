import Combine
import Foundation
import Supabase

@MainActor
final class AppContainer: ObservableObject {
    let configuration: AppConfiguration
    let supabase: SupabaseClient?
    let database: AppDatabase?
    let receiptStore: ReceiptStore
    let authStore: AuthStore
    let ledgerStore: LedgerStore

    init() {
        let configuration = AppConfiguration.load()
        let receiptStore = ReceiptStore()

        let database: AppDatabase?
        let databaseMessage: String?
        do {
            database = try AppDatabase.live()
            databaseMessage = nil
        } catch {
            database = nil
            databaseMessage = "Rainflow could not initialize its protected local database. Free device storage, restart the app, and try again. Technical detail: \(error.localizedDescription)"
        }

        let startupMessage = configuration.validationMessage ?? databaseMessage
        let supabase = startupMessage == nil ? configuration.makeSupabaseClient() : nil
        let api = supabase.map { SupabaseLedgerAPI(client: $0) }

        self.configuration = configuration
        self.supabase = supabase
        self.database = database
        self.receiptStore = receiptStore
        self.authStore = AuthStore(
            client: supabase,
            configurationMessage: startupMessage
        )
        self.ledgerStore = LedgerStore(
            api: api,
            database: database,
            receiptStore: receiptStore
        )
    }
}
