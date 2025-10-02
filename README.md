# dintero-ios-native-example

Native iOS app with payment using Dintero.

## Apple pay
See [Apple Pay native payment documentation](https://docs.dintero.com/docs/checkout/apple-pay/apple-pay-native-app).

The application takes an existing session for in-app payments.

This example app shows how to:
  - Get session payment details given a Dintero payment session ID
  - Get session payment operations
  - Show native Apple Pay button
  - Open Apple Pay payment view
  - Submit payment data to the Dintero PSP
  - Complete session payment
  - Show payment result

## Creating a payment session for apple pay

Sample session request body, not that the `return_url` must
match the app url namespace, and that `initial_recipient=merchant`
must be set if the link in the session payment response should
be followed.


```json
{
  "url": {
    "return_url": "dinterodemo://redirect?initial_recipient=merchant",
    "callback_url": "https://<your-backend-callback-handler>"
  },
  "order": {
    "amount": 20100,
    "currency": "NOK",
    "merchant_reference": "<unique-reference>",
    "items": [
      {
        "id": "<item-id>",
        "line_id": "<unique-id-per-line>",
        "description": "Item to be paid for",
        "amount": 20100,
        "quantity": 1,
        "vat_amount": 4020,
        "vat": 25
      }
    ]
  },
  "configuration": {
    "channel": "in_app",
    "dintero_psp": {
      "applepay": {
        "enabled": true
      }
    }
  },
  "expires_at": "<ISO-timestamp>"
}
```

## Setting up Apple Pay in your Apple developer account

1. Create a merchantID in your apple developer account
2. Open the merchantID details page
3. Obtain a .csr file (certifiacate request) from dintero by email to integration@dintero.com
4. Press the "Create Certificate" button
5. Upload the .csr file received by dintero
6. Download the certificate
7. Send the certificate to integration@dintero.com so we can verify your payments
8. Open the certificate and ensure that it is added to the Keychain Access on your delveoper machine
9. In xcode app project settings, press the Signing and Capablities tab
10. Press the "+ Capability" button and select Apple Pay
11. Select the merchantID configured in step 1
