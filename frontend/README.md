# AstraLend frontend

Next.js app router + wagmi + TanStack Query. Dark-first, no component library —
the primitives in `src/components/ui` are the whole design system.

## Running it

```bash
npm install
cp .env.example .env.local   # point NEXT_PUBLIC_API_BASE_URL at the backend
npm run dev                  # http://localhost:3000
```

The backend must be running; every number on screen comes from it. If it is
down, the status pill in the header says so rather than rendering zeros.

| Variable | Purpose |
| --- | --- |
| `NEXT_PUBLIC_API_BASE_URL` | Backend base URL. |
| `NEXT_PUBLIC_ETH_RPC_URL` / `NEXT_PUBLIC_ARB_RPC_URL` | Optional wagmi transport overrides — set the first to `http://localhost:8545` when developing against Anvil. |

## Structure

```
src/
  app/
    page.tsx            Landing page
    app/                The product: dashboard, markets, borrow, portfolio, activity
  components/
    app/                Wallet, chain switcher, action dialog, market table, gauges
    site/               Landing-only pieces
    ui/                 Primitives: Card, Button, Modal, Meter, Toast, …
  lib/
    api.ts              Typed backend client
    chains.ts           wagmi config + chain metadata
    format.ts           bigint → human formatting, one place
    hooks.ts            Query hooks and poll intervals
    use-tx-runner.ts    Signs and submits a built transaction sequence
```

## How a transaction works

1. The user picks an amount in `ActionDialog`.
2. The dialog asks the backend to **build** the transactions — usually an ERC-20
   approval followed by the protocol call.
3. `useTxRunner` switches the wallet to the right chain, then signs and submits
   each transaction **in order**, waiting for each receipt before the next. The
   second call is never simulated against an allowance that has not landed yet.
4. On success, every affected query is invalidated.

The user's wallet is the only thing that signs. The backend never holds a key
that can move user funds.

## Conventions worth keeping

- **Amounts are `bigint` end to end.** Parse once at the input boundary
  (`parseAmount`), format once at the display boundary (`format.ts`). Never let
  a token amount become a `number` in between.
- **Risk math lives in the backend.** The dialog projects the *pending* health
  factor client-side, but the authoritative numbers come from `/portfolio` — the
  two use the same formula on purpose.
- **Chain-to-read is separate from chain-to-sign.** Browsing Ethereum markets
  with an Arbitrum wallet is fine; the switch is prompted only at signing time.
- **Cross-chain writes are asynchronous.** On a satellite chain, a confirmed
  transaction does not mean hub state has settled. The UI says so instead of
  spinning.
