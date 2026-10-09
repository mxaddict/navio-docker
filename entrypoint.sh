#!/bin/sh
set -e

# `docker run navio -testnet ...` — if the first arg is a flag, run naviod.
if [ "${1#-}" != "$1" ]; then
    set -- naviod "$@"
fi

# When running the daemon, log to stdout so Docker/`docker logs` captures it.
if [ "$1" = "naviod" ]; then
    shift
    # i2p image: start the bundled i2pd and point naviod at its SAM bridge.
    # -i2psam goes first so a user-supplied -i2psam still wins.
    if [ "${NAVIO_I2P:-0}" = "1" ]; then
        i2pd --conf=/etc/i2pd/i2pd.conf \
            --datadir="$HOME/.i2pd" \
            --certsdir=/usr/share/i2pd/certificates &
        set -- -i2psam=127.0.0.1:7656 "$@"
    fi
    set -- naviod -printtoconsole "$@"
fi

exec "$@"
