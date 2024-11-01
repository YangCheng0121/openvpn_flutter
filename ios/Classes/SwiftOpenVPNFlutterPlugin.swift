import Flutter
import UIKit
import NetworkExtension

public class SwiftOpenVPNFlutterPlugin: NSObject, FlutterPlugin {
    private static var utils: VPNUtils! = VPNUtils()
    
    private static var EVENT_CHANNEL_VPN_STAGE = "id.laskarmedia.openvpn_flutter/vpnstage"
    private static var METHOD_CHANNEL_VPN_CONTROL = "id.laskarmedia.openvpn_flutter/vpncontrol"
    
    public static var stage: FlutterEventSink?
    private var initialized: Bool = false
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = SwiftOpenVPNFlutterPlugin()
        instance.onRegister(registrar)
    }
    
    public func onRegister(_ registrar: FlutterPluginRegistrar) {
        // 创建方法通道和事件通道
        let vpnControlM = FlutterMethodChannel(name: SwiftOpenVPNFlutterPlugin.METHOD_CHANNEL_VPN_CONTROL, binaryMessenger: registrar.messenger())
        let vpnStageE = FlutterEventChannel(name: SwiftOpenVPNFlutterPlugin.EVENT_CHANNEL_VPN_STAGE, binaryMessenger: registrar.messenger())
        
        vpnStageE.setStreamHandler(StageHandler())
        vpnControlM.setMethodCallHandler({ (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
            switch call.method {
            case "status":
                SwiftOpenVPNFlutterPlugin.utils.getTraffictStats()
                result(UserDefaults.init(suiteName: SwiftOpenVPNFlutterPlugin.utils.groupIdentifier)?.string(forKey: "connectionUpdate"))
                break
            case "stage":
                result(SwiftOpenVPNFlutterPlugin.utils.currentStatus())
                break
            case "initialize":
                // 解析初始化参数
                let providerBundleIdentifier: String? = (call.arguments as? [String: Any])?["providerBundleIdentifier"] as? String
                let localizedDescription: String? = (call.arguments as? [String: Any])?["localizedDescription"] as? String
                let groupIdentifier: String? = (call.arguments as? [String: Any])?["groupIdentifier"] as? String
                
                // 检查参数是否为空
                if providerBundleIdentifier == nil {
                    result(FlutterError(code: "-2", message: "providerBundleIdentifier 内容为空或为 null", details: nil))
                    return
                }
                if localizedDescription == nil {
                    result(FlutterError(code: "-3", message: "localizedDescription 内容为空或为 null", details: nil))
                    return
                }
                if groupIdentifier == nil {
                    result(FlutterError(code: "-4", message: "groupIdentifier 内容为空或为 null", details: nil))
                    return
                }
                
                // 设置 VPN 配置
                SwiftOpenVPNFlutterPlugin.utils.groupIdentifier = groupIdentifier
                SwiftOpenVPNFlutterPlugin.utils.localizedDescription = localizedDescription
                SwiftOpenVPNFlutterPlugin.utils.providerBundleIdentifier = providerBundleIdentifier
                
                SwiftOpenVPNFlutterPlugin.utils.loadProviderManager { (err: Error?) in
                    if err == nil {
                        result(SwiftOpenVPNFlutterPlugin.utils.currentStatus())
                    } else {
                        result(FlutterError(code: "-4", message: err?.localizedDescription, details: err?.localizedDescription))
                    }
                }
                self.initialized = true
                break
            case "disconnect":
                // 断开 VPN 连接
                SwiftOpenVPNFlutterPlugin.utils.stopVPN()
                break
            case "connect":
                if !self.initialized {
                    result(FlutterError(code: "-1", message: "VPNEngine 需要初始化", details: nil))
                }
                let config: String? = (call.arguments as? [String: Any])?["config"] as? String
                let username: String? = (call.arguments as? [String: Any])?["username"] as? String
                let password: String? = (call.arguments as? [String: Any])?["password"] as? String
                
                if config == nil {
                    result(FlutterError(code: "-2", message: "Config 为空或为 null", details: "Config 不能为空"))
                    return
                }
                
                // 配置并连接 VPN
                SwiftOpenVPNFlutterPlugin.utils.configureVPN(config: config, username: username, password: password, completion: { (success: Error?) -> Void in
                    if success == nil {
                        result(nil)
                    } else {
                        result(FlutterError(code: "99", message: "权限被拒绝", details: success?.localizedDescription))
                    }
                })
                break
            case "dispose":
                self.initialized = false
            default:
                break
            }
        })
    }
    
    class StageHandler: NSObject, FlutterStreamHandler {
        func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
            SwiftOpenVPNFlutterPlugin.utils.stage = events
            return nil
        }
        
        func onCancel(withArguments arguments: Any?) -> FlutterError? {
            SwiftOpenVPNFlutterPlugin.utils.stage = nil
            return nil
        }
    }
}

