# navio-docker

Thin Docker image for running a [Navio](https://github.com/nav-io/navio-core) full node.

The image ships the **official, pre-built `navio-core` release binaries** —
downloaded and checksum-verified at build time — on top of `debian:bookworm-slim`.
The release binaries are statically linked against everything except glibc, so the
runtime layer carries no extra libraries. No compilation happens in this repo; it
only packages upstream releases.

## Image contents

- `naviod`, `navio-cli`, `navio-wallet`, `navio-staker`, `navio-tx`, `navio-util`
- `tini` as PID 1 for clean signal handling and zombie reaping
- Runs as a non-root `navio` user; datadir at `/home/navio/.navio` (a volume)

## Usage

> Publishing to Docker Hub is not wired up yet — see [Deploy](#deploy-todo).
> For now, build the image locally.

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

### Ports

| Network   | P2P   | RPC   |
| --------- | ----- | ----- |
| mainnet   | 48470 | 48471 |
| testnet7  | 33670 | 33677 |

RPC binds to loopback by default. Only publish an RPC port if you have configured
authentication and `-rpcallowip`/`-rpcbind` deliberately.

### Configuration

Mount a `navio.conf` into the datadir, or pass flags after the binary name:

```bash
docker run --rm -it \
    -v navio-data:/home/navio/.navio \
    -p 48470:48470 \
    navio naviod -server=1 -rpcuser=navio -rpcpassword=changeme
```

## Build arguments

| Arg                  | Default  | Effect                                                        |
| -------------------- | -------- | ------------------------------------------------------------- |
| `NAVIO_RELEASE_TAG`  | `latest` | navio-core release to ship. `latest` = newest (incl. rc). Pin with e.g. `v0.1rc30`. |

```bash
docker build --build-arg NAVIO_RELEASE_TAG=v0.1rc30 -t navio:rc30 .
```

## Supported platforms

`linux/amd64`, `linux/arm64` are built in CI. The Dockerfile additionally maps
`linux/arm/v7`, `linux/ppc64le`, and `linux/riscv64` to their release triplets.

## CI

[`.github/workflows/build.yml`](.github/workflows/build.yml) builds the image for
`linux/amd64` and `linux/arm64` on every push and PR, plus a weekly schedule to
pick up new navio-core releases. It currently runs **test builds only** (`push: false`).

## Deploy (TODO)

Publishing to Docker Hub is intentionally left as a follow-up:

1. Create a Docker Hub repository (default target: `mxaddict/navio`).
2. Add repository secrets `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN`.
3. Uncomment the **Log in to Docker Hub** step in the workflow.
4. Set the build step's `push` to `github.event_name != 'pull_request'`.

## License

MIT — see [LICENSE](LICENSE). The packaged `navio-core` binaries are licensed
under the MIT license by the Navio project.
