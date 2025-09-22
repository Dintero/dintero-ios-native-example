//
//  ContentView.swift
//  dintero-applepay-demo
//
//  Created by Sven Nicolai Viig on 22/09/2025.
//

import SwiftUI
import PassKit
import Foundation
import CryptoKit

let dinteroHostname = "checkout.dintero.com"
let dinteroTestSessionId = "<dintero-payment-session-id>"
let merchantIdentifier = "merchant.com.dintero.checkout"
let logNetwork: Bool = true

enum PaymentError: Error {
    case invalidURL
    case serverError
    case encodingError
    case invalidOperationsResponse
}

struct DinteroPspOperation: Codable {
    let rel: String
    let href: String
    let method: String
}

struct DinterPspOperationsResponse: Codable {
    let operations: [DinteroPspOperation]
}

struct DinteroSession: Codable {
    let id: String
    let account_id: String
    let order: Order
    let configuration: DinteroSessionConfiguration
    
    struct Order: Codable {
        let amount: Int
        let currency: String
        let vat_amount: Int?
        let vat: Double?
        let items: [Item]?
        
        struct Item: Codable {
            let amount: Int
            let id: String
            let line_id: String
            let description: String?
            let quantity: Int?
            let vat_amount: Int?
            let vat: Double?
        }
    }
}

struct DinteroSessionConfiguration: Codable {
    let merchant: DinteroSessionConfigurationMerchant
}

struct DinteroSessionConfigurationMerchant: Codable {
    let name: String
    let country: String
}

struct DinteroSessionAndOperations {
    let session: DinteroSession
    let operations: DinterPspOperationsResponse
}

struct EmptyBody: Encodable {}

func printHTTPRequest(request: URLRequest) {
    if(!logNetwork){
        return
    }
    let method = request.httpMethod ?? "GET"
    let urlString = request.url?.absoluteString ?? "<no url>"
    print("HTTP Request: \(method) \(urlString)")
    if let headers = request.allHTTPHeaderFields {
        print("--- Request Headers ---")
        for (key, value) in headers {
            print("\(key): \(value)")
        }
    }
    if let body = request.httpBody, !body.isEmpty {
        if let bodyString = String(data: body, encoding: .utf8) {
            print("--- Request Body ---\n\(bodyString)")
            print("---")
        } else {
            print("Body: <non-UTF8 data>")
        }
    }
}

func printHTTPResponse(response: HTTPURLResponse, data: Data) {
    if(!logNetwork){
        return
    }
    print("Response status code: \(response.statusCode)")
    print("--- Response Headers ---")
    for (key, value) in response.allHeaderFields {
        print("\(key): \(value)")
    }
    if let bodyString = String(data: data, encoding: .utf8) {
        print("--- Response body ---\n\(bodyString)")
        print("---")
    } else {
        print("Response body: <non-UTF8 data>")
    }
    print("\n")
}

func sendJSONRequest<T: Encodable, U: Decodable>(
    url: URL,
    method: String = "POST",
    body: T,
    headers: [String: String] = ["Content-Type": "application/json"],
    completion: @escaping (Result<U, Error>) -> Void
) {
    var request = URLRequest(url: url)
    request.httpMethod = method
    headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
    
    // Only encode body for non-GET methods
    if method.uppercased() != "GET" {
        do {
            let jsonData = try JSONEncoder().encode(body)
            request.httpBody = jsonData
        } catch {
            completion(.failure(error))
            return
        }
    }
    printHTTPRequest(request: request)
    
    URLSession.shared.dataTask(with: request) { data, response, error in
        if let error = error {
            completion(.failure(error))
            return
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            completion(.failure(NSError(domain: "NoHTTPResponse", code: 0)))
            return
        }
        guard let data = data else {
            completion(.failure(NSError(domain: "NoData", code: 0)))
            return
        }
        printHTTPResponse(response: httpResponse, data: data)
        let statusCode = httpResponse.statusCode
        
        if statusCode != 200 {
            completion(.failure(NSError(domain: "UnexpectedStatusCode", code: statusCode)))
            return
        }
        do {
            let decoded = try JSONDecoder().decode(U.self, from: data)
            completion(.success(decoded))
        } catch {
            // Print if decoding fails
            print("JSON decoding failed with error: \(error)")
            completion(.failure(error))
        }
    }.resume()
}

