# Local simulator

Postgres, a local Base chain fork (Anvil), and the `server` API itself —
`docker compose up -d` here starts the whole backend; nothing needs to run
on the host. (The Flutter app is the one piece that can't be containerized
— there's no iOS Simulator inside a Linux container — so it still runs via
`flutter run` from `../app`, pointed at this stack's `localhost:8081`.)

```sh
cp .env.example .env   # set BASE_FORK_RPC_URL to a real provider
docker compose up -d
docker compose ps
```

Rebuild the server image after changing `crates/server` or `crates/wallet-core`:

```sh
docker compose build server && docker compose up -d server
```

- **server** — `localhost:8081` on the host (`8080` inside the container/
  network — only the host mapping is non-default, to avoid colliding with
  another project's stack on this machine). Built from
  `../crates/server/Dockerfile` (build context is the repo root, since it
  depends on `crates/wallet-core` via a workspace path dependency).
- **Postgres** — `localhost:5433` on the host (`5432` inside the network),
  db/user/password all `jamiipay`. The `server` crate runs its own
  migrations on startup.
- **Anvil (Base fork)** — `localhost:8546` on the host (`8545` inside the
  network), chain id `8453`. Ten funded
  dev accounts are seeded automatically (Anvil's default deterministic
  mnemonic) — grab a private key from the container logs:

  ```sh
  docker compose logs anvil | grep -A 11 "Private Keys"
  ```

  Deploy contracts against it from `../contracts`:

  ```sh
  cd ../contracts
  DEPLOYER_PRIVATE_KEY=<one of the anvil dev keys> \
    forge script script/Deploy.s.sol --rpc-url local --broadcast
  ```

Tear down with `docker compose down` (add `-v` to also drop the Postgres
volume).
