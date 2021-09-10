import Flutter
import UIKit
import PassKit

@available(iOS 10.0, *)
public class SwiftFlutterPayPlugin: NSObject, FlutterPlugin {
    
    let paymentAuthorizationController = PKPaymentAuthorizationController()
    
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "flutter_pay", binaryMessenger: registrar.messenger())
    let instance = SwiftFlutterPayPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

    private var flutterResult: FlutterResult?
    
  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if(call.method == "canMakePayments") {
        canMakePayment(result: result)
    } else if(call.method == "canMakePaymentsWithActiveCard") {
        canMakePaymentsWithActiveCard(arguments: call.arguments, result: result)
    } else if(call.method == "requestPayment") {
        requestPayment(arguments: call.arguments, result: result)
    } else if(call.method == "switchEnvironment") {}
    
  }
    
    func canMakePayment(arguments: Any? = nil, result: @escaping FlutterResult) {
        let canMakePayment = PKPaymentAuthorizationController.canMakePayments()
        result(canMakePayment)
    }

    func canMakePaymentsWithActiveCard(arguments: Any? = nil, result: @escaping FlutterResult) {
        guard let params = arguments as? [String: Any],
            let paymentNetworks = params["paymentNetworks"] as? [String] else {
                result(FlutterError(code: "invalidParameters", message: "Invalid parameters", details: nil))
                return;
        }
        let pkPaymentNetworks: [PKPaymentNetwork] = paymentNetworks.compactMap({ PaymentNetworkHelper.decodePaymentNetwork($0) })
        let canMakePayments = PKPaymentAuthorizationController.canMakePayments(usingNetworks: pkPaymentNetworks)
        result(canMakePayments)
    }
    
    func requestPayment(arguments: Any? = nil, result: @escaping FlutterResult) {
        guard let params = arguments as? [String: Any],
                let merchantID = params["merchantIdentifier"] as? String,
                let currency = params["currencyCode"] as? String,
                let countryCode = params["countryCode"] as? String,
                let allowedPaymentNetworks = params["allowedPaymentNetworks"] as? [String],
                let items = params["items"] as? [[String: String]] else {
                    result(FlutterError(code: "invalidParameters", message: "Invalid parameters", details: nil))
                    return
        }
        
        var paymentItems = [PKPaymentSummaryItem]()
        items.forEach { item in
            let itemTitle = item["name"]
            let itemPrice = item["price"]
            let itemDecimalPrice = NSDecimalNumber(string: itemPrice)
            let item = PKPaymentSummaryItem(label: itemTitle ?? "", amount: itemDecimalPrice)
            paymentItems.append(item)
        }
        
        let paymentNetworks = allowedPaymentNetworks.count > 0 ? allowedPaymentNetworks.compactMap { PaymentNetworkHelper.decodePaymentNetwork($0) } : PKPaymentRequest.availableNetworks()
        
        let paymentRequest = PKPaymentRequest()
        paymentRequest.paymentSummaryItems = paymentItems
        
        paymentRequest.merchantIdentifier = merchantID
        paymentRequest.merchantCapabilities = .capability3DS
        paymentRequest.countryCode = countryCode
        paymentRequest.currencyCode = currency
        paymentRequest.supportedNetworks = paymentNetworks
        
        let paymentController = PKPaymentAuthorizationController(paymentRequest: paymentRequest)
        paymentController.delegate = self
        self.flutterResult = result
        paymentController.present(completion: nil)
    }
    
    private func paymentResult(pkPayment: PKPayment?) {
        if let result = flutterResult {
            if let payment = pkPayment {
                let paymentDataDictionary: [AnyHashable: Any]? = try? JSONSerialization.jsonObject(with: payment.token.paymentData, options: .mutableContainers) as! [AnyHashable : Any]

                var paymentType: String = "debit"
                var paymentMethodDictionary: [AnyHashable: Any] = ["network": "", "type": paymentType, "displayName": ""]
                paymentMethodDictionary = ["network": payment.token.paymentMethod.network ?? "", "type": paymentType, "displayName": payment.token.paymentMethod.displayName ?? ""]

                switch payment.token.paymentMethod.type {
                    case .debit:
                        paymentType = "debit"
                    case .credit:
                        paymentType = "credit"
                    case .store:
                        paymentType = "store"
                    case .prepaid:
                        paymentType = "prepaid"
                    default:
                        paymentType = "unknown"
                }

                let cryptogramDictionary: [AnyHashable: Any] = ["paymentData": paymentDataDictionary ?? "", "transactionIdentifier": payment.token.transactionIdentifier, "paymentMethod": paymentMethodDictionary]

                let cardCryptogramPacketDictionary: [AnyHashable: Any] = cryptogramDictionary
                let cardCryptogramPacketData: Data? = try? JSONSerialization.data(withJSONObject: cardCryptogramPacketDictionary, options: [])

                let token = String(data: cardCryptogramPacketData!, encoding: .utf8)
                result(["token": token])
            } else {
                result(FlutterError(code: "userCancelledError", message: "User cancelled the payment", details: nil))
            }
            flutterResult = nil
        }
    }
}

@available(iOS 10.0, *)
extension SwiftFlutterPayPlugin: PKPaymentAuthorizationControllerDelegate {
    public func paymentAuthorizationControllerDidFinish(_ controller: PKPaymentAuthorizationController) {
        paymentResult(pkPayment: nil)
        controller.dismiss(completion: nil)
    }
    
    @available(iOS 11.0, *)
    public func paymentAuthorizationController(_ controller: PKPaymentAuthorizationController, didAuthorizePayment payment: PKPayment, handler completion: @escaping (PKPaymentAuthorizationResult) ->  Void) {
        paymentResult(pkPayment: payment)
        completion(PKPaymentAuthorizationResult(status: .success, errors: nil))
    }
}
