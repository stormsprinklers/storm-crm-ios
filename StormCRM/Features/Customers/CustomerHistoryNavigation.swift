import SwiftUI

enum CustomerListRoute: Hashable {
    case detail(id: String)
}

enum CustomerHistoryDestination: Hashable {
    case visit(String)
    case estimate(String)
    case invoice(String)
}

extension View {
    func customerHistoryDestinations() -> some View {
        navigationDestination(for: CustomerHistoryDestination.self) { destination in
            switch destination {
            case .visit(let visitId):
                VisitDetailView(visitId: visitId)
            case .estimate(let estimateId):
                EstimateDetailView(estimateId: estimateId)
            case .invoice(let invoiceId):
                InvoiceDetailView(invoiceId: invoiceId)
            }
        }
        .navigationDestination(for: CustomerListRoute.self) { route in
            switch route {
            case .detail(let customerId):
                CustomerDetailView(customerId: customerId)
            }
        }
    }
}
