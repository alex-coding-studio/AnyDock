import SystemConfiguration
import Testing
@testable import AnyDock

@Test("接收地址使用 SCDynamicStore 的本地主机名拼成 .local，拿不到时退回网卡地址，不做 DNS 解析")
func receiveAddressUsesLocalHostNameWithoutResolving() {
    #expect(
        LocalHost.receiveAddress(port: 8766, localHostName: { "Studio" }, interfaceAddress: { nil })
            == "http://Studio.local:8766/upload"
    )
    #expect(
        LocalHost.receiveAddress(
            port: 8766,
            localHostName: { nil },
            interfaceAddress: { "192.168.1.20" }
        )
            == "http://192.168.1.20:8766/upload"
    )
    #expect(
        LocalHost.receiveAddress(port: 8766, localHostName: { "" }, interfaceAddress: { nil })
            == "http://localhost:8766/upload"
    )
    if let name = SCDynamicStoreCopyLocalHostName(nil) as String?, !name.isEmpty {
        #expect(LocalHost.receiveAddress(port: 1) == "http://\(name).local:1/upload")
    }
}
