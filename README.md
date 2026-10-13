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

Licenses are checked once a day with the license server at `https://plugin.fascure-hosting.com`. See `license-server/README.md`.

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

## Where to put application files

Upload the Node.js or Next.js project into the account home directory. Do not upload the project into `public_html`. `public_html` is only the website address. The plugin keeps the application files beside it and attaches a URL such as `/node-test`.

For a cPanel user named `username`, the test application lives here:

```text
/home/username/apps/hello/app.js
/home/username/apps/hello/package.json
```

In **cPanel → File Manager**, open the home folder (the folder that contains `public_html`), then open `apps/hello`. The same folder over SFTP or FTP is `apps/hello` directly under the account home.

```text
/home/username/
├── apps/hello/              ← upload the Node.js project here
│   ├── app.js
│   └── package.json
└── public_html/             ← normal website files stay here
    └── node-test/           ← URL folder created by the plugin; leave the app source out of it
```

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

1. Upload the Next.js project to an application root such as `/home/username/apps/my-site/`.
2. Add a `server.js` that listens on `process.env.PORT`.
3. Create the application with type **Next.js**, root `apps/my-site`, the URL you want, and startup file `server.js`.
4. Click **Run NPM Install**, then **Run next build**, then **Restart**.
5. Open the application URL.

## Uninstall

On the cPanel server, as root, from a checkout of this repository:

```bash
bash uninstall-plugin.sh
```

To also delete the Node.js builds installed for the plugin:

```bash
bash uninstall-plugin.sh --remove-node
```

The uninstaller removes the WHM page, the cPanel page, the license check, and the Passenger configuration for plugin applications. It stops those applications from answering on the web.

It does not delete project files already uploaded to an account. Those stay in folders such as `/home/username/apps/`. Delete that folder from File Manager when the project itself should be removed. A normal website in `public_html` is not part of this plugin and is left as it is.

## What gets installed

- WHM page: **Fascure Node.js App**
- cPanel page: **Software → Fascure Node.js App**
- Node.js builds under `/opt/nodeapps/versions`
- Account applications recorded in the account home, `.nodeapps/apps.json`
- Apache Passenger configuration for each application, written for that account only
- Uninstaller: `uninstall-plugin.sh`

## Trademarks

Node.js is a trademark of the OpenJS Foundation. Next.js is a trademark of Vercel, Inc. cPanel and WHM are trademarks of WebPros International, LLC. Phusion Passenger is a trademark of Phusion Holding B.V.

Fascure Node.js App is an independent hosting plugin. It is not affiliated with, endorsed by, or sponsored by those companies. Their names are used only to say which software this plugin can run.
