#!/usr/bin/env sh
# Uses "local", which dash (/bin/sh on Debian and Ubuntu) and bash both support.
# shellcheck shell=dash

# Script to build an extension and install it through the Extension Manager of the dev server -
# also again, after every new build of the same version.

set -u

usage() {
  echo "Script will build the XWiki extension (XAR or JAR) of the Maven module in the current folder and"
  echo "install it with its dependencies through the Extension Manager of the development server."
  echo
  echo "Usage:"
  echo "  sh $0 [OPTIONS] [<USERNAME>:<PASSWORD>] [<REST_ENTRY_POINT>] [-- <MAVEN_ARGUMENTS>]"
  echo
  echo "  <USERNAME>:<PASSWORD>  Credentials of an XWiki account with programming rights. Without them,"
  echo "                         they are taken from ~/.netrc, or from the file given with --netrc-file."
  echo "                         Prefer a netrc file: arguments are visible to other users in the"
  echo "                         process list for as long as the build and the deployment take."
  echo "  <REST_ENTRY_POINT>     Default: http://localhost:8080/xwiki/rest"
  echo "  <MAVEN_ARGUMENTS>      Passed on to Maven, e.g. -DskipTests."
  echo
  echo "Options:"
  echo "  --netrc-file <FILE>    Read the credentials from this netrc file."
  echo "  --wiki <WIKI>          Install the extension on this wiki. Default: where it is installed"
  echo "                         already, otherwise on the main wiki."
  echo "  --farm                 Install the extension on the whole farm (the root namespace)."
  echo "  --force                Reinstall the extension even if the wiki has this build already, e.g."
  echo "                         to restore the pages of a XAR."
  echo "  --no-build             Install what the last build put into the local Maven repository."
  echo "  --verbose              Show the whole log of the Extension Manager, not only its warnings."
  echo "  -h, --help             Show this help."
  echo
  echo "The extension is built with \"mvn clean install\", which puts it into the local Maven repository,"
  echo "one of the extension repositories of the development server. In a module of a multi-module"
  echo "project, the modules it depends on are built along with it (\"mvn -pl <module> -am clean install\")."
  echo
  echo "The Extension Manager never downloads a version again it has once downloaded. If the wiki has"
  echo "another build of the version than the local Maven repository - as after every new build of a"
  echo "SNAPSHOT - this script uninstalls it, replaces the Extension Manager's copy with the new build and"
  echo "installs it again, without a restart. This applies to every extension with the same Maven group"
  echo "id, so that a JAR module of the project is updated along with the XAR that depends on it, and"
  echo "extensions uninstalled along with them are installed again. As every build is a new one, the"
  echo "modules built along with the extension are reinstalled on every run. The pages of a reinstalled"
  echo "XAR get the content of the new build, changes made to them on the wiki are lost."
  echo
  echo "The work is done by the hidden page XWiki.DevToolsDeployExtension in the main wiki, which this"
  echo "script creates and updates. Its Groovy script needs programming rights, which Admin has."
  echo
  echo "Examples:"
  echo "  sh $0"
  echo "  sh $0 -- -DskipTests"
  echo "  sh $0 --no-build --force http://localhost:8090/xwiki/rest"
}

credentials=""
netrcFile=""
restEntryPoint="http://localhost:8080/xwiki/rest"
namespace=""
build=true
force=false
verbose=false

while [ "$#" -gt 0 ]; do
  case "$1" in
    --netrc-file|--wiki)
      if [ "$#" -lt 2 ]; then
        echo >&2 "Error: $1 needs a value."
        exit 1
      fi ;;
  esac
  case "$1" in
    --) shift; break ;;
    --netrc-file) netrcFile="$2"; shift 2 ;;
    --wiki) namespace="wiki:$2"; shift 2 ;;
    --farm) namespace="{root}"; shift ;;
    --force) force=true; shift ;;
    --no-build) build=false; shift ;;
    --verbose) verbose=true; shift ;;
    -h|--help) usage; exit 0 ;;
    http://*|https://*) restEntryPoint="${1%/}"; shift ;;
    -*) echo >&2 "Error: Unknown option \"$1\" - Maven arguments go after \"--\"."; echo >&2; usage >&2; exit 1 ;;
    *:*)
      # A second one is most likely a REST entry point given without http:// or https://.
      if [ -n "$credentials" ]; then
        echo >&2 "Error: \"$1\" is neither credentials, which were given already, nor a REST entry point, which has to start with http:// or https://."
        exit 1
      fi
      credentials="$1"; shift ;;
    *) echo >&2 "Error: Unexpected argument \"$1\"."; echo >&2; usage >&2; exit 1 ;;
  esac
