# xwiki-dev-tools

Tools for development with XWiki

The scripts are meant to be run from wherever this repository is checked out - put the three
script folders on your `PATH`, or link the scripts into a directory that is on it. Every script
prints its usage with `--help`, and every one of them can run without asking anything, so they
work in scripts and for coding agents as well as on the command line.

## installation/create-dev-xwiki.sh

Will allow to install a local XWiki installation for development purposes to a directory of your
choice.<br>
You can install as many local development XWiki system as you like.

Run `create-dev-xwiki.sh` without any arguments, the script will guide you through the
installation. Or pass everything on the command line:

```bash
create-dev-xwiki.sh --version lts --dir ~/xwiki/dev
```

`--version` takes a version number, `lts` for the latest release of the current long term support
branch (the highest `N.10.x`), or `latest` for the latest stable release. Resolving `lts` and
`latest` requires `xmlstarlet`.

The installation is the Jetty/HyperSQL distribution with the standard flavor already installed, so
it is ready to use on the first start. The script enables the local Maven repository as an
extension repository and the `superadmin` account; the preset `Admin` account has the password
`admin`.

## deploy-xar.sh

Will automatically build your project's xar and deploy it on your dev server. Run it from the
project root:

```bash
deploy-xar.sh                                         # local server at http://localhost:8080
deploy-xar.sh --netrc-file ~/.netrc-xwiki --no-build
deploy-xar.sh Admin:admin http://localhost:8080/xwiki/rest
```

Without credentials on the command line they are read from `~/.netrc`, e.g.
`machine localhost login Admin password admin`. Prefer that: credentials given as an argument are
visible in the process list. The pages are imported through XWiki's REST API, which replaces them
without going through the Extension Manager.

Run `deploy-xar.sh --help` to get more information.

## xwiki-dev.sh

Helper script to start, restart and stop an XWiki dev server, and to check its status. `start`
returns once XWiki actually answers, which takes a minute or more.

Run

- `xwiki-dev.sh --dir <installation> start` - or set `XWIKI_DEV_HOME`, or run it from the
  installation folder
- `xwiki-dev.sh restart`
- `xwiki-dev.sh stop`
- `xwiki-dev.sh status`
- `xwiki-dev.sh log [-f]`

`--port` starts XWiki on another port than 8080. XWiki also takes the port below it for its stop
command, so installations running at the same time need ports at least two apart, e.g. 8080 and
8090. The server's output goes to `logs/xwiki-<port>.log` in the installation folder.

## Experimental!!!

Install scripts for XWiki on production server (run at own risk!!!) in folder "installation/offline-installation-production"
