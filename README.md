# navio-docker

Thin Docker image for running a [Navio](https://github.com/nav-io/navio-core)
full node.

The image ships the **official, pre-built `navio-core` release binaries** —
downloaded and checksum-verified at build time — on top of
`debian:bookworm-slim`. The release binaries are statically linked against
everything except glibc, so the runtime layer carries no extra libraries. No
compilation happens in this repo; it only packages upstream releases.

## Image contents

- `naviod`, `navio-cli`, `navio-wallet`, `navio-staker`, `navio-tx`,
  `navio-util`
- `tini` as PID 1 for clean signal handling and zombie reaping
- Runs as a non-root `navio` user; datadir at `/home/navio/.navio` (a volume)

Two variants are built from the same Dockerfile:

| Variant    | Dockerfile target | Tags                          | Adds                                     |
| ---------- | ----------------- | ----------------------------- | ---------------------------------------- |
| node       | `node` (default)  | `<version>`, `latest`         | —                                        |
| node + I2P | `i2p`             | `<version>-i2p`, `latest-i2p` | [i2pd](https://i2pd.website/) I2P router |

See [I2P](#i2p) for the second one.

## Usage

> Once published, pull `navio/navio` from Docker Hub (see
> [Publishing to Docker Hub](#publishing-to-docker-hub)). To build it yourself:

```bash
docker build -t navio .
```

Run a testnet node in the foreground:

```bash
docker run --rm -it \
    -v navio-data:/home/navio/.navio \
    -p 33670:33670 \
    navio naviod -testnet
```

Because the entrypoint runs `naviod` when the first argument is a flag, this is
equivalent:

```bash
docker run --rm -it -v navio-data:/home/navio/.navio -p 33670:33670 navio -testnet
```

Run `navio-cli` against a running container:

```bash
docker exec <container> navio-cli -testnet getblockchaininfo
```

### Docker Compose

A ready-to-edit [`docker-compose.yml`](docker-compose.yml) is included (testnet
by default, persistent volume, healthcheck):

```bash
docker compose up -d
docker compose logs -f
```

### Ports

| Network  | P2P   | RPC   |
| -------- | ----- | ----- |
| mainnet  | 48470 | 48471 |
| testnet7 | 33670 | 33677 |

RPC binds to loopback by default. Only publish an RPC port if you have
configured authentication and `-rpcallowip`/`-rpcbind` deliberately.

### Configuration

Mount a `navio.conf` into the datadir, or pass flags after the binary name:

```bash
docker run --rm -it \
    -v navio-data:/home/navio/.navio \
    -p 48470:48470 \
    navio naviod -server=1 -rpcuser=navio -rpcpassword=changeme
```

## I2P

The `-i2p` images bundle the official [i2pd](https://github.com/PurpleI2P/i2pd)
router (its Debian bookworm package, checksum-verified at build time). When the
container runs `naviod`, the entrypoint first starts i2pd in the background and
then starts `naviod` with `-i2psam=127.0.0.1:7656`, so the node makes and
accepts I2P connections with no extra setup:

```bash
docker build --target i2p -t navio:i2p .

docker run --rm -it \
    -v navio-data:/home/navio/.navio \
    -v i2pd-data:/home/navio/.i2pd \
    -p 33670:33670 \
    -p 48480:48480/tcp -p 48480:48480/udp \
    navio:i2p -testnet
```

- **SAM stays inside the container.** i2pd's SAM bridge listens on loopback
  only, and every other i2pd client service (web console, HTTP and SOCKS
  proxies) is disabled — see [`i2pd.conf`](i2pd.conf).
- **Router state** lives in `/home/navio/.i2pd`. Keep it on a volume so i2pd
  does not reseed and build a new router identity on every start.
- **Router port** `48480` (TCP and UDP) is optional to publish. Without it i2pd
  runs as a firewalled router: it works, but tunnels build more slowly.
- **I2P only:** add `-onlynet=i2p` to keep the node off clearnet entirely.
- **Logs** from both daemons go to `docker logs`; i2pd logs at `warn` level.
- **Own i2pd config:** mount it at `/etc/i2pd/i2pd.conf`. Keep SAM on
  `127.0.0.1:7656`, or pass a matching `-i2psam=` on the command line.
- **Overriding `-i2psam`:** a value on the command line wins over the
  entrypoint's, but one set in `navio.conf` does not, because command-line flags
  take precedence over the config file.
- **Turning it off:** `-e NAVIO_I2P=0` runs the `-i2p` image as a plain node.
- **No supervision:** if i2pd exits, `naviod` keeps running without I2P until
  the container is restarted.

Prefer a separate router? The plain image works with any i2pd you already run:
start `naviod` with `-i2psam=<host>:7656` pointing at its SAM port.

## Build arguments

| Arg                 | Default  | Effect                                                                              |
| ------------------- | -------- | ----------------------------------------------------------------------------------- |
| `NAVIO_RELEASE_TAG` | `latest` | navio-core release to ship. `latest` = newest (incl. rc). Pin with e.g. `v0.1rc30`. |
| `I2PD_VERSION`      | pinned   | i2pd release bundled in the `i2p` target (see the Dockerfile).                      |

```bash
docker build --build-arg NAVIO_RELEASE_TAG=v0.1rc30 -t navio:rc30 .
```

## Supported platforms

`linux/amd64`, `linux/arm64` are built in CI. The Dockerfile additionally maps
`linux/arm/v7`, `linux/ppc64le`, and `linux/riscv64` to their release triplets.
The `i2p` target supports `linux/amd64`, `linux/arm64` and `linux/arm/v7` only,
the architectures i2pd publishes bookworm packages for.

## CI

[`.github/workflows/build.yml`](.github/workflows/build.yml) builds both images
(`node` and `i2p` targets) for `linux/amd64` and `linux/arm64`. Pull requests
build for verification only (no push); every other event (push to `master`,
schedule, dispatch, manual) **publishes to Docker Hub**.

### Automatic rebuilds on new navio-core releases

The workflow tracks upstream releases without any access to `nav-io/navio-core`:

- **Poll (every 6h):** a scheduled run resolves the newest navio-core release
  and builds **only if that version changed**. Each built version is recorded as
  a `built/<version>` git tag, so unchanged polls do no work.
- **Instant trigger:** fire a `repository_dispatch` to build right away:

  ```bash
  gh api repos/nav-io/navio-docker/dispatches -f event_type=navio-core-release
  ```

For truly instant rebuilds, add a `release: published` workflow to
`nav-io/navio-core` that dispatches the event (needs a PAT with `contents:write`
on this repo stored as a secret there):

```yaml
# .github/workflows/notify-docker.yml in nav-io/navio-core
on:
  release:
    types: [published]
jobs:
  notify:
    runs-on: ubuntu-latest
    steps:
      - run: |
          gh api repos/nav-io/navio-docker/dispatches \
              -f event_type=navio-core-release
        env:
          GH_TOKEN: ${{ secrets.NAVIO_DOCKER_DISPATCH_PAT }}
```

## Publishing to Docker Hub

Publishing is enabled in the workflow (login → build+push → description sync).
Image tags: `<navio-version>`, `latest`, `pr-N`, `sha-…`, each also with an
`-i2p` suffix for the I2P image. It needs two pieces of setup:

1. Create the Docker Hub repository (default target: `navio/navio`).
2. Add repository secrets `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` (use a
   Docker Hub access token, not your account password).

**If the secrets are missing**, a publishing run does not fail — it **cancels
itself** before building, so it never produces an image that cannot be pushed.
PR/test builds skip this gate entirely (they never publish).

Optional: enable `provenance`/`sbom` attestations — scaffolded as TODOs in the
build step.

## License

MIT — see [LICENSE](LICENSE). The packaged `navio-core` binaries are licensed
under the MIT license by the Navio project.
