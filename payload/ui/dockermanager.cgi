#!/bin/sh

# Xiaomi's plugin gateway always executes <plugin-id>.cgi. Keep the API and
# static-file implementation in docker-manager.cgi and delegate to it here.
# Firmware can execute the CGI through /dev/fd/N; resolve the file first.
SCRIPT_FILE=$(readlink -f "$0") || exit 1
SCRIPT_DIR=$(CDPATH= cd -P "$(dirname "$SCRIPT_FILE")" && pwd -P)
exec "$SCRIPT_DIR/docker-manager.cgi"