done
# The remaining arguments are Maven's.

if [ -n "$credentials" ] && [ -n "$netrcFile" ]; then
  echo >&2 "Error: Pass either credentials or --netrc-file, not both."
  exit 1
fi

case "$restEntryPoint" in
  */rest) ;;
  *) echo >&2 "Error: \"$restEntryPoint\" is no REST entry point, which ends with /rest."; exit 1 ;;
esac
# The helper page is run through the normal web interface, which is next to the REST API.
webApplication="${restEntryPoint%/rest}"

if ! [ -f "./pom.xml" ]; then
  echo >&2 "Error: Please start this script in the folder of the Maven module that builds the extension!"
  exit 2
fi

if [ -n "$netrcFile" ] && ! [ -r "$netrcFile" ]; then
  echo >&2 "Error: Cannot read netrc file \"$netrcFile\"."
  exit 2
fi

mvnCommand=$(command -v mvnd || command -v mvn)
if [ -z "$mvnCommand" ]; then
  echo >&2 "Error: You need Maven to run this script!"
  exit 2
fi

callMaven() {
  local exitCode

  "$mvnCommand" -B -ntp "$@"
  exitCode=$?

  if [ "$exitCode" -ne 0 ]; then
    echo >&2 "Error: Maven call failed with exit code $exitCode"
    exit $exitCode
  fi
}

# Credentials given on the command line are handed to curl through its standard input rather than
# as an argument, so they do not show up in the process list. In a curl config file, backslashes
# and double quotes inside a quoted value have to be escaped.
callCurl() {
  local escapedCredentials

  if [ -n "$credentials" ]; then
    escapedCredentials=$(printf '%s' "$credentials" | sed 's/[\\"]/\\&/g')
    printf 'user = "%s"\n' "$escapedCredentials" | curl --config - "$@"
  elif [ -n "$netrcFile" ]; then
    curl --netrc-file "$netrcFile" "$@"
  else
    curl --netrc-optional "$@"
  fi
}

# Maven itself tells the coordinates, as they may be inherited from the parent or use properties.
# The project id is <groupId>:<artifactId>:<packaging>:<version>.
projectId=$("$mvnCommand" -B -ntp -q -N org.apache.maven.plugins:maven-help-plugin:3.5.2:evaluate \
  -Dexpression=project.id -DforceStdout)
if [ "$?" -ne 0 ] || [ -z "$projectId" ]; then
  echo >&2 "Error: Could not read the coordinates of the Maven module:"
  echo >&2 "$projectId"
  exit 2
fi
version="${projectId##*:}"
projectId="${projectId%:*}"
packaging="${projectId##*:}"
extensionId="${projectId%:*}"

if [ "$packaging" = "pom" ]; then
  echo >&2 "Error: $extensionId is a parent POM, not an extension. Please start this script in the folder of the module that builds the extension!"
  exit 2
fi

if [ "$build" = true ]; then
  # In a module of a multi-module project, the modules it depends on are built along with it, so
  # that their current state is installed, not what the local Maven repository has from earlier.
  reactorRoot=$(pwd -P)
  module=""
  while parent=$(dirname "$reactorRoot") && [ -f "$parent/pom.xml" ] \
    && grep -Eq "<module>[[:space:]]*(\./)?${reactorRoot##*/}/?[[:space:]]*</module>" "$parent/pom.xml"; do
    module="${reactorRoot##*/}${module:+/$module}"
    reactorRoot="$parent"
  done

  # XWiki builds need "clean": building again on existing target folders puts XWiki's test
  # configuration into target/classes, and packaging a XAR then fails on hibernate.cfg.xml.
  if [ -n "$module" ]; then
    echo "Building $module with the modules it depends on in $reactorRoot..."
    callMaven -f "$reactorRoot/pom.xml" -pl "$module" -am clean install "$@"
  else
    callMaven clean install "$@"
  fi
fi

