# Offline Installation of XWiki (Tomcat + PostgreSQL)

## Workflow

**On the internet-connected machine:**

```
./01-download-online.sh
```

Downloads JRE, Tomcat, the XWiki WAR, and the PostgreSQL JDBC driver into
`~/temp-xwiki-offline`. Also copies `00-config.sh` into that directory.

Then transfer `~/temp-xwiki-offline` **and** the scripts `00`-`05` to the
offline machine, e.g. via USB.

**On the offline machine (Debian):**

0. Install and start PostgreSQL (see your note above -
   `apt install postgresql postgresql-contrib`,
   `systemctl enable --now postgresql`). This only works if the Debian
   packages are available locally (an official repo mirror, a local apt
   proxy, etc.) - this is not covered by these scripts.
1. `sudo ./02-install-offline.sh` - extracts JRE/Tomcat, creates the service
   user `xwiki`, extracts the XWiki WAR into
   `/opt/xwiki/webapps/xwiki`, copies the JDBC driver, creates the
   "permanent directory" `/var/lib/xwiki`, writes `setenv.sh`.
2. `sudo ./03-setup-database.sh` - creates the DB role and database in
   PostgreSQL. Requests the password interactively (never stored).
3. `sudo ./04-configure-xwiki.sh` - writes `WEB-INF/hibernate.cfg.xml` for
   PostgreSQL (mapping entries are carried over from the original) and sets
   the permanent directory in `xwiki.properties`. Requests the DB password
   again.
4. `sudo ./05-install-systemd-service.sh` - sets up the systemd service
   `xwiki-tomcat.service`, enables and starts it.

Afterwards, XWiki should be reachable at `http://<host>:8080/xwiki`, where
it will start the usual first-time setup wizard (create admin account, etc.).

## Important notes

- **Do not share real passwords/customer data with Claude or in chat
  tools.** That's why these scripts deliberately request database passwords
  interactively via `read -s` instead of accepting them as plaintext
  parameters.
- All paths/versions/usernames live centrally in `00-config.sh` - adjust
  there if, for example, a different XWiki or Tomcat version is needed
  (then also check the URLs in `01-download-online.sh`).
- `04-configure-xwiki.sh` completely rewrites `hibernate.cfg.xml`, but backs
  up a copy first as `hibernate.cfg.xml.orig`. It's worth a quick manual
  look at the new file before starting Tomcat for the first time.
- The scripts are reasonably idempotent for a second run, but
  `02-install-offline.sh` replaces the entire Tomcat installation
  (`rm -rf ${INSTALL_DIR}`) - so back up data first if re-running on a
  system already in production use.
- Firewall: port 8080 (or later 80/443 via a reverse proxy) needs to be
  reachable for users; this is not covered here.
