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

Purchase a license at [https://fascure-hosting.com](https://fascure-hosting.com). After checkout, paste the key in **WHM → Fascure Node.js App**.

Basic is free for 3 months: 1 account and 1 application. In **WHM → Fascure Node.js App**, choose **Get free license**. The request uses this server's public IP. If that IP already has an active license, Basic or Standard, the same license is renewed for 3 months. If none is active, a new free Basic license is issued.

The license server at `https://plugin.fascure-hosting.com` must stay online. The plugin verifies the license key once a day, and it keeps working only while that check succeeds. The license server compares that connection's IP and the expiry date with the license. A different IP, an expired license, or a revoked license turns the plugin off.

| Plan | Accounts | Applications on each account |
| --- | --- | --- |
| Basic (free) | 1 | 1 |
| Standard | 10 | 3 |
| Enterprise | unlimited | unlimited |

Until a key is saved in **WHM → Fascure Node.js App**:

- WHM will not install Passenger or Node.js versions.
- Customers cannot create, edit, start, stop, delete, or build applications.

## Offer Node.js to customers

After the license key is saved:

1. In **WHM → Fascure Node.js App**, install Passenger if it is not already loaded.
2. Install the Node.js versions customers may select, such as `20` or `22`.
3. Choose one installed version as the default.

## Accounts in WHM

**WHM → Fascure Node.js App** lists every hosting account whose feature list allows the plugin. Each account can be given a CPU limit there. The number is a percentage of one CPU core: **100** is one core, and **0** removes the limit. On a server with 6 cores the highest useful value is 600. The limit applies to that account's Node.js and Next.js processes, not to the rest of the website.

The same page lists every application with its account, domain, folder, URL, and status. **Running** means the process is listening. **Idle** means it is enabled and Passenger will start it on the next visit. **Stopped** means it was turned off. The port shown is the internal `127.0.0.1` port for that running application. Each running application gets its own port.

## Where to put application files

Node.js and Next.js use the same place on the account. Upload the project into a folder under the account home, next to `public_html`. Do not upload the project into `public_html`.

`public_html` is only the website address. The plugin creates a URL folder there, such as `public_html/node-test/`, and leaves the application source in `apps/`. The folder name under `apps/` is the application root you type in cPanel. `apps/hello` is only the Node.js test. A Next.js site uses its own folder, such as `apps/my-site`.

For a cPanel user named `username`:

```text
/home/username/
├── apps/hello/              ← Node.js test project (startup file app.js)
│   ├── app.js
│   └── package.json
├── apps/my-site/            ← Next.js project (startup file server.js)
│   ├── server.js
│   ├── package.json
│   └── app/ or pages/
└── public_html/             ← normal website files stay here
    ├── node-test/           ← URL folder for the Node.js test; leave the source out of it
    └── my-site/             ← URL folder for Next.js; leave the source out of it
```

In **cPanel → File Manager**, open the home folder (the folder that contains `public_html`), then open `apps`. Over SFTP or FTP, `apps` is directly under the account home.

| | Node.js test | Next.js |
| --- | --- | --- |
| Upload to | `/home/username/apps/hello/` | `/home/username/apps/my-site/` |
| Application root in cPanel | `apps/hello` | `apps/my-site` |
| Startup file | `app.js` | `server.js` |
| After create | Run NPM Install, then Restart | Run NPM Install, then Run next build, then Restart |
| Leave empty | `public_html/node-test/` | `public_html/my-site/` |

## Run the test application

`examples/hello` in this repository is a small Node.js server. It listens on `process.env.PORT`, which Passenger sets.

1. Open **cPanel → Software → Fascure Node.js App**.
2. Create an application with these values:

| Field | Value |
| --- | --- |
| Application name | `hello` |
| Application type | Node.js |
| Node.js version | the installed version, such as `v22.23.3` |
| Application mode | Production |
| Application root | `apps/hello` |
| Domain | the account domain |
| Application URL | `/node-test` |
| Startup file | `app.js` |

3. If the folder is empty, leave **Create starter files** checked and click **Create**. To use the files from `examples/hello` instead, upload `app.js` and `package.json` into `/home/username/apps/hello/` before you click **Create**, and leave starter files unchecked.
4. Open the application card and click **Run NPM Install**.
5. Click **Restart**.
6. Open `https://your-domain.example/node-test/`. The page should show the Node.js version.

Click **Stop App** to take it offline. Click **Start App** to publish it again. **Delete** removes the application from the plugin. Check **Also delete application files** only when `/home/username/apps/hello/` should be removed too.

## Run a Next.js application

The files go in the same kind of folder as the Node.js test. Use a different name so the two projects stay separate. Do not copy `examples/hello` into the Next.js folder, and do not put the Next.js project in `public_html`.

1. Upload the Next.js project to `/home/username/apps/my-site/`.
2. Add `server.js` in that same folder. It must listen on `process.env.PORT` and on `127.0.0.1`. That port is internal. Passenger chooses it and Apache connects to it on the same server. Visitors use the website address, such as `https://your-domain.example/my-site/`, on ports 80 and 443. The `3000` value is used only when the file is started by hand without Passenger.

```js
const { createServer } = require('http');
const { parse } = require('url');
const next = require('next');

const port = parseInt(process.env.PORT, 10) || 3000;
const app = next({ dev: false, hostname: '127.0.0.1', port, dir: __dirname });
const handle = app.getRequestHandler();

app.prepare().then(() => {
  createServer((req, res) => {
    handle(req, res, parse(req.url, true));
  }).listen(port, '127.0.0.1');
});
```

3. Open **cPanel → Software → Fascure Node.js App** and create the application with these values:

| Field | Value |
| --- | --- |
| Application name | `my-site` |
| Application type | Next.js |
| Node.js version | the installed version, such as `v22.23.3` |
| Application mode | Production |
| Application root | `apps/my-site` |
| Domain | the account domain |
| Application URL | `/my-site` |
| Startup file | `server.js` |

4. Leave **Create starter files** unchecked when `package.json` is already in `apps/my-site`.
5. Open the application card and click **Run NPM Install**.
6. Click **Run next build**.
7. Click **Restart**.
8. Open `https://your-domain.example/my-site/`.

The URL folder `public_html/my-site/` is created by the plugin. It is not the place to upload `server.js`, `package.json`, or the `app` or `pages` directory.

## Uninstall

Installation copies the Fascure uninstaller to a fixed path. On the cPanel server, as root, from any directory:

```bash
bash /usr/local/nodeapps/bin/uninstall-FS-plugin.sh
```

To also delete the Node.js builds installed for the plugin:

```bash
bash /usr/local/nodeapps/bin/uninstall-FS-plugin.sh --remove-node
```

The uninstaller removes the WHM page, the cPanel page, the license check, and the Passenger configuration for plugin applications. It stops those applications from answering on the web.

It does not delete project files already uploaded to an account. Those stay in folders such as `/home/username/apps/`. Delete that folder from File Manager when the project itself should be removed. A normal website in `public_html` is not part of this plugin and is left as it is.

## What gets installed

- WHM page: **Fascure Node.js App**
- cPanel page: **Software → Fascure Node.js App**
- Node.js builds under `/opt/nodeapps/versions`
- Account applications recorded in the account home, `.nodeapps/apps.json`
- Apache Passenger configuration for each application, written for that account only
- Uninstaller: `/usr/local/nodeapps/bin/uninstall-FS-plugin.sh`

## Trademarks

Node.js is a trademark of the OpenJS Foundation. Next.js is a trademark of Vercel, Inc. cPanel and WHM are trademarks of WebPros International, LLC. Phusion Passenger is a trademark of Phusion Holding B.V.

Fascure Node.js App is an independent hosting plugin. It is not affiliated with, endorsed by, or sponsored by those companies. Their names are used only to say which software this plugin can run.
