# Offline Installation of XWiki (Tomcat + PostgreSQL)

## Workflow

**On the internet-connected machine:**

```
./01-download-online.sh
```

Downloads JRE, Tomcat, the XWiki WAR, the **XIP package** (offline extension
repository for the Standard Flavor), and the PostgreSQL JDBC driver into
`~/temp-xwiki-offline`. Also copies `00-config.sh` into that directory. The
directory is created if missing but never wiped - existing files are kept,
only re-downloaded ones are overwritten.

Then transfer `~/temp-xwiki-offline` **and** the scripts `00`-`05` to the
offline machine, e.g. via USB.

**On the offline machine (Debian):**

0. Install and start PostgreSQL (see your note above -
   `apt install postgresql postgresql-contrib`,
   `systemctl enable --now postgresql`). This only works if the Debian
   packages are available locally (an official repo mirror, a local apt
   proxy, etc.) - this is not covered by these scripts.
1. `sudo ./02-install-offline.sh` - extracts the JRE into `/opt/xwiki/jre`
   and Tomcat into `/opt/xwiki/tomcat`, creates the service user `xwiki`,
   configures Tomcat's HTTP connector for `HTTP_PORT` (see
   below), extracts the XWiki WAR into `/opt/xwiki/tomcat/webapps/xwiki`, copies
   the JDBC driver, creates the "permanent directory" `/var/lib/xwiki`,
   extracts the **XIP package** into `/var/lib/xwiki/extension/repository`
   (so the Standard Flavor can be installed without internet access),
   writes `setenv.sh`.
2. `sudo ./03-setup-database.sh` - creates the DB role and database in
   PostgreSQL. Requests the password interactively (never stored).
3. `sudo ./04-configure-xwiki.sh` - writes `WEB-INF/hibernate.cfg.xml` for
   PostgreSQL (mapping entries are carried over from the original), sets
   the permanent directory in `xwiki.properties`, and disables remote
   extension repositories (`extension.repositories=`) so XWiki doesn't try
   to reach `nexus.xwiki.org` at runtime. Requests the DB password again.
4. `sudo ./05-install-systemd-service.sh` - sets up the systemd service
   `xwiki-tomcat.service`, enables and starts it. If `HTTP_PORT` is a
   privileged port (e.g. `80`), the unit is granted
   `CAP_NET_BIND_SERVICE` so Tomcat can bind it while still running as the
   unprivileged `xwiki` user (no need to run the whole service as root).

Afterwards, XWiki should be reachable at `http://<host>:<HTTP_PORT>/xwiki`
(`http://<host>:8080/xwiki` by default), where it will start the
usual first-time setup wizard (Distribution Wizard). It will find the
Standard Flavor and its extensions locally (from the XIP package) instead
of downloading them, and let you create the admin account.

## Changing the HTTP port

`HTTP_PORT` in `00-config.sh` defaults to `8080` (the Tomcat default). To
use port `80` instead (or any other port), either edit `00-config.sh` or
override it for a single run, e.g.:

```
HTTP_PORT=80 sudo -E ./02-install-offline.sh
HTTP_PORT=80 sudo -E ./05-install-systemd-service.sh
```

(`sudo -E` preserves the environment variable through `sudo`.) Ports below
1024 (like `80`) are privileged; `05-install-systemd-service.sh`
automatically grants the service `CAP_NET_BIND_SERVICE` via systemd in that
case, so Tomcat can still run as the unprivileged `xwiki` user. If you
change the port after already having run `02`/`05` once, just re-run both
scripts - `02-install-offline.sh` does a clean reinstall of `${INSTALL_DIR}`,
and `05` overwrites the systemd unit.

## Important notes

- **Do not share real passwords/customer data with Claude or in chat
  tools.** That's why these scripts deliberately request database passwords
  interactively via `read -s` instead of accepting them as plaintext
  parameters.
- All paths/versions/usernames live centrally in `00-config.sh` - adjust
  there if, for example, a different XWiki or Tomcat version is needed
  (then also check the URLs in `01-download-online.sh`).
- **The XIP package version must exactly match the XWiki (WAR) version.**
  Both are derived from `XWIKI_VERSION` in `00-config.sh`, so if you bump
  one, the other updates automatically - just make sure a matching XIP
  actually exists for that version (check
  `https://nexus.xwiki.org/nexus/content/repositories/releases/org/xwiki/platform/xwiki-platform-distribution-flavor-xip/`).
- `04-configure-xwiki.sh` completely rewrites `hibernate.cfg.xml`, but backs
  up a copy first as `hibernate.cfg.xml.orig`. It's worth a quick manual
  look at the new file before starting Tomcat for the first time.
- The scripts are reasonably idempotent for a second run, but
  `02-install-offline.sh` replaces the entire Tomcat installation
  (`rm -rf ${INSTALL_DIR}`) - so back up data first if re-running on a
  system already in production use.
- Firewall: `HTTP_PORT` (default `8080`, or `80`/`443` if you switch port or
  reverse proxy) needs to be reachable for users; this is not covered here.
