## Pools.trade

**LiquidityLauncher** — multicall entry

- `createToken`, then `distributeToken` (instant) or `distributeWithNative` (crowd)

**UERC20Factory** — mints the token

- metadata from `tokenURI()`, inline base64 JSON

**Liquidity strategy** — instant launch

- hookless native-ETH pool, fee 2500, spacing 25
- supply locked single-sided, so it opens with no ETH

**Crowd (CCA) strategy** — crowd launch

- deploys the auction, holds the supply
- `migrate(auction)` seeds the pool once the raise clears — 2500, spacing 50

**Liquidity locker** — LP position, permanently

**Universal Router** — swaps

| name | address |
|------|---------|
| LiquidityLauncher | 0x0000FffFBE8efE702c8703aE3477FF5dE3d319C0 |
| UERC20Factory | 0x000000e200088d55C39a11F609E5F667729AD49b |
| Liquidity strategy | 0x23f8209572b4A1c2AD88a42749E830791fb027F1 |
| Crowd (CCA) strategy | 0x1242C9439d589CAE85E121b1f79F2af51e91dcEe |
| Liquidity locker | 0xEfF166aAf189323C58dc27eD1206Eb2c37fAacdF |
| Universal Router | 0x8876789976dEcBfCbBbe364623C63652db8C0904 |

## Bidding

One auction per launch, named in the launch receipt.

```
submitBid(uint256 maxPrice, uint128 amount, address owner, uint256 prevTickPrice, bytes hookData) payable -> bidId
exitBid(uint256 bidId)             // after the end: refund
claimTokensBatch(address owner, uint256[] bidIds)
checkpoint()                       // permissionless
migrate(address auction)           // on the strategy
```

- `maxPrice` on a tick, above `clearingPrice()`
- no exit while running, no bid after the end
- exit first, then claim
- no graduation, full refund

## Launches

- launcher's `TokenCreated(address indexed token)`
- same receipt: metadata, and `Initialize` if instant
- `Initialize` indexes both currencies — pools are a point lookup

## Tests

`forge test` — forks mainnet

- launch, bid, refund, graduated claim, trade, safety
- uncovered: `migrate` — keeper work, too gas-heavy on a rolled fork
