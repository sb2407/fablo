#!/bin/bash

set -e

FABRICA_VERSION="0.0.1"
FABRICA_IMAGE_NAME="softwaremill/fabrica"
FABRICA_IMAGE="$FABRICA_IMAGE_NAME:$FABRICA_VERSION"

COMMAND="$1"
DEFAULT_FABRICA_TARGET="$(pwd)/fabrica-target"
DEFAULT_FABRICA_CONFIG="$(pwd)/fabrica-config.json"

printHelp() {
  echo "Fabrica -- kick-off and manage your Hyperledger Fabric network

Usage:
  fabrica.sh init
    Creates simple Fabrica config in current directory.

  fabrica.sh generate [/path/to/fabrica-config.json [/path/to/fabrica/target]]
    Generates network configuration files in the given directory. Default config file path is '\$(pwd)/fabrica-config.json', default (and recommended) directory '\$(pwd)/fabrica-target'.

  fabrica.sh up [/path/to/fabrica-config.json]
    Starts the Hyperledger Fabric network for given Fabrica configuration file, creates channels, installs and instantiates chaincodes. If there is no configuration, it will call 'generate' command for given config file.

  fabrica.sh <down | start | stop>
    Downs, starts or stops the Hyperledger Fabric network for configuration in the current directory. This is similar to down, start and stop commands for Docker Compose.

  fabrica.sh reboot
    Downs and ups the network. Network state is lost, but the configuration is kept intact.

  fabrica.sh prune
    Downs the network and removes all generated files.

  fabrica.sh recreate [/path/to/fabrica-config.json]
    Prunes and ups the network. Default config file path is '\$(pwd)/fabrica-config.json'

  fabrica.sh chaincode upgrade <chaincode-name> <version>
    Upgrades and instantiates chaincode on all relevant peers. Chaincode directory is specified in Fabrica config file.

  fabrica.sh use [version]
    Updates this Fabrica script to specified version. Prints all versions if no version parameter is provided.

  fabrica.sh <help | --help>
    Prints the manual.

  fabrica.sh version [--verbose | -v]
    Prints current Fabrica version, with optional details."
}

executeOnFabricaDocker() {
  local passed_command="$1"
  local passed_param="$2"
  local fabrica_workspace="$3"
  local fabrica_config="${4:-$FABRICA_CONFIG}"
  local chaincodes_base_dir="$(dirname "$fabrica_config")"

  # Create temporary workspace and remove it after script execution
  if [ -z "$fabrica_workspace" ]; then
    fabrica_workspace="$(mktemp -d -t fabrica.XXXXXXXX)"
    # shellcheck disable=SC2064
    trap "rm -rf \"$fabrica_workspace\"" EXIT
  fi

  docker run -i --rm \
    -v "$fabrica_config":/network/fabrica-config.json \
    -v "$fabrica_workspace":/network/workspace \
    --env FABRICA_CONFIG="$fabrica_config" \
    --env CHAINCODES_BASE_DIR="$chaincodes_base_dir" \
    --env FABRICA_WORKSPACE="$fabrica_workspace" \
    -u "$(id -u):$(id -g)" \
    $FABRICA_IMAGE sh -c "/fabrica/docker-entrypoint.sh \"$passed_command\" \"$passed_param\"" \
    2>&1
}

useVersion() {
  version="$1"

  if [ -n "$version" ]; then
    echo "Updating '$0' to version $version..."
    curl -Lf https://github.com/softwaremill/fabrica/releases/download/"$version"/fabrica.sh -o "$0" && chmod +x "$0"
  else
    executeOnFabricaDocker list-versions
  fi
}

validateConfig() {
  if [ -z "$1" ]; then
    FABRICA_CONFIG="$DEFAULT_FABRICA_CONFIG"
    if [ ! -f "$FABRICA_CONFIG" ]; then
      echo "File $FABRICA_CONFIG does not exist"
      exit 1
    fi
  else
    if [ ! -f "$1" ]; then
      echo "File $1 does not exist"
      exit 1
    fi
    FABRICA_CONFIG="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
  fi

  executeOnFabricaDocker validate
}

generateNetworkConfig() {
  fabrica_config="$1"
  fabrica_target="${2:-$DEFAULT_FABRICA_TARGET}"

  if [ -z "$fabrica_config" ]; then
    fabrica_config="$DEFAULT_FABRICA_CONFIG"
    if [ ! -f "$fabrica_config" ]; then
      echo "File $fabrica_config does not exist"
      exit 1
    fi
  else
    if [ ! -f "$fabrica_config" ]; then
      echo "File $fabrica_config does not exist"
      exit 1
    fi
    fabrica_config="$(cd "$(dirname "$fabrica_config")" && pwd)/$(basename "$fabrica_config")"
  fi

  mkdir -p "$fabrica_target"

  echo "Generating network config"
  echo "    FABRICA_VERSION:      $FABRICA_VERSION"
  echo "    FABRICA_CONFIG:       $fabrica_config"
  echo "    FABRICA_TARGET:       $fabrica_target"

  executeOnFabricaDocker "" "" "$fabrica_target" "$fabrica_config"
}

networkPrune() {
  if [ -f "$DEFAULT_FABRICA_TARGET/fabric-docker.sh" ]; then
    "$DEFAULT_FABRICA_TARGET/fabric-docker.sh" down
  fi
  echo "Removing $DEFAULT_FABRICA_TARGET"
  rm -rf "$DEFAULT_FABRICA_TARGET"
}

networkUp() {
  if [ ! -d "$DEFAULT_FABRICA_TARGET" ] || [ -z "$(ls -A "$DEFAULT_FABRICA_TARGET")" ]; then
    echo "Network target directory is empty"
    generateNetworkConfig "$1"
  fi
  "$DEFAULT_FABRICA_TARGET/fabric-docker.sh" up
}

if [ -z "$COMMAND" ]; then
  printHelp
  exit 1

elif [ "$COMMAND" = "help" ] || [ "$COMMAND" = "--help" ]; then
  printHelp

elif [ "$COMMAND" = "version" ]; then
  executeOnFabricaDocker version "$2"

elif [ "$COMMAND" = "use" ]; then
  useVersion "$2"

elif [ "$COMMAND" = "init" ]; then
  executeOnFabricaDocker init

elif [ "$COMMAND" = "validate" ]; then
  validateConfig "$2"

elif [ "$COMMAND" = "generate" ]; then
  generateNetworkConfig "$2" "$3"

elif [ "$COMMAND" = "up" ]; then
  networkUp "$2"

elif [ "$COMMAND" = "prune" ]; then
  networkPrune

elif [ "$COMMAND" = "recreate" ]; then
  networkPrune
  networkUp "$2"

else
  echo "Executing Fabrica docker command: $COMMAND"
  "$DEFAULT_FABRICA_TARGET/fabric-docker.sh" "$COMMAND" "$2" "$3" "$4"
fi
