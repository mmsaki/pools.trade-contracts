## Pools.trade

**LiquidityLauncher** — the multicall entry: `createToken`

- then `distributeToken` (instant)
- or `distributeWithNative` (crowd)
- batched so the minted supply cannot be taken between the two

**UERC20Factory** — mints the token

- metadata comes back from `tokenURI()` as inline base64 JSON

**Liquidity strategy** — instant launch

- initializes a hookless native-ETH v4 pool (fee 2500, spacing 25)
- locks the whole supply as one single-sided range
- so the pool opens with tokens and no ETH

**Crowd (CCA) strategy** — crowd launch

- deploys the auction
- holds the supply
- permissionless `migrate(auction)` seeds the pool (fee 2500, spacing 50) once
  the raise clears

**Liquidity locker** — holds the LP position permanently

- nobody can withdraw it, the protocol included

**Universal Router** — swaps

| name | address |
|------|---------|
| LiquidityLauncher | 0x0000FffFBE8efE702c8703aE3477FF5dE3d319C0 |
| UERC20Factory | 0x000000e200088d55C39a11F609E5F667729AD49b |
| Liquidity strategy | 0x23f8209572b4A1c2AD88a42749E830791fb027F1 |
| Crowd (CCA) strategy | 0x1242C9439d589CAE85E121b1f79F2af51e91dcEe |
| Liquidity locker | 0xEfF166aAf189323C58dc27eD1206Eb2c37fAacdF |
| Universal Router | 0x8876789976dEcBfCbBbe364623C63652db8C0904 |

## Bidding on the CCA

One auction contract per launch

- named in the launch receipt
- the emitter that is not the launcher, factory, token or strategy
- bids go straight to it, not through the launcher

```
submitBid(uint256 maxPrice, uint128 amount, address owner, uint256 prevTickPrice, bytes hookData) payable -> bidId
checkpoint()                       // permissionless, advances auction state
exitBid(uint256 bidId)             // after the end (or a failed auction): refund
claimTokensBatch(address owner, uint256[] bidIds)
migrate(address auction)           // on the crowd strategy: seeds the v4 pool
```

Rules, each learned from a revert

- `maxPrice` on a tick boundary — `floorPrice() + n * tickSpacing()`, else
  `TickPriceNotAtBoundary()`
- strictly above the live `clearingPrice()`, else
  `BidMustBeAboveClearingPrice()`
- `amount` equals the ETH sent; `prevTickPrice` only a search hint
- no exits while running (`AuctionIsNotOver()`), no bids after the end
  (`AuctionIsOver()`)
- claims revert `NotGraduated()` until the raise clears
- exit first, then claim — a claim before the exit reverts
- an auction that never graduates refunds the bid whole

## Finding a launch

- launcher's `TokenCreated(address indexed token)` — every launch
- same receipt carries the factory's metadata event
- and, for an instant launch, PoolManager's `Initialize` with the pool id
- `Initialize` indexes both currencies, so a pool is a point lookup, at any fee
  and spacing

## Tests

`forge test` — forks Robinhood Chain mainnet, nothing deployed locally

- `InstantLaunch` — create + distribute, as two calls and as the site's
  multicall
- `CrowdLaunch` — supply handed to the auction, no pool until graduation
- `CrowdBid` — bid, refund after a failed auction, claims gated on graduation
- `TradeLaunch` — buy, price impact, min-out revert, sell through Permit2
- `LauncherSafety` — graffiti, zero recipient, events, on-chain JSON, and the
  parked-supply front-run the interface warns about

Not covered: a claim against a graduated auction

- a CCA needs demand spread across its whole 144k-block window
- stageable by bidding each rolled chunk above the fresh clearing price