func operationsURL(sessionId: String) throws -> URL {
    guard var components = URLComponents(string: "https://checkout.test.dintero.com/v1/view/\(sessionId)/payments/dintero_psp.applepay") else {
        throw PaymentError.invalidURL
    }
    components.queryItems = [URLQueryItem(name: "force_new", value: "true")]
    guard let url = components.url else {
        throw PaymentError.invalidURL
    }
    return url
}

func sessionURL(sessionId: String) throws -> URL {
    guard let url = URL(string: "https://\(dinteroHostname)/v1/view/\(sessionId)/session") else {
        throw PaymentError.invalidURL
    }
    return url
}

func sessionPaymentURL(sessionId: String) throws -> URL {
    guard let url = URL(string: "https://\(dinteroHostname)/v1/sessions/\(sessionId)/pay") else {
        throw PaymentError.invalidURL
    }
    return url
}

func fetchSession(
    sessionId: String,
    completion: @escaping (Result<DinteroSession, Error>) -> Void
) {
    do {
        let url = try sessionURL(sessionId: sessionId)
        sendJSONRequest(
            url: url,
            method: "GET",
            body: EmptyBody(),
            headers: ["Accept": "application/json"],
            completion: completion
        )
    } catch {
        completion(.failure(error))
    }
}

func fetchSessionOperations(
    sessionId: String,
    completion: @escaping (Result<DinterPspOperationsResponse, Error>) -> Void
) {
    do {
        let url = try operationsURL(sessionId: sessionId)
        sendJSONRequest(
            url: url,
            method: "POST",
            body: EmptyBody(),
            headers: ["Accept": "application/json"],
            completion: completion
        )
    } catch {
        completion(.failure(error))
    }
}

