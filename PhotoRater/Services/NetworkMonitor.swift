import Foundation
import Network
import Combine
import FirebaseFirestore

/// Monitors network connectivity so services can avoid failing when offline.
class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    @Published private(set) var isConnected: Bool = true

    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "NetworkMonitor")

    private init() {
        monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            DispatchQueue.main.async {
                self?.isConnected = connected
                if connected {
                    Firestore.firestore().enableNetwork(completion: nil)
                } else {
                    Firestore.firestore().disableNetwork(completion: nil)
                }
            }
        }
        monitor.start(queue: queue)
    }
}
