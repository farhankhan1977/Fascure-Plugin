# Fascure license server

PHP and MySQL application for `plugin.fascure-hosting.com`. It checks Fascure Node.js App licenses by server IP, and it issues or renews licenses for the store.

## Install

1. Create an empty MySQL database and user.
2. Upload this folder so it is the document root of `plugin.fascure-hosting.com`.
3. Open `https://plugin.fascure-hosting.com/install.php`.
4. Enter the database and the admin username and password.
5. Delete `install.php`.
6. Sign in at `https://plugin.fascure-hosting.com/admin/login.php`.

Use HTTPS. The cPanel plugin refuses a license when it cannot verify the certificate.

## What a license allows

| Plan | Accounts | Applications on each account |
| --- | --- | --- |
| Basic | 1 | 1 |
| Standard | 10 | 3 |
| Enterprise | unlimited | unlimited |

Each license is assigned to one public IP, the same way a cPanel license is. The plugin calls the verifier once a day. The IP that connects must be the IP stored on the license. Expiry, a revoked license, or a different IP turns the plugin off.

## APIs

Verify, used by the plugin. No token. The source IP is the license IP.

`POST /api/verify.php`

```json
{"license_key":"FSCP-ABCD-EFGH-JKLM-NPQR"}
```

Generate or renew, used by the store. Send `Authorization: Bearer <token>`.

`POST /api/manage.php`

```json
{"action":"generate","plan":"standard","ip":"46.151.210.123","days":365}
```

```json
{"action":"renew","license_key":"FSCP-ABCD-EFGH-JKLM-NPQR","ip":"46.151.210.123","days":365}
```

`expires_at` (`YYYY-MM-DD HH:MM:SS`) can be sent instead of `days`.

Free Basic license, used by the WHM button. No token. The license is issued to the public IP that connects. It allows 1 account and 1 application for 3 months. The same server can renew it during the last 14 days, or after it expires. A click earlier than that returns the current key and does not extend it. An IP that already has an active paid license is refused.

`POST /api/free.php`

```json
{}
```

On a server that is already installed, upload `api/free.php` and `lib/licenses.php`. Do not run `install.php` again.

Create the bearer token in **API tokens**. A token has a total generation cap and a separate cap for Basic, Standard, and Enterprise. A plan cap of 0 means that plan cannot be issued. Each successful generate or renew counts against both caps.

The admin pages can also create, renew, and revoke licenses without an API token.
