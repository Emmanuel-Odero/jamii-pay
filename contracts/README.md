# JamiiPay contracts

Smart account configuration + ERC-7579 recovery module on Base. Deliberately
small: we configure audited account-abstraction modules, we do not write new
account-abstraction or cryptographic primitives here.

## First-time setup (Foundry isn't installed on this machine yet)

```sh
curl -L https://foundry.paradigm.xyz | bash
foundryup

cd contracts
forge install foundry-rs/forge-std
forge install eth-infinitism/account-abstraction
forge install erc7579/erc7579-implementation   # pick the actual audited
  # base once selected — this is the reference impl, not necessarily what
  # ships to mainnet.
forge build
forge test
```

Foundry also runs without a local install via the `foundry` Docker image —
see `../docker/docker-compose.yml`, which forks Base with Anvil for local
testing against real on-chain state (tokens, existing contracts).

## Layout

Three validator modules, matching the split described in the tech deck
(`designs/jamii-pay-tech-presentation.html`) — each installed on a user's
smart account as an ERC-7579 validator, each gating a different balance:

| Module | Gates | Requires | Timelock |
|---|---|---|---|
| `SpendModule.sol` | Everyday balance | PIN-derived signature alone | none — "the only thing reachable under duress" |
| `GuardianModule.sol` | Savings balance | Owner signature + 2-of-3 guardians | none (blocks the transfer outright without threshold) |
| `RecoveryModule.sol` | Replacing the account's signers entirely | 2-of-3 guardians (no owner signature — the owner is who's unreachable) | 48h, per the design's Recovery flow |

All three have their actual signature verification stubbed with an explicit
revert rather than a naive implementation — wire each to an audited scheme
(see `forge install` targets above) before any of this holds real funds.

- `src/interfaces/IERC7579Module.sol` — minimal local interface subset (kept
  in-repo so this compiles before the full standard lib is vendored).
- `src/JamiiPaySmartAccount.sol` — documents the module-install surface we
  configure on top of the chosen ERC-4337/7579 account base.
- `script/Deploy.s.sol` — deployment script, run against `local` (Anvil Base
  fork), `base_sepolia`, or `base`.
