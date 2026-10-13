# Fascure Node.js App

cPanel and WHM plugin for per-account Node.js and Next.js applications. Each application can use its own Node.js version, application root, URL, startup file, and environment variables. Applications run under Phusion Passenger as the cPanel user.

The plugin stays limited until a license key for that server is entered in WHM.

Repository: https://github.com/farhankhan1977/Fascure-Plugin

## Requirements

- cPanel & WHM on AlmaLinux 8 or another cPanel-supported Linux server
- root access for installation
- EasyApache 4
- Outbound HTTPS access to `nodejs.org` for Node.js downloads and to GitHub for this installer

## Install

On the cPanel server, as root:

```bash
curl -fsSL https://raw.githubusercontent.com/farhankhan1977/Fascure-Plugin/main/cpanel-install.sh | bash
```

From a clone of this repository:

```bash
bash cpanel-install.sh
```

The installer copies the plugin into cPanel, registers **Fascure Node.js App** in WHM and in the Jupiter theme, and allows each hosting account to publish its own Apache Passenger configuration.

## License

Licenses are issued by the Fascure license server and checked once a day. The application is in `license-server/` and is meant to run at `https://plugin.fascure-hosting.com`. See `license-server/README.md`.

A license is bound to the public IP of the cPanel server. The plugin sends its key to `/api/verify.php`. The license server compares that connection's IP and the expiry date with the license. A different IP, an expired license, or a revoked license turns the plugin off.

| Plan | Accounts | Applications on each account |
| --- | --- | --- |
| Basic | 1 | 1 |
| Standard | 10 | 3 |
| Enterprise | unlimited | unlimited |

Until a key is saved in **WHM → Fascure Node.js App**:

- WHM will not install Passenger or Node.js versions.
- Customers cannot create, edit, start, stop, delete, or build applications.

The daily check is `/etc/cron.daily/nodeapps-license`. Opening the WHM page also checks when the last successful check is older than 24 hours. If the license server cannot be reached, the last successful check is kept for one extra day. When the license server reports the key expired, revoked, unknown, or assigned to another IP, every running Node.js and Next.js application is stopped.

## Offer Node.js to customers

After the license key is saved:

1. In **WHM → Fascure Node.js App**, install Passenger if it is not already loaded.
2. Install the Node.js versions customers may select, such as `20` or `22`.
3. Choose one installed version as the default.

## Customer application

The customer opens **cPanel → Software → Fascure Node.js App** and creates an application:

| Field | Example |
| --- | --- |
| Application name | `hello` |
| Application type | Node.js or Next.js |
| Node.js version | `v22` |
| Application root | `apps/hello` |
| Application URL | `unisocia.com` `/node-test` |
| Startup file | `app.js` |

The application must listen on `process.env.PORT`. For Next.js, use a custom `server.js` that listens on that port, then run **NPM Install** and **Run next build**.

## Test application

`examples/hello` is a small Node.js server. Place `app.js` and `package.json` in the application root, then create the application with startup file `app.js`.

## What gets installed

- WHM page: **Fascure Node.js App**
- cPanel page: **Software → Fascure Node.js App**
- Node.js builds under `/opt/nodeapps/versions`
- Account applications recorded in the account home, `.nodeapps/apps.json`
- Apache Passenger configuration for each application, written for that account only

## Trademarks

Node.js is a trademark of the OpenJS Foundation. Next.js is a trademark of Vercel, Inc. cPanel and WHM are trademarks of WebPros International, LLC. Phusion Passenger is a trademark of Phusion Holding B.V.

Fascure Node.js App is an independent hosting plugin. It is not affiliated with, endorsed by, or sponsored by those companies. Their names are used only to say which software this plugin can run.
