# Prompt for the e-commerce Cursor session

Paste the following into the Cursor chat for the store application.

---

Add Fascure Node.js App license keys to this store. The store already sells products in a WHMCS-style flow. After a paid order is complete, or when a free Basic order is placed, generate one license key and show it in the client area and the order email. Do not build a cPanel plugin. Only add key generation and delivery on this e-commerce server.

## Products

Create or map three products:

- Basic, price 0. Limits: 1 hosting account, 1 Node.js application on that account.
- Standard. Limits: 10 hosting accounts, 3 Node.js applications on each account.
- Enterprise. Limits: unlimited hosting accounts and unlimited applications. Encode unlimited as the number 0.

Checkout must collect the customer's cPanel server hostname, such as `ns10.example.com`. Reject hostnames that are not letters, digits, dots, and hyphens. One purchased key works only on that hostname. Store the hostname on the order.

If the product is a subscription, set `exp` to the subscription period end as a unix timestamp. Otherwise set `exp` to 0, which means the key does not expire.

## Secrets

Read these from the server environment. Never commit them and never send them to the browser.

- `FASCURE_LICENSE_PRIVATE_KEY`: absolute path to the RSA private PEM used to sign keys. The operator will place this file on the store server. Do not generate a new keypair. A new keypair would not match the plugin.
- AES key hex: `bbc4b8e19112ed6c354b2250745cf7b989b7103b3c01bf79c0b703133707c9cc`
- HMAC key hex: `4b2cd60a6d92c6b333fe4e60c5b3551e452d5573a49579439f9cd4d424496a6e`

The AES and HMAC values are decryption material already shipped in the plugin. The private key is what stops a customer from making their own Enterprise key. If the private key file is missing, fail the order with a clear admin error and do not mark the license as delivered.

## Key format

Build this JSON with the fields in this order and no extra whitespace:

`{"product":"fascure-nodeapps","plan":"standard","host":"hostname","tenants":10,"apps":3,"exp":0,"id":"16hexchars"}`

`plan` is `basic`, `standard`, or `enterprise`. `tenants` and `apps` must be exactly the numbers for that plan. `id` is a random 8-byte hex string, unique per key.

Encrypt and sign with OpenSSL:

1. AES-256-CBC encrypt the JSON with the AES hex key, a random 16-byte IV, and `-nosalt`. Do not prefix the ciphertext with `Salted__`.
2. HMAC-SHA256 the raw IV bytes followed by the raw ciphertext, using the HMAC hex key. The MAC is 32 bytes.
3. Build the blob as raw IV (16 bytes) + raw MAC (32 bytes) + raw ciphertext.
4. RSA-SHA256 sign that blob with the private PEM (`openssl dgst -sha256 -sign`).
5. Return one line: `FSC2.` + base64url(blob) + `.` + base64url(signature).

base64url means standard base64 with `+` replaced by `-`, `/` replaced by `_`, and `=` padding removed.

Save the resulting string on the order. Show it once in the client area with the hostname and plan name, and include a short instruction: in WHM open Fascure Node.js App, paste the key, and choose Save license key.

Do not put the plan limits in a separate unsigned field that the plugin would trust. The plugin decrypts this key and refuses limits that do not match the plan name.

## Check

Add an admin-only action that generates a Basic key for a hostname you type and prints the FSC2 string. Confirm the string starts with `FSC2.` and contains exactly one more dot. Do not log the private key or the AES and HMAC secrets.
