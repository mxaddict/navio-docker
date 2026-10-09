# Changelog

All notable changes to this project are documented in this file. The format is
based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Images are
tagged with the navio-core version they package, so this file has no version
headings of its own yet.

## [Unreleased]

### Added

- `i2p` image variant (`<version>-i2p`, `latest-i2p`; Dockerfile target `i2p`)
  bundling the official i2pd router. The entrypoint starts i2pd and runs
  `naviod` with `-i2psam=127.0.0.1:7656`; SAM is bound to loopback and i2pd's
  other client services are off (`i2pd.conf`). Router state persists in the
  `/home/navio/.i2pd` volume; `NAVIO_I2P=0` disables it at run time.
- `I2PD_VERSION` build argument pinning the bundled i2pd release.
- `tor` image variant (`<version>-tor`, `latest-tor`; Dockerfile target `tor`)
  bundling Debian's Tor client. The entrypoint starts Tor and runs `naviod` with
  `-onion=127.0.0.1:9050`; naviod publishes an onion service through Tor's
  control port (cookie auth). Both Tor ports are bound to loopback (`torrc`),
  state persists in the `/home/navio/.tor` volume, and `NAVIO_TOR=0` disables it
  at run time.

### Changed

- The Dockerfile now has three targets, `node` (the default), `i2p` and `tor`;
  CI builds and publishes all of them as a parallel matrix, and only marks a
  release as built once every variant has been pushed.
- The entrypoint runs under `tini -g` in every image, so `docker stop` signals
  the whole process group.