# The Groovy script below is the content of the helper page. It uses the Extension Manager's own
# components, as neither the REST API nor the script service can remove a downloaded extension.
helperScript='{{groovy}}
// Helper page of deploy-extension.sh from xwiki-dev-tools, which creates and updates it on each
// run - changes made here are lost. It installs an extension from the extension repository with a
// file: URL, the local Maven repository, and first replaces the copies the Extension Manager has
// of builds that are older than the ones in that repository.
import java.security.MessageDigest

import org.apache.commons.lang3.exception.ExceptionUtils
import org.xwiki.extension.ExtensionId
import org.xwiki.extension.ResolveException
import org.xwiki.extension.repository.ExtensionRepositoryManager
import org.xwiki.extension.repository.InstalledExtensionRepository
import org.xwiki.extension.repository.LocalExtensionRepository
import org.xwiki.logging.LogLevel
import org.xwiki.security.authorization.AuthorizationManager
import org.xwiki.security.authorization.Right

def output = new StringBuilder()
def say = { line -> output.append(line).append("\n") }
def verbose = request.getParameter("verbose") == "true"

def respond = { int status ->
  response.setStatus(status)
  response.setContentType("text/plain; charset=UTF-8")
  // Read by deploy-extension.sh to tell that this script ran, and how it ended.
  say(status == 200 ? "DEPLOY-EXTENSION: SUCCESS" : "DEPLOY-EXTENSION: FAILURE")
  response.getWriter().print(output.toString())
  xcontext.setFinished(true)
}

def displayName = { namespace -> namespace ?: "the farm" }

def sha256 = { extension ->
  extension.getFile().openStream().withCloseable { stream ->
    def digest = MessageDigest.getInstance("SHA-256")
    byte[] buffer = new byte[65536]
    int count
    while ((count = stream.read(buffer)) > 0) {
      digest.update(buffer, 0, count)
    }
    digest.digest().encodeHex().toString()
  }
}

def runJob = { String action, extensionRequest ->
  // Nobody could answer the questions of an interactive job, such as which pages to delete, so
  // the Extension Manager takes its default answers.
  extensionRequest.setInteractive(false)
  def job = action == "install" ? services.extension.install(extensionRequest)
    : services.extension.uninstall(extensionRequest)
  if (job == null) {
    throw new IllegalStateException("The ${action} job did not start: ${services.extension.getLastError()}")
  }
  job.join()
  def status = job.getStatus()
  status.getLog().each { event ->
    def message = event.getFormattedMessage()
    // Maven does not put checksums into its local repository, which Aether warns about every time.
    def checksumWarning = message.startsWith("Could not validate integrity of download from file:")
    if (event.getLevel().ordinal() <= (verbose ? LogLevel.INFO : LogLevel.WARN).ordinal() && !checksumWarning) {
      def cause = event.getThrowable() != null ? " - " + ExceptionUtils.getRootCauseMessage(event.getThrowable()) : ""
      say("  [${event.getLevel()}] ${message}${cause}")
    }
  }
  if (status.getError() != null || status.getLog().hasLogLevel(LogLevel.ERROR)) {
    throw new IllegalStateException("The ${action} job failed, see its log above.")
  }
}

