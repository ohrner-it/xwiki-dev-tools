#!/usr/bin/env sh
# Uses "local" and "read -p", which dash (/bin/sh on Debian and Ubuntu) and bash both support.
# shellcheck shell=dash

#############################################################
## Script to create an XWiki installation for development. ##
## Start it without arguments to be asked for everything,  ##
## or pass the values as options to run it unattended.     ##
## Run it with --help to see the options.                  ##
#############################################################

set -e

nexusUrl="https://nexus.xwiki.org/nexus/content/groups/public"
distributionPath="org/xwiki/platform/xwiki-platform-distribution-flavor-jetty-hsqldb"

usage() {
  echo "Creates a local XWiki installation (Jetty + HyperSQL, standard flavor) for development."
  echo
  echo "Usage:"
  echo "  sh $0"
  echo "      Asks for all values interactively."
  echo "  sh $0 --version <VERSION> --dir <FOLDER> [--superadmin-password <PASSWORD>] [--archive <FILE>]"
  echo "      Runs without asking anything."
  echo
  echo "Options:"
  echo "  --version <VERSION>             XWiki version, e.g. 17.10.13, or one of:"
  echo "                                    lts     the latest release of the current long term support branch"
  echo "                                    latest  the latest stable release"
  echo "  --dir <FOLDER>                  Installation folder. Must not exist yet."
  echo "  --superadmin-password <PASS>    Password of the built-in \"superadmin\" account (default: superadmin)."
  echo "  --archive <FILE>                Data archive to import into the new installation."
  echo "  -h, --help                      Show this help."
}

# Prints the highest stable release matching the given extended regular expression, taken from the
# Maven metadata of the distribution. That metadata is the list of all published versions; its
# <latest> element names the most recently *deployed* version, which is not necessarily the highest
# one, because maintenance releases of older branches are deployed after newer releases.
resolveVersion() {
  local pattern="$1" keyword="$2" metadata resolved

  if ! [ -x "$(command -v xmlstarlet)" ]; then
    echo >&2 "Error: xmlstarlet is required to resolve \"$keyword\" to a version. Please install it (Debian/Ubuntu: sudo apt install xmlstarlet) or pass an explicit version."
    exit 1
  fi

  metadata=$(curl -sS --fail --max-time 60 "$nexusUrl/$distributionPath/maven-metadata.xml") || {
    echo >&2 "Error: Could not read the list of XWiki versions from $nexusUrl."
    exit 1
  }

  resolved=$(printf '%s\n' "$metadata" \
    | xmlstarlet sel -t -v '/metadata/versioning/versions/version' -n \
    | grep -E "$pattern" | sort -V | tail -n 1)

  if [ -z "$resolved" ]; then
    echo >&2 "Error: No XWiki release found for \"$keyword\"."
    exit 1
  fi

  echo "$resolved"
}

# Uncomments a property in an XWiki configuration file: replaces the line matching the extended
# regular expression given second with the sed replacement given third. Fails if the commented
# line is not there, instead of leaving the installation silently unconfigured when a new XWiki
# version changes it.
enableProperty() {
  local file="$1" commentedLine="$2" replacement="$3"

  if ! grep -qE "^$commentedLine" "$file"; then
    echo >&2 "Error: $file does not contain a line matching \"$commentedLine\" - cannot configure this XWiki version."
    exit 1
  fi

  sed -i -E "s|^$commentedLine|$replacement|" "$file"
}

xwikiVersion=""
installationFolder=""
superadminPassword=""
archiveFile=""

if [ "$#" -eq 0 ]; then
  read -r -p "Enter XWiki version (e.g. 17.10.13, lts or latest): " xwikiVersion
  read -r -p "Enter relative or absolute path to installation folder: " installationFolder
  # Password for the built-in "superadmin" account, enabled below to provide a
  # user that is guaranteed to have Programming Right for scripted administration.
  read -r -p "Enter superadmin password to enable [superadmin]: " superadminPassword
  read -r -p "Enter the data archive file to be imported (leave empty if not needed): " archiveFile
fi

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --version|--dir|--superadmin-password|--archive)
      if [ "$#" -lt 2 ]; then
        echo >&2 "Error: $1 needs a value."
        exit 1
      fi ;;
  esac
  case "$1" in
    --version) xwikiVersion="$2"; shift 2 ;;
    --dir) installationFolder="$2"; shift 2 ;;
    --superadmin-password) superadminPassword="$2"; shift 2 ;;
    --archive) archiveFile="$2"; shift 2 ;;
    *) echo >&2 "Error: Unknown argument \"$1\"."; echo >&2; usage >&2; exit 1 ;;
  esac
done

# The preset password is printed at the end, one that was chosen is not.
if [ -z "$superadminPassword" ]; then
  superadminPassword="superadmin"
  superadminPasswordShown="\"superadmin\""
else
  superadminPasswordShown="you chose"
fi

