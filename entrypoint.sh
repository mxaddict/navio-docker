#!/bin/sh
set -e

# `docker run navio -testnet ...` — if the first arg is a flag, run naviod.
if [ "${1#-}" != "$1" ]; then
    set -- naviod "$@"
fi

# When running the daemon, log to stdout so Docker/`docker logs` captures it.
if [ "$1" = "naviod" ]; then
    shift
    set -- naviod -printtoconsole "$@"
fi

exec "$@"
