#!/usr/bin/sh
set -e
if ! [ -x "$(command -v bsdtar)" ]; then
  echo "Error: bsdtar is not installed." >&2
  exit 1
fi

xwikiVersion=""
archiveFile=""
installationFolder=""
read -p "Enter XWIKI Version: " xwikiVersion
read -p "Enter installation folder path: " installationFolder
read -p "Enter the import data archive file: " archiveFile
url="https://nexus.xwiki.org/nexus/content/groups/public/org/xwiki/platform/xwiki-platform-distribution-flavor-jetty-hsqldb/$xwikiVersion/xwiki-platform-distribution-flavor-jetty-hsqldb-$xwikiVersion.zip"
echo  "Donwloading xwiki-hsqldb-standard flavor: $xwikiVersion"
wget -q --show-progress $url -O "$installationFolder/xwiki.zip"
bsdtar -xf "$installationFolder/xwiki.zip" -C "$installationFolder" --strip-components 1
rm "$installationFolder/xwiki.zip"
if [ -e "$archiveFile" ]
then
    bsdtar -xf "$archiveFile" -C "$installationFolder/data" --strip-components 1
fi
echo  "Finish installation"