func fetchSessionAndOperations(
    sessionId: String,
    completion: @escaping (Result<DinteroSessionAndOperations, Error>) -> Void
) {
    fetchSession(sessionId: sessionId) { result in
        switch result {
        case .success(let dinteroSession):
            fetchSessionOperations(sessionId: sessionId) { result in
                switch result {
                case .success(let dinteroOperations):
                    if(dinteroOperations.operations.isEmpty){
                        completion(.failure(PaymentError.invalidOperationsResponse))
                        return
                    }
                    
                    let combined = DinteroSessionAndOperations(
                        session: dinteroSession,
                        operations: dinteroOperations
                    )
                    completion(.success(combined))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        case .failure(let error):
            completion(.failure(error))
        }
    }
}

enum URLParsingError: Error {
    case invalidURL
    case missingAccessToken
}

func extractAccessToken(from href: String) throws -> String {
    guard let url = URL(string: href),
          let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
        throw URLParsingError.invalidURL
    }
    guard let token = components.queryItems?.first(where: { $0.name == "access_token" })?.value else {
        throw URLParsingError.missingAccessToken
    }
    return token
}

func urlWithoutQuery(from href: String) throws -> URL {
    guard var components = URLComponents(string: href) else { throw URLParsingError.invalidURL }
    components.query = nil
    components.queryItems = nil
    guard let url = components.url else { throw URLParsingError.invalidURL }
    return url
}

func generateUniqueReference() -> String {
    return UUID().uuidString
}

struct ApplePayTransaction: Codable {
    let payment: Payment
    
    struct Payment: Codable {
        let token: Token
        
        struct Token: Codable {
            let paymentData: PaymentData
            let paymentMethod: PaymentMethod
            let transactionIdentifier: String
        }
        
        struct PaymentData: Codable {
            let data: String
            let signature: String
            let header: Header
            let version: String
            
            struct Header: Codable {
                let publicKeyHash: String
                let ephemeralPublicKey: String
                let transactionId: String
            }
        }
        
        struct PaymentMethod: Codable {
            let displayName: String
            let network: String
            let type: String
        }
    }
}

struct DinteroApplePayTransactionResponse: Codable {
    let payment_id: String
    let transaction_id: String
    let type: String
}

extension PKPaymentMethodType {
    var stringValue: String {
        switch self {
        case .unknown: return "unknown"
        case .debit: return "debit"
        case .credit: return "credit"
        case .prepaid: return "prepaid"
        case .store: return "store"
        case .eMoney: return "eMoney"
        @unknown default: return "unknown"
        }
    }
}

struct DinteroSessionPayPayload: Codable {
    let payment_product_type: String
    let psp_transaction_id: String
}

struct DinteroSessionPayResponse: Codable {
    let success: Bool
    let redirect_url: String
}

func toApplePayTransaction(from payment: PKPayment) throws -> ApplePayTransaction {
    // Decode paymentData JSON
    let paymentData = try JSONDecoder().decode(
        ApplePayTransaction.Payment.PaymentData.self,
        from: payment.token.paymentData
    )
    let network: String = payment.token.paymentMethod.network?.rawValue ?? ""
    
    let method = ApplePayTransaction.Payment.PaymentMethod(
        displayName: payment.token.paymentMethod.displayName ?? "",
        network: network,
        type: payment.token.paymentMethod.type.stringValue
    )

    // Build token
    let token = ApplePayTransaction.Payment.Token(
        paymentData: paymentData,
        paymentMethod: method,
        transactionIdentifier: payment.token.transactionIdentifier
    )
    
    // Build payment
    let paymentStruct = ApplePayTransaction.Payment(
        token: token,
    )

    return ApplePayTransaction(payment: paymentStruct)
}

struct ApplePayTransactionPayload: Codable {
    let payment_data: String
    let reference: String
    
    init(payment: PKPayment, reference: String) throws {
        // Bulid paymentData
        let paymentData = try toApplePayTransaction(from: payment)
        // Make json string from paymentData
        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(paymentData)
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw NSError(domain: "EncodingError", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to encode JSON as UTF-8 string"])
        }
        self.payment_data = jsonString
        self.reference = reference
    }
}

func fetchApplePayTransaction(
    operations: [DinteroPspOperation],
    payment: PKPayment,
    completion: @escaping (Result<DinteroApplePayTransactionResponse, Error>) -> Void
) {
    do {
        guard let op = operations.first(where: { $0.rel == "submit-dintero-psp-applepay" }) else {
            completion(.failure(PaymentError.invalidOperationsResponse))
            return
        }
        let url = try urlWithoutQuery(from: op.href)
        let method = op.method
        let accessToken = try extractAccessToken(from: op.href)
        let payload = try ApplePayTransactionPayload(
            payment: payment,
            reference: generateUniqueReference()
        )
        sendJSONRequest(
            url: url,
            method: method,
            body: payload,
            headers: [
                "Content-Type": "application/json",
                "Accept": "application/json",
                "Authorization": accessToken
            ],
            completion: completion
        )
    } catch {
        completion(.failure(error))
    }
}

func fetchSessionPay(
    sessionId: String,
    pspTransactionId: String,
    completion: @escaping (Result<DinteroSessionPayResponse, Error>) -> Void
) {
    let payload = DinteroSessionPayPayload(
        payment_product_type: "dintero_psp.applepay",
        psp_transaction_id: pspTransactionId
    )
    guard let url = try? sessionPaymentURL(sessionId: sessionId) else {
        completion(.failure(NSError(domain: "InvalidURL", code: 0)))
        return
    }
    sendJSONRequest(
        url: url,
        body: payload,
        completion: completion
    )
}

struct ContentView: View {
    @State private var sessionId: String = dinteroTestSessionId
    @State private var paymentSuccess = false
    
    var body: some View {
        VStack {
            Text("Apple Pay Demo")
                .padding()
            
            if paymentSuccess {
                Text("Payment Successful!")
            } else {
               TextField("Dintero Session ID", text: $sessionId)
                 .textFieldStyle(RoundedBorderTextFieldStyle())
                 .padding()

                ApplePayButton(sessionId: sessionId) {
                    paymentSuccess = true
                }
                    .frame(width: 250, height: 50)
            }
        }
    }
}

func toCurrencyAmount (amount: Int, currency: String) -> NSDecimalNumber {
    // TODO: Account for other types of currencies (eg. YEN)
    return NSDecimalNumber(value: amount).dividing(by:NSDecimalNumber(value: 100))
}

func toPaymentRequest(dinteroSession: DinteroSession) -> PKPaymentRequest {
    let request = PKPaymentRequest()
    request.merchantIdentifier = merchantIdentifier
    request.supportedNetworks = [.visa, .masterCard]
    request.merchantCapabilities = .threeDSecure
    request.countryCode = dinteroSession.configuration.merchant.country
    request.currencyCode = dinteroSession.order.currency
    request.paymentSummaryItems = [
        PKPaymentSummaryItem(
            label: dinteroSession.configuration.merchant.name,
            amount: toCurrencyAmount(amount: dinteroSession.order.amount, currency: dinteroSession.order.currency)
        )
    ]
    return request
}

func topViewController(_ rootViewController: UIViewController?) -> UIViewController? {
    if let presented = rootViewController?.presentedViewController {
        return topViewController(presented)
    }
    if let nav = rootViewController as? UINavigationController {
        return topViewController(nav.visibleViewController)
    }
    if let tab = rootViewController as? UITabBarController {
        return topViewController(tab.selectedViewController)
    }
    return rootViewController
}

struct ApplePayButton: UIViewRepresentable {
    let sessionId: String
    let onPaymentSuccess: () -> Void
    
    func makeUIView(context: Context) -> PKPaymentButton {
        PKPaymentButton(paymentButtonType: .buy, paymentButtonStyle: .black)
    }
    
    func updateUIView(_ uiView: PKPaymentButton, context: Context) {
        uiView.addTarget(context.coordinator, action: #selector(Coordinator.paymentTapped), for: .touchUpInside)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(sessionId: sessionId, onPaymentSuccess: onPaymentSuccess)
    }
    
    class Coordinator: NSObject, PKPaymentAuthorizationViewControllerDelegate {
        let sessionId: String
        let onPaymentSuccess: () -> Void
        private var _sessionPayementResponse:DinteroSessionPayResponse? = nil
        private var _sesionAndOperations:DinteroSessionAndOperations? = nil
        
        init(sessionId: String, onPaymentSuccess: @escaping ()-> Void) {
            self.sessionId = sessionId
            self.onPaymentSuccess = onPaymentSuccess
        }
        
        @objc func paymentTapped() {
            fetchSessionAndOperations(sessionId: sessionId) { result in
                switch result {
                case .success(let dinteroSessionAndOperations):
                    self._sesionAndOperations = dinteroSessionAndOperations
                    let request = toPaymentRequest(dinteroSession: dinteroSessionAndOperations.session)
                    guard let controller = PKPaymentAuthorizationViewController(paymentRequest: request) else {
                        print("Failed to create PKPaymentAuthorizationViewController")
                        return
                    }
                    controller.delegate = self
                    DispatchQueue.main.async {
                        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                           let window = windowScene.windows.first,
                           let topVC = topViewController(window.rootViewController) {
                            topVC.present(controller, animated: true)
                        } else {
                            print("Failed to find top view controller")
                        }
                    }
                case .failure(let error): print(error)
                }
            }
        }
        
        func paymentAuthorizationViewControllerDidFinish(_ controller: PKPaymentAuthorizationViewController) {
            DispatchQueue.main.async {
                controller.dismiss(animated: true)
                if(self._sessionPayementResponse?.success == true) {
                    self.onPaymentSuccess()
                }
            }
        }
        
        func paymentAuthorizationViewController(
            _ controller: PKPaymentAuthorizationViewController,
            didAuthorizePayment payment: PKPayment,
            handler completion: @escaping (PKPaymentAuthorizationResult) -> Void
        ) {
            // Process payment
            if let sessionAndOperations = _sesionAndOperations {
                let ops = sessionAndOperations.operations
                fetchApplePayTransaction(operations: ops.operations, payment: payment) { pspResult in
                    switch pspResult {
                    case .success(let pspResponse):
                        fetchSessionPay(
                            sessionId: sessionAndOperations.session.id,
                            pspTransactionId: pspResponse.transaction_id
                        ) { checkoutResult in
                            switch checkoutResult {
                            case .success(let checkoutResponse):
                                if checkoutResponse.success {
                                    self._sessionPayementResponse = checkoutResponse
                                    DispatchQueue.main.async {
                                        completion(PKPaymentAuthorizationResult(status: .success, errors: nil))
                                    }
                                } else {
                                    print("Checkout-service payment not successful")
                                    DispatchQueue.main.async {
                                        completion(PKPaymentAuthorizationResult(status: .failure, errors: nil))
                                    }
                                }
                            case .failure(let error):
                                print("Checkout-service error: \(error)")
                                DispatchQueue.main.async {
                                    completion(PKPaymentAuthorizationResult(status: .failure, errors: [error]))
                                }
                            }
                        }
                    case .failure(let pspTransactionError):
                        print("PSP Transaction error: \(pspTransactionError)")
                        DispatchQueue.main.async {
                            completion(PKPaymentAuthorizationResult(status: .failure, errors: [pspTransactionError]))
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
