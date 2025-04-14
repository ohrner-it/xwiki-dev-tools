#!/usr/bin/sh

############################################################
## Script to create an XWiki installation for development ##
############################################################

set -e

if ! [ -x "$(command -v bsdtar)" ]; then
  echo >&2 "Error: bsdtar is required but not installed. If you use an Ubuntu-based system please try the following: sudo apt install libarchive-tools"
  exit 1
fi

xwikiVersion=""
archiveFile=""
installationFolder=""
read -p "Enter XWiki version: " xwikiVersion
read -p "Enter relative or absolute path to installation folder: " installationFolder
read -p "Enter the data archive file to be imported (leave empty if not needed): " archiveFile

installationFolder=$(realpath "$installationFolder")
url="https://nexus.xwiki.org/nexus/content/groups/public/org/xwiki/platform/xwiki-platform-distribution-flavor-jetty-hsqldb/$xwikiVersion/xwiki-platform-distribution-flavor-jetty-hsqldb-$xwikiVersion.zip"

if [ -d "$installationFolder" ]; then
  echo >&2 "Error: Installation folder \"$installationFolder\" already exits."
  exit 1
fi

echo  "Starting download of XWiki with HyperSQL database and standard flavor in version \"$xwikiVersion\" to \"$installationFolder\"."

mkdir -p "$installationFolder"
wget -q --show-progress $url -O "$installationFolder/xwiki.zip"
bsdtar -xf "$installationFolder/xwiki.zip" -C "$installationFolder" --strip-components 1
rm "$installationFolder/xwiki.zip"

# Modifying configuration to support local Maven repository as additional source of XWiki extensions.
sed -i -E "s|(# )(extension.repositories = maven-local:maven:.*)|\2|" "$installationFolder/webapps/xwiki/WEB-INF/xwiki.properties"
sed -i -E "s|(# )(extension.repositories = maven-xwiki:maven:https://nexus.xwiki.org/nexus/content/groups/public)|\2|" "$installationFolder/webapps/xwiki/WEB-INF/xwiki.properties"
sed -i -E "s|(# )(extension.repositories = store.xwiki.com:xwiki:https://store.xwiki.com/xwiki/rest/)|\2|" "$installationFolder/webapps/xwiki/WEB-INF/xwiki.properties"
sed -i -E "s|(# )(extension.repositories = extensions.xwiki.org:xwiki:https://extensions.xwiki.org/xwiki/rest/)|\2|" "$installationFolder/webapps/xwiki/WEB-INF/xwiki.properties"

if [ -e "$archiveFile" ]
then
    bsdtar -xf "$archiveFile" -C "$installationFolder/data" --strip-components 1
fi

echo "XWiki has been successfully installed in folder \"$installationFolder\"." 
echo "You can start XWiki with $installationFolder/start_xwiki.sh"
echo "Then open your browser and call http://localhost:8080"
echo "The username of the superuser is \"Admin\", the preset password is \"admin\"."

