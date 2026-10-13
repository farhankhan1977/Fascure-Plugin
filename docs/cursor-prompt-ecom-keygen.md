# Prompt for the e-commerce Cursor session

Paste the following into the Cursor chat for the store application.

---

Add Fascure Node.js App license sales to this store. Do not build a cPanel plugin and do not generate license keys locally. The license server at https://plugin.fascure-hosting.com issues the keys.

After a paid order is complete, or when a free Basic order is placed, call the license server and save the returned license key on the order. Show it in the client area and the order email.

## Products

- Basic, price 0. The license server allows 1 hosting account and 1 Node.js application.
- Standard. The license server allows 10 hosting accounts and 3 Node.js applications on each account.
- Enterprise. The license server allows unlimited accounts and applications.

Checkout must collect the customer's cPanel server public IP. Validate it with a normal IP check. One license works only for that IP. Store the IP on the order. If the product is a subscription, send the period length in days. Otherwise send 365, or the store's own billing period.

## API

The store server calls this with a bearer token. Keep the token in the server environment as FASCURE_LICENSE_API_TOKEN. Never send it to the browser and never commit it.

POST https://plugin.fascure-hosting.com/api/manage.php
Authorization: Bearer <token>
Content-Type: application/json

New license:

{"action":"generate","plan":"standard","ip":"46.151.210.123","days":365,"note":"order 1001"}

Renew the same key at the next billing date. Send the new IP if the customer moved servers:

{"action":"renew","license_key":"FSCP-ABCD-EFGH-JKLM-NPQR","ip":"46.151.210.123","days":365}

plan is basic, standard, or enterprise. days is 1 through 3650. expires_at in `YYYY-MM-DD HH:MM:SS` can be sent instead of days.

A successful generate response includes license_key, plan, ip, and expires_at. Save license_key on the order. Show the customer this instruction: in WHM open Fascure Node.js App, paste the key, and choose Save license key.

If the API returns 400 or 401, mark the license as not delivered and show the message to the admin. Do not invent a key.

The token's generation limits are managed in the license server admin UI. This store only needs to call the API.
