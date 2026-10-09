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
    # tor image: start the bundled tor. naviod's -torcontrol default
    # (127.0.0.1:9051) already finds its control port to publish an onion
    # service; -onion routes .onion peers through its SOCKS port from the
    # start, before the control connection is up. User flags still win.
    if [ "${NAVIO_TOR:-0}" = "1" ]; then
        tor -f /etc/tor/torrc &
        set -- -onion=127.0.0.1:9050 "$@"
    fi
    set -- naviod -printtoconsole "$@"
fi

exec "$@"
