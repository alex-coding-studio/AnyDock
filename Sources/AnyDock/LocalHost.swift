import Darwin
import SystemConfiguration

enum LocalHost {
  static func receiveAddress(
    port: UInt16,
    localHostName: () -> String? = { SCDynamicStoreCopyLocalHostName(nil) as String? },
    interfaceAddress: () -> String? = LocalHost.interfaceAddress
  ) -> String {
    let host =
      localHostName().flatMap { $0.isEmpty ? nil : "\($0).local" } ?? interfaceAddress()
      ?? "localhost"
    return "http://\(host):\(port)/upload"
  }

  static func computerName() -> String? {
    SCDynamicStoreCopyComputerName(nil, nil) as String?
  }

  static func interfaceAddress() -> String? {
    var list: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&list) == 0, let first = list else { return nil }
    defer { freeifaddrs(list) }
    for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
      let entry = pointer.pointee
      let flags = Int32(entry.ifa_flags)
      guard let address = entry.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
        flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0
      else { continue }
      var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
      guard
        getnameinfo(
          address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0,
          NI_NUMERICHOST) == 0
      else { continue }
      return String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
    return nil
  }
}
