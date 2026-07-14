# xwiki-dev-tools

Tools for development with XWiki

## installation/create-dev-xwiki.sh

Will allow to install a local XWiki installation for development purposes to a directory of your
choice.<br>
You can install as many local development XWiki system as you like.
Run `sh create-dev-xwiki` without any arguments, the script will guide you through the
installation.

## deploy-xar.sh

Will automatically deploy your project's xar on your dev server (normally after `mvnd package`
has been run).
Run `sh deploy-xar.sh --help` to get more information.

## xwiki-dev.sh

Helper script to start, restart and stop the XWiki dev server.<br>
Just copy that script in the base directory of your XWIKI dev installation.

Run

- `sh xwiki-dev.sh start`
- `sh xwiki-dev.sh restart`
- `sh xwiki-dev.sh stop`

## Experimental!!!

Install scripts for XWiki on production server (run at own risk!!!) in folder "installation/offline-installation-production"