# xwiki.cfg is read as a Java properties file, where a backslash starts an escape sequence, and a
# line break would end the value.
case "$superadminPassword" in
  *\\*|*"
"*)
    echo >&2 "Error: The superadmin password must not contain a backslash or a line break."
    exit 1 ;;
esac

if [ -z "$xwikiVersion" ] || [ -z "$installationFolder" ]; then
  echo >&2 "Error: Both the XWiki version and the installation folder are required."
  echo >&2
  usage >&2
  exit 1
fi

for tool in bsdtar wget curl; do
  if ! [ -x "$(command -v "$tool")" ]; then
    echo >&2 "Error: $tool is required but not installed. On Debian/Ubuntu: sudo apt install libarchive-tools wget curl"
    exit 1
  fi
done

if [ -n "$archiveFile" ] && ! [ -f "$archiveFile" ]; then
  echo >&2 "Error: Data archive \"$archiveFile\" does not exist."
  exit 1
fi

case "$xwikiVersion" in
  # The LTS branch is the .10 release line of each yearly cycle.
  lts) xwikiVersion=$(resolveVersion '^[0-9]+\.10\.[0-9]+$' lts) ;;
  latest) xwikiVersion=$(resolveVersion '^[0-9]+\.[0-9]+\.[0-9]+$' latest) ;;
esac

# realpath needs the parent folder to exist.
mkdir -p "$(dirname "$installationFolder")"
installationFolder=$(realpath "$installationFolder")
url="$nexusUrl/$distributionPath/$xwikiVersion/xwiki-platform-distribution-flavor-jetty-hsqldb-$xwikiVersion.zip"

if [ -e "$installationFolder" ]; then
  echo >&2 "Error: Installation folder \"$installationFolder\" already exists."
  exit 1
fi

echo "Starting download of XWiki with HyperSQL database and standard flavor in version \"$xwikiVersion\" to \"$installationFolder\"."

# A progress bar is only useful to somebody watching; in a log it is thousands of lines of noise,
# and only the reason of a failure is worth keeping there.
if [ -t 1 ]; then
  wgetOutput="--quiet --show-progress"
else
  wgetOutput="--no-verbose"
fi

# A half finished installation is removed again, whatever step fails, so that the script can
# simply be run once more.
mkdir -p "$installationFolder"
trap 'rm -rf "$installationFolder"' EXIT

# $wgetOutput holds one or two options and is split on purpose.
# shellcheck disable=SC2086
if ! wget $wgetOutput "$url" -O "$installationFolder/xwiki.zip"; then
  echo >&2 "Error: Could not download XWiki $xwikiVersion from $url - is the version correct?"
  exit 1
fi
bsdtar -xf "$installationFolder/xwiki.zip" -C "$installationFolder" --strip-components 1
rm "$installationFolder/xwiki.zip"

xwikiProperties="$installationFolder/webapps/xwiki/WEB-INF/xwiki.properties"
xwikiCfg="$installationFolder/webapps/xwiki/WEB-INF/xwiki.cfg"

# Add the local Maven repository as an additional source of XWiki extensions. Enabling one
# extension.repositories entry replaces the built-in default list, so the default repositories
# are enabled explicitly as well.
enableProperty "$xwikiProperties" \
  '# (extension\.repositories = maven-local:maven:.*)' '\1'
enableProperty "$xwikiProperties" \
  '# (extension\.repositories = maven-xwiki:maven:https://nexus\.xwiki\.org/nexus/content/groups/public)' '\1'
enableProperty "$xwikiProperties" \
  '# (extension\.repositories = store\.xwiki\.com:xwiki:https://store\.xwiki\.com/xwiki/rest/)' '\1'
enableProperty "$xwikiProperties" \
  '# (extension\.repositories = extensions\.xwiki\.org:xwiki:https://extensions\.xwiki\.org/xwiki/rest/)' '\1'

# Enable the built-in "superadmin" account (disabled by default). It always has
# Programming Right, which is required for scripted extension management
# (install / uninstall / cache clearing). Dev-only: never enable superadmin in prod.
# The password becomes part of a sed replacement, where \, & and the delimiter | are special.
escapedPassword=$(printf '%s' "$superadminPassword" | sed 's/[\\&|]/\\&/g')
enableProperty "$xwikiCfg" \
  '# xwiki\.superadminpassword=.*' "xwiki.superadminpassword=$escapedPassword"

if [ -n "$archiveFile" ]; then
  bsdtar -xf "$archiveFile" -C "$installationFolder/data" --strip-components 1
fi

trap - EXIT

echo "XWiki $xwikiVersion has been successfully installed in folder \"$installationFolder\"."
echo "You can start XWiki with $installationFolder/start_xwiki.sh, or with xwiki-dev.sh (see its --help)."
echo "Then open your browser and call http://localhost:8080/xwiki"
echo "The username of the superuser is \"Admin\", the preset password is \"admin\"."
echo "The \"superadmin\" account is enabled with the password $superadminPasswordShown."