def deploy = {
  def authorizationManager = services.component.getInstance(AuthorizationManager)
  if (!authorizationManager.hasAccess(Right.PROGRAM, xcontext.getUserReference(), null)) {
    say("You need programming rights to deploy extensions with this page.")
    return 403
  }

  def extensionId = request.getParameter("extensionId")
  def version = request.getParameter("version")
  def requestedNamespace = request.getParameter("namespace")
  def force = request.getParameter("force") == "true"
  if (!extensionId || !version) {
    say("The parameters extensionId and version are required.")
    return 400
  }
  def id = new ExtensionId(extensionId, version)

  def localRepository = services.component.getInstance(LocalExtensionRepository)
  def installedRepository = services.component.getInstance(InstalledExtensionRepository)
  def buildRepository = services.component.getInstance(ExtensionRepositoryManager).getRepositories()
    .find { it.getDescriptor().getURI().getScheme() == "file" }
  if (buildRepository == null) {
    say("The wiki has no extension repository with a file: URL, such as the local Maven repository. Add one to extension.repositories in xwiki.properties.")
    return 500
  }
  def buildRepositoryURI = buildRepository.getDescriptor().getURI()
  def resolveBuild = { ExtensionId buildId ->
    try {
      return buildRepository.resolve(buildId)
    } catch (ResolveException e) {
      return null
    }
  }
  def build = resolveBuild(id)
  if (build == null) {
    say("${id} is not in ${buildRepositoryURI}. Build it with mvn clean install first.")
    return 500
  }

  // The Extension Manager installs from its local extension repository and only downloads what is
  // missing there, so the copies of older builds have to go first. The extensions with the same
  // group id include the other modules of the project the extension depends on.
  def groupPrefix = extensionId.substring(0, extensionId.indexOf(":") + 1)
  def outdated = localRepository.getLocalExtensions().findAll { local ->
    if (!local.getId().getId().startsWith(groupPrefix)) {
      return false
    }
    def localBuild = resolveBuild(local.getId())
    return localBuild != null && ((force && local.getId() == id) || sha256(local) != sha256(localBuild))
  }

  // Extensions installed on their own rather than as a dependency, as pairs of id and namespace.
  def installedOnTheirOwn = {
    def result = [] as LinkedHashSet
    installedRepository.getInstalledExtensions().each { installed ->
      (installed.getNamespaces() ?: [null]).each { namespace ->
        if (!installed.isDependency(namespace)) {
          result << [installed.getId(), namespace]
        }
      }
    }
    return result
  }

  def targetNamespaces
  if (requestedNamespace) {
    targetNamespaces = [requestedNamespace == "{root}" ? null : requestedNamespace]
  } else {
    targetNamespaces = installedRepository.getInstalledExtensions().findAll { it.getId().getId() == extensionId }
      .collectMany { it.getNamespaces() ?: [null] }.unique()
    if (!targetNamespaces) {
      targetNamespaces = ["wiki:" + xcontext.getMainWikiName()]
    }
  }

  if (outdated.isEmpty() && targetNamespaces.every { installedRepository.getInstalledExtension(extensionId, it)?.getId() == id }) {
    say("${id} is installed on ${targetNamespaces.collect(displayName).join(", ")} already, in the build of ${buildRepositoryURI}. Nothing to do - --force reinstalls it.")
    return 200
  }

  def before = installedOnTheirOwn()
  outdated.each { local ->
    def namespaces = installedRepository.getInstalledExtensions().findAll { it.getId() == local.getId() }
      .collectMany { it.getNamespaces() ?: [null] }
    namespaces.each { namespace ->
      // Uninstalling an extension uninstalls the ones depending on it as well, so this is checked again.
      if (installedRepository.getInstalledExtension(local.getId().getId(), namespace)?.getId() == local.getId()) {
        say("Uninstalling ${local.getId()} from ${displayName(namespace)} to replace its build...")
        runJob("uninstall", services.extension.createUninstallRequest(local.getId().getId(), namespace))
      }
    }
  }
  outdated.each { local ->
    say("Removing the build of ${local.getId()} the Extension Manager has downloaded before...")
    localRepository.removeExtension(local)
  }

  // The extensions installed on their own that had to go with the outdated ones come back, with
  // their new build where there is one.
  def installations = [:]
  (before - installedOnTheirOwn()).findAll { it[0].getId() != extensionId }.each { idAndNamespace ->
    installations.computeIfAbsent(idAndNamespace[1], { [] as LinkedHashSet }) << idAndNamespace[0]
  }
  targetNamespaces.each { namespace ->
    installations.computeIfAbsent(namespace, { [] as LinkedHashSet }) << id
  }
  installations.each { namespace, allIds ->
    // An extension may have come back already as a dependency of one installed before.
    def ids = allIds.findAll { installedRepository.getInstalledExtension(it.getId(), namespace)?.getId() != it }
    (allIds - ids).each { say("${it} is installed on ${displayName(namespace)} again.") }
    if (!ids) {
      return
    }
    say("Installing ${ids.join(", ")} on ${displayName(namespace)}...")
    def first = ids.first()
    def installRequest = services.extension.createInstallRequest(first.getId(), first.getVersion().getValue(), namespace)
    ids.drop(1).each { installRequest.addExtension(it) }
    runJob("install", installRequest)
  }

  def stillOutdated = ([id] + outdated*.getId()).unique().findAll { replacedId ->
    def replaced = localRepository.getLocalExtension(replacedId)
    // An outdated dependency that is not needed any longer is gone, which is fine as well.
    replaced == null ? replacedId == id : sha256(replaced) != sha256(resolveBuild(replacedId))
  }
  if (stillOutdated) {
    say("The wiki still does not have the build of ${stillOutdated.join(", ")} in ${buildRepositoryURI}.")
    return 500
  }
  say("${id} is installed on ${targetNamespaces.collect(displayName).join(", ")}, in the build of ${buildRepositoryURI}.")
  return 200
}

