import Testing
import Foundation
import Network
@testable import Networking

@MainActor
struct ConnectivityTests {

  @Test("Add observe reachability increments handlers")
  func addObserverIncrementsHandlers() async throws {
    // Reset handlers to a known state
    Networking.Connectivity.monitorChangeHandlers = []
    let before = Networking.Connectivity.monitorChangeHandlers.count

    let noop: Networking.Connectivity.Handler = { _ in }
    Networking.Connectivity.addObserveReachabilityChange(handler: noop)

    let after = Networking.Connectivity.monitorChangeHandlers.count
    #expect(after == before + 1)
  }

  @Test("Reachability returns a boolean without crashing")
  func reachabilitySafeCall() async throws {
    let reachable = Networking.Connectivity.isNetworkReachability()
    // This assertion ensures the call is made and returns a valid Bool.
    #expect([true, false].contains(reachable))
  }
}