@available(iOS 9.0, *)
class VPNUtils {
    var providerManager: NETunnelProviderManager!
    var providerBundleIdentifier: String?
    var localizedDescription: String?
    var groupIdentifier: String?
    var stage: FlutterEventSink!
    var vpnStageObserver: NSObjectProtocol?
    
    func loadProviderManager(completion: @escaping (_ error: Error?) -> Void) {
        // 从偏好设置中加载 VPN 提供程序管理器
        NETunnelProviderManager.loadAllFromPreferences { (managers, error) in
            if error == nil {
                self.providerManager = managers?.first ?? NETunnelProviderManager()
                completion(nil)
            } else {
                completion(error)
            }
        }
    }
    
    func onVpnStatusChanged(notification: NEVPNStatus) {
        // 处理 VPN 状态变化
        switch notification {
        case NEVPNStatus.connected:
            stage?("connected")
            break
        case NEVPNStatus.connecting:
            stage?("connecting")
            break
        case NEVPNStatus.disconnected:
            stage?("disconnected")
            break
        case NEVPNStatus.disconnecting:
            stage?("disconnecting")
            break
        case NEVPNStatus.invalid:
            stage?("invalid")
            break
        case NEVPNStatus.reasserting:
            stage?("reasserting")
            break
        default:
            stage?("null")
            break
        }
    }
    
    func onVpnStatusChangedString(notification: NEVPNStatus?) -> String? {
        // 将 VPN 状态转换为字符串
        if notification == nil {
            return "disconnected"
        }
        switch notification! {
        case NEVPNStatus.connected:
            return "connected"
        case NEVPNStatus.connecting:
            return "connecting"
        case NEVPNStatus.disconnected:
            return "disconnected"
        case NEVPNStatus.disconnecting:
            return "disconnecting"
        case NEVPNStatus.invalid:
            return "invalid"
        case NEVPNStatus.reasserting:
            return "reasserting"
        default:
            return ""
        }
    }
    
    func currentStatus() -> String? {
        // 获取当前 VPN 状态
        if self.providerManager != nil {
            return onVpnStatusChangedString(notification: self.providerManager.connection.status)
        } else {
            return "disconnected"
        }
    }
    
    func configureVPN(config: String?, username: String?, password: String?, completion: @escaping (_ error: Error?) -> Void) {
        // 配置 VPN
        let configData = config
        self.providerManager?.loadFromPreferences { error in
            if error == nil {
                let tunnelProtocol = NETunnelProviderProtocol()
                tunnelProtocol.serverAddress = ""
                tunnelProtocol.providerBundleIdentifier = self.providerBundleIdentifier
                let nullData = "".data(using: .utf8)
                tunnelProtocol.providerConfiguration = [
                    "config": configData?.data(using: .utf8) ?? nullData!,
                    "groupIdentifier": self.groupIdentifier?.data(using: .utf8) ?? nullData!,
                    "username": username?.data(using: .utf8) ?? nullData!,
                    "password": password?.data(using: .utf8) ?? nullData!
                ]
                tunnelProtocol.disconnectOnSleep = false
                self.providerManager.protocolConfiguration = tunnelProtocol
                self.providerManager.localizedDescription = self.localizedDescription // VPN 配置在设置中显示的标题
                self.providerManager.isEnabled = true
                self.providerManager.saveToPreferences(completionHandler: { (error) in
                    if error == nil {
                        self.providerManager.loadFromPreferences(completionHandler: { (error) in
                            if error != nil {
                                completion(error)
                                return
                            }
                            do {
                                // 观察 VPN 状态变化
                                if self.vpnStageObserver != nil {
                                    NotificationCenter.default.removeObserver(self.vpnStageObserver!,
                                                                              name: NSNotification.Name.NEVPNStatusDidChange,
                                                                              object: nil)
                                }
                                self.vpnStageObserver = NotificationCenter.default.addObserver(forName: NSNotification.Name.NEVPNStatusDidChange,
                                                                                               object: nil,
                                                                                               queue: nil) { [weak self] notification in
                                    let nevpnconn = notification.object as! NEVPNConnection
                                    let status = nevpnconn.status
                                    self?.onVpnStatusChanged(notification: status)
                                }
                                
                                // 开始 VPN 连接
                                if username != nil && password != nil {
                                    let options: [String: NSObject] = [
                                        "username": username! as NSString,
                                        "password": password! as NSString
                                    ]
                                    try self.providerManager.connection.startVPNTunnel(options: options)
                                    completion(nil)
                                } else {
                                    completion(FlutterError(code: "-2", message: "用户名或密码为空", details: nil))
                                }
                            } catch let e {
                                completion(e)
                            }
                        })
                    } else {
                        completion(error)
                    }
                })
            } else {
                completion(error)
            }
        }
    }
    
    func stopVPN() {
        // 停止 VPN 连接
        if self.providerManager != nil {
            self.providerManager.connection.stopVPNTunnel()
            stage?("disconnected")
        }
    }
    
    func getTraffictStats() {
        // 获取流量统计信息
        if let stats = UserDefaults(suiteName: self.groupIdentifier!)?.string(forKey: "connectionUpdate") {
            stage?(stats)
        }
    }
}