try {
  respond(deploy())
} catch (Throwable e) {
  say("Error: ${e}")
  e.getStackTrace().take(verbose ? 50 : 3).each { say("  at ${it}") }
  respond(500)
}
{{/groovy}}'

requestFile=$(mktemp)
responseFile=$(mktemp)
trap 'rm -f "$requestFile" "$responseFile"' EXIT

# The script goes into a CDATA section, so it does not need to be escaped as long as it does not
# contain "]]>".
{
  echo '<?xml version="1.0" encoding="UTF-8"?>'
  echo '<page xmlns="http://www.xwiki.org">'
  echo '  <title>deploy-extension.sh helper</title>'
  echo '  <syntax>xwiki/2.1</syntax>'
  echo '  <hidden>true</hidden>'
  printf '  <content><![CDATA[%s]]></content>\n' "$helperScript"
  echo '</page>'
} > "$requestFile"

echo
echo "Updating the helper page XWiki.DevToolsDeployExtension at $restEntryPoint..."
httpCode=$(callCurl -sS -o "$responseFile" -w '%{http_code}' \
  -X PUT \
  -H "Content-Type: application/xml" \
  --data-binary "@$requestFile" \
  "$restEntryPoint/wikis/xwiki/spaces/XWiki/pages/DevToolsDeployExtension")
exitCode=$?

if [ "$exitCode" -ne 0 ] || { [ "$httpCode" != "201" ] && [ "$httpCode" != "202" ] && [ "$httpCode" != "304" ]; }; then
  echo >&2 "Error: Could not save the helper page (curl exit code $exitCode, HTTP status ${httpCode:-none})."
  case "$httpCode" in
    401) echo >&2 "The credentials were missing or rejected - see --help for how to pass them." ;;
    403) echo >&2 "The account is not allowed to edit XWiki.DevToolsDeployExtension." ;;
    404|405) echo >&2 "$restEntryPoint is not an XWiki REST entry point." ;;
    *) head -c 2000 "$responseFile" >&2 ;;
  esac
  exit 1
fi

echo "Installing $extensionId $version through the Extension Manager..."
# The request returns once the Extension Manager's jobs are done. They do not ask questions, so they
# should never wait for an answer - the time limit is for the case they still do.
httpCode=$(callCurl -sS -o "$responseFile" -w '%{http_code}' \
  --max-time 1800 \
  -G \
  --data-urlencode "extensionId=$extensionId" \
  --data-urlencode "version=$version" \
  --data-urlencode "namespace=$namespace" \
  --data-urlencode "force=$force" \
  --data-urlencode "verbose=$verbose" \
  "$webApplication/bin/get/XWiki/DevToolsDeployExtension")
exitCode=$?

if [ "$exitCode" -ne 0 ]; then
  echo >&2 "Error: The deployment request failed (curl exit code $exitCode)."
  if [ "$exitCode" -eq 28 ]; then
    echo >&2 "The Extension Manager did not finish within 30 minutes - see the log of the wiki, e.g. with xwiki-dev.sh log."
  fi
  exit 1
fi

case "$(tail -n 1 "$responseFile")" in
  "DEPLOY-EXTENSION: SUCCESS")
    sed '$d' "$responseFile"
    echo "Deployment of $extensionId $version was successful ($(date "+%Y-%m-%d %H:%M:%S")).";;
  "DEPLOY-EXTENSION: FAILURE")
    sed '$d' "$responseFile" >&2
    echo >&2 "Error: Deployment of $extensionId $version failed (HTTP status $httpCode)."
    exit 1 ;;
  *)
    echo >&2 "Error: The helper page did not run (HTTP status $httpCode). Its Groovy script needs an account with programming rights, which saves the page."
    head -c 2000 "$responseFile" >&2
    exit 1 ;;
esac
