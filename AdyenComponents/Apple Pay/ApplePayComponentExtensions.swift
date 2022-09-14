//
// Copyright (c) 2022 Adyen N.V.
//
// This file is open source and available under the MIT license. See the LICENSE file for more info.
//

@_spi(AdyenInternal) import Adyen
import Foundation
import PassKit

@_spi(AdyenInternal)
extension ApplePayComponent: PKPaymentAuthorizationControllerDelegate {

    public func paymentAuthorizationControllerDidFinish(_ controller: PKPaymentAuthorizationController) {
        switch state {
        case let .finalized(completion):
            completion?()
        default:
            delegate?.didFail(with: ComponentError.cancelled, from: self)
        }
    }
    
    public func paymentAuthorizationController(_ controller: PKPaymentAuthorizationController,
                                               didAuthorizePayment payment: PKPayment,
                                               handler completion: @escaping (PKPaymentAuthorizationResult) -> Void) {
        guard payment.token.paymentData.isEmpty == false else {
            completion(PKPaymentAuthorizationResult(status: .failure, errors: [Error.invalidToken]))
            state = .finalized { [weak self] in
                guard let self = self else { return }
                self.delegate?.didFail(with: Error.invalidToken, from: self)
            }
            return
        }

        state = .paid(completion)
        let token = payment.token.paymentData.base64EncodedString()
        let network = payment.token.paymentMethod.network?.rawValue ?? ""
        let details = ApplePayDetails(paymentMethod: applePayPaymentMethod,
                                      token: token,
                                      network: network,
                                      billingContact: payment.billingContact,
                                      shippingContact: payment.shippingContact,
                                      shippingMethod: payment.shippingMethod)
        submit(data: PaymentComponentData(paymentMethodDetails: details, amount: applePayPayment.amount, order: order))
    }

    public func paymentAuthorizationController(
        _ controller: PKPaymentAuthorizationController,
        didSelectShippingContact contact: PKContact,
        handler completion: @escaping (PKPaymentRequestShippingContactUpdate) -> Void
    ) {
        guard let applePayDelegate = applePayDelegate else {
            return completion(.init(paymentSummaryItems: applePayPayment.summaryItems))
        }

        applePayDelegate.didUpdate(contact: contact,
                                   for: applePayPayment) { [weak self] result in
            guard let self = self else { return }
            self.updateApplePayPayment(result)
            completion(result)
        }
    }

    public func paymentAuthorizationController(_ controller: PKPaymentAuthorizationController,
                                               didSelectShippingMethod shippingMethod: PKShippingMethod,
                                               handler completion: @escaping (PKPaymentRequestShippingMethodUpdate) -> Void) {
        guard let applePayDelegate = applePayDelegate else {
            return completion(.init(paymentSummaryItems: applePayPayment.summaryItems))
        }

        applePayDelegate.didUpdate(shippingMethod: shippingMethod,
                                   for: applePayPayment) { [weak self] result in
            guard let self = self else { return }
            self.updateApplePayPayment(result)
            completion(result)
        }
    }

    @available(iOS 15.0, *)
    public func paymentAuthorizationController(_ controller: PKPaymentAuthorizationController,
                                               didChangeCouponCode couponCode: String,
                                               handler completion: @escaping (PKPaymentRequestCouponCodeUpdate) -> Void) {
        guard let applePayDelegate = applePayDelegate else {
            return completion(.init(paymentSummaryItems: applePayPayment.summaryItems))
        }

        applePayDelegate.didUpdate(couponCode: couponCode,
                                   for: applePayPayment) { [weak self] result in
            guard let self = self else { return }
            self.updateApplePayPayment(result)
            completion(result)
        }
    }

    private func updateApplePayPayment<T: PKPaymentRequestUpdate>(_ result: T) {
        if result.status == .success, result.paymentSummaryItems.count > 0 {
            do {
                applePayPayment = try applePayPayment.replacing(summaryItems: result.paymentSummaryItems)
            } catch {
                delegate?.didFail(with: error, from: self)
            }
        }
    }

}
