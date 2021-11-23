import Network
import SystemConfiguration

extension Networking {
  
  public enum ConnectionState {
    case available
    case unavailable
    case noConnection
  }
  
  public class Connectivity {
    @available(iOS 12.0, macOS 10.14, *)
    private static var monitor: NWPathMonitor? = NWPathMonitor()
  }
}

extension Networking.Connectivity {
  public typealias Handler = (Networking.ConnectionState) -> Void
  
  public static func isNetworkReacability() -> Bool {
    if #available(iOS 12.0, macOS 10.14, *) {
      guard
        // if there are no interfaces, the current path is none.
        let monitor = monitor,
        monitor.currentPath.availableInterfaces.count > 0
      else {
        return false
      }
      return monitor.currentPath.status == .satisfied
    } else {
      return isReachability()
    }
  }
  
  /// Check reachability in iOS lower than 12
  /// - Returns: is Network status reachability or not
  private static func isReachability() -> Bool {
    var zeroAddress = sockaddr_in()
    zeroAddress.sin_len = UInt8(MemoryLayout.size(ofValue: zeroAddress))
    zeroAddress.sin_family = sa_family_t(AF_INET)
    
    guard
      let defaultRouteReachability = withUnsafePointer(
        to:&zeroAddress, {
          $0.withMemoryRebound(
            to: sockaddr.self,
            capacity: 1
          ) { zeroSockAddress in
            SCNetworkReachabilityCreateWithAddress(nil, zeroSockAddress)
          }
        }
      )
    else {
      return false
    }
    
    var flags : SCNetworkReachabilityFlags = []
    if !SCNetworkReachabilityGetFlags(defaultRouteReachability, &flags) {
      return false
    }
    
    let isReachable = flags.contains(.reachable)
    let needsConnection = flags.contains(.connectionRequired)
    
    return (isReachable && !needsConnection)
  }
}

@available(iOS 12.0, macOS 10.14, *)
extension Networking.Connectivity {
  
  public static var monitorChangeHandlers:
  [Handler] = [] {
    didSet {
      var newState: Networking.ConnectionState = .noConnection
      // re-assign the observe events
      monitor?.pathUpdateHandler = { path in
        switch path.status {
        case .satisfied:
          newState = .available
        case .unsatisfied:
          newState = .unavailable
        case .requiresConnection:
          newState = .noConnection
        @unknown default:
          break
        }
        for handler in monitorChangeHandlers {
          handler(newState)
        }
      }
    }
  }
  
  static func addObserveReachabilityChange(
    handler: @escaping ((Networking.ConnectionState) -> Void)
  ) {
    // start the queue if needed
    if let _ = monitor?.queue { } else {
      let queue = DispatchQueue(label: "Monitor")
      monitor?.start(queue: queue)
    }
    
    monitorChangeHandlers.append(handler)
  }
}
