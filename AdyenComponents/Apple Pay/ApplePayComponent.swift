//
// Copyright (c) 2022 Adyen N.V.
//
// This file is open source and available under the MIT license. See the LICENSE file for more info.
//

@_spi(AdyenInternal) import Adyen
import Foundation
import PassKit

/// A component that handles Apple Pay payments.
public class ApplePayComponent: NSObject, InstantPaymentComponentProtocol, FinalizableComponent {

    internal var applePayPayment: ApplePayPayment

    internal var state: State = .initial

    internal var viewControllerDidFinish: Bool = false

    internal let applePayPaymentMethod: ApplePayPaymentMethod

    internal let paymentController: PKPaymentAuthorizationController

    /// The context object for this component.
    @_spi(AdyenInternal)
    public let context: AdyenContext

    /// The Apple Pay payment method.
    public var paymentMethod: PaymentMethod { applePayPaymentMethod }

    /// The delegate of the component.
    public weak var delegate: PaymentComponentDelegate?

    /// The delegate changes of ApplePay payment state.
    public weak var applePayDelegate: ApplePayComponentDelegate?

    /// Initializes the component.
    /// - Warning: Do not dismiss this component.
    ///  First, call `didFinalize(with:completion:)` on error or success, then dismiss it.
    ///  Dismissal should occur within `completion` block.
    ///
    /// - Parameter paymentMethod: The Apple Pay payment method. Must include country code.
    /// - Parameter context: The context object for this component.
    /// - Parameter paymentRequest: The payment request
    /// - Throws: `ApplePayComponent.Error.userCannotMakePayment`.
    /// if user can't make payments on any of the payment request’s supported networks.
    /// - Throws: `ApplePayComponent.Error.deviceDoesNotSupportApplyPay` if the current device's hardware doesn't support ApplePay.
    /// - Throws: `ApplePayComponent.Error.userCannotMakePayment` if user can't make payments on any of the supported networks.
    public init(paymentMethod: ApplePayPaymentMethod,
                context: AdyenContext,
                paymentRequest: PKPaymentRequest) throws {
        guard Self.canMakePaymentWith(paymentRequest) else {
            throw Error.userCannotMakePayment
        }

        self.applePayPayment = try paymentRequest.getApplePayment()
        self.context = context
        self.paymentController = PKPaymentAuthorizationController(paymentRequest: paymentRequest)
        self.applePayPaymentMethod = paymentMethod
        super.init()

        paymentController.delegate = self
        state = .initial
    }
    
    /// Initializes the component.
    /// - Warning: Do not dismiss this component.
    ///  First, call `didFinalize(with:completion:)` on error or success, then dismiss it.
    ///  Dismissal should occur within `completion` block.
    ///
    /// - Parameter paymentMethod: The Apple Pay payment method. Must include country code.
    /// - Parameter context: The context object for this component.
    /// - Parameter configuration: Apple Pay component configuration
    /// - Throws: `ApplePayComponent.Error.userCannotMakePayment`.
    /// if user can't make payments on any of the payment request’s supported networks.
    /// - Throws: `ApplePayComponent.Error.deviceDoesNotSupportApplyPay` if the current device's hardware doesn't support ApplePay.
    /// - Throws: `ApplePayComponent.Error.userCannotMakePayment` if user can't make payments on any of the supported networks.
    public init(paymentMethod: ApplePayPaymentMethod,
                context: AdyenContext,
                configuration: Configuration) throws {
        guard PKPaymentAuthorizationViewController.canMakePayments() else {
            throw Error.deviceDoesNotSupportApplyPay
        }
        let supportedNetworks = paymentMethod.supportedNetworks
        guard configuration.allowOnboarding || Self.canMakePaymentWith(supportedNetworks) else {
            throw Error.userCannotMakePayment
        }

        let paymentRequest = configuration.createPaymentRequest(supportedNetworks: supportedNetworks)
        self.paymentController = PKPaymentAuthorizationController(paymentRequest: paymentRequest)
        self.context = context
        self.applePayPaymentMethod = paymentMethod
        self.applePayPayment = configuration.applePayPayment
        super.init()

        paymentController.delegate = self
        state = .initial
    }

    public func initiatePayment() {
        paymentController.present { result in
            guard !result else { return }
            print("Failed to instantiate PKPaymentAuthorizationController because of unknown error")
        }
    }

    public func didFinalize(with success: Bool, completion: (() -> Void)?) {
        if case let .paid(paymentAuthorizationCompletion) = state {
            state = .finalized(completion)
            let status: PKPaymentAuthorizationStatus = success ? .success : .failure
            paymentAuthorizationCompletion(PKPaymentAuthorizationResult(status: status, errors: nil))
        } else {
            paymentController.dismiss {
                DispatchQueue.main.async { completion?() }
            }
            state = .initial
        }
    }

    internal func update(payment: Payment?) throws {
        guard let payment = payment else {
            throw ApplePayComponent.Error.negativeGrandTotal
        }

        applePayPayment = try ApplePayPayment(payment: payment, brand: applePayPayment.brand)
    }

    // MARK: - Private

    private static func canMakePaymentWith(_ networks: [PKPaymentNetwork]) -> Bool {
        PKPaymentAuthorizationViewController.canMakePayments(usingNetworks: networks)
    }

    private static func canMakePaymentWith(_ paymentRequest: PKPaymentRequest) -> Bool {
        PKPaymentAuthorizationViewController.canMakePayments(usingNetworks: paymentRequest.supportedNetworks,
                                                             capabilities: paymentRequest.merchantCapabilities)
    }
}

extension ApplePayComponent {

    internal enum State {
        case initial
        case paid((PKPaymentAuthorizationResult) -> Void)
        case finalized((() -> Void)?)
    }

}

@_spi(AdyenInternal)
extension ApplePayComponent: TrackableComponent {}

@_spi(AdyenInternal)
extension ApplePayComponent: ViewControllerDelegate {
    public func viewDidLoad(viewController: UIViewController) { /* Empty implementation */ }

    public func viewDidAppear(viewController: UIViewController) { /* Empty implementation */ }

    public func viewWillAppear(viewController: UIViewController) {
        sendTelemetryEvent()
    }
}

extension PKPaymentRequest {
    func getApplePayment() throws -> ApplePayPayment {
        try ApplePayPayment(countryCode: countryCode,
                            currencyCode: currencyCode,
                            summaryItems: paymentSummaryItems)
    }
}
