#!/bin/bash

########
# Loads the docker image and tests the structure
########

set -exu
set -o pipefail

if [[ "${ARCHITECTURE:-}" == "" ]]; then
  echo "!! ARCHITECTURE is not set. Exiting."
  exit 2
fi

# Load our common environment variables for publishing
export CURDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
source $CURDIR/publish-common.sh

# Detect the platform we are running on (needed for container-structure-test)
arch_name=`uname -sr`
case "$arch_name" in
    Darwin*)
        echo "detected MacOS platform"
        LOCAL_MACHINE_ARCH="MacOS"
        ;;
    Linux*)
        echo "detected Linux platform"
        LOCAL_MACHINE_ARCH="Linux"
        ;;
    *)
        echo "Unsupported platform: $arch_name"
        exit 2
        ;;
esac

# Load the image from the artifact created in build-docker.sh
echo "Loading image from archive file..."
docker load < "$PROJECT_ROOT/.artifacts/${DOCKER_ARTIFACT_KEY}-${DOCKER_TAG_VERSION}-${ARCHITECTURE}.tar.gz"

# Ensure we have container-structure-test installed
echo "Ensuring test environment is set up"

BIN_DIR="$PROJECT_ROOT/bin"
TEST_EXEC="$BIN_DIR/container-structure-test"
if [[ ! -f "$TEST_EXEC" ]]; then
  mkdir -p "$BIN_DIR"

  pushd "$BIN_DIR"
  if [[ "$LOCAL_MACHINE_ARCH" == "MacOS" ]]; then
    curl -LO https://storage.googleapis.com/container-structure-test/latest/container-structure-test-darwin-$ARCHITECTURE
    mv container-structure-test-darwin-$ARCHITECTURE container-structure-test
  else
    curl -LO https://storage.googleapis.com/container-structure-test/latest/container-structure-test-linux-$ARCHITECTURE
    mv container-structure-test-linux-$ARCHITECTURE container-structure-test
  fi

  chmod +x container-structure-test
  popd
fi

# Generate our config file
TEST_CONFIG_FILE="$PROJECT_ROOT/.buildkite/publish/container-structure-test.yaml"

# The config file needs escaped dots and pluses - we'll do that here
ESCAPED_VERSION=${VERSION//./\\\\.}
ESCAPED_VERSION=${ESCAPED_VERSION//+/\\\\+}

# Generate the config file text
TEST_CONFIG_TEXT='
schemaVersion: "2.0.0"

commandTests:
  # ensure Python 3.11.* is installed
  - name: "Python 3 Installation 3.11.*"
    command: "python3"
    args: ["--version"]
    expectedOutput: ["Python\\s3\\.11\\.*"]
  - name: "Connectors Installation"
    command: "/app/.venv/bin/elastic-ingest"
    args: ["--version"]
    expectedOutput: ["'"${ESCAPED_VERSION}"'*"]
'
# ... and save the config file
printf '%s\n' "$TEST_CONFIG_TEXT" > "$TEST_CONFIG_FILE"

# Finally, run the tests
echo "Running container-structure-test"
TAG_NAME="$BASE_TAG_NAME:${DOCKER_TAG_VERSION}-${ARCHITECTURE}"
"$TEST_EXEC" test --image "$TAG_NAME" --config "$TEST_CONFIG_FILE"
