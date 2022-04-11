//
//  AnyRedirectComponentMock.swift
//  AdyenTests
//
//  Created by Mohamed Eldoheiri on 11/4/20.
//  Copyright © 2020 Adyen. All rights reserved.
//

@testable import AdyenActions
@testable import AdyenCard
import Foundation

final class AnyRedirectComponentMock: AnyRedirectComponent {
    
    let apiContext = APIContext(environment: Environment.test, clientKey: "local_DUMMYKEYFORTESTING")

    var adyenContext: AdyenContext {
        return .init(apiContext: apiContext)
    }

    var delegate: ActionComponentDelegate?

    var onHandle: ((_ action: RedirectAction) -> Void)?

    func handle(_ action: RedirectAction) {
        onHandle?(action)
    }
}
