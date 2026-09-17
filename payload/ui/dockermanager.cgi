#!/bin/sh

# Xiaomi's plugin gateway always executes <plugin-id>.cgi. Keep the API and
# static-file implementation in docker-manager.cgi and delegate to it here.
SCRIPT_DIR=$(CDPATH= cd -P "$(dirname "$0")" && pwd -P)
exec "$SCRIPT_DIR/docker-manager.cgi"

