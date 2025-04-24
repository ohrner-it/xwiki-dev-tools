# xwiki-dev-tools
Tools for development with XWiki

## create-dev-xwiki.sh

Will allow to install a local XWiki installation for development purposes to a directory of your
choice.<br>
You can install as many local development XWiki system as you like.
Run `sh create-dev-xwiki` without any arguments, the script will guide you through the
installation.

## deploy-xar.sh

Will automatically deploy your project's xar on your dev server (normally after `mvnd package`
has been run).
Run `sh deploy-xar --help` to get more information.
