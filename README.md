## Pools.trade

Robinhood Chain mainnet. Addresses recovered from captured launch calldata and
verified on-chain; `test/` exercises all of it against live state.

**LiquidityLauncher** — the multicall entry: `createToken`, then
`distributeToken` (instant) or `distributeWithNative` (crowd), batched so the
minted supply cannot be taken between the two.

**UERC20Factory** — mints the token; its metadata comes back from
`tokenURI()` as inline base64 JSON, no gateway needed.

**Liquidity strategy** — instant launch: initializes a hookless native-ETH v4
pool (fee 2500, spacing 25) and locks the whole supply as one single-sided
range, so the pool opens with tokens and no ETH.

**Crowd (CCA) strategy** — crowd launch: deploys the auction, holds the supply,
and its permissionless `migrate(auction)` seeds the pool (fee 2500, spacing 50)
once the raise clears.

**Liquidity locker** — holds the LP position permanently; nobody can withdraw
it, the protocol included.

**Universal Router** — swaps, the same router the rest of the chain uses.

| name | address |
|------|---------|
| LiquidityLauncher | 0x0000FffFBE8efE702c8703aE3477FF5dE3d319C0 |
| UERC20Factory | 0x000000e200088d55C39a11F609E5F667729AD49b |
| Liquidity strategy | 0x23f8209572b4A1c2AD88a42749E830791fb027F1 |
| Crowd (CCA) strategy | 0x1242C9439d589CAE85E121b1f79F2af51e91dcEe |
| Liquidity locker | 0xEfF166aAf189323C58dc27eD1206Eb2c37fAacdF |
| Universal Router | 0x8876789976dEcBfCbBbe364623C63652db8C0904 |

## Crowd Launch: bidding on the CCA

The auction is its own contract, deployed per launch and named in the launch
receipt (the log emitter that is neither the launcher, the factory, the token,
nor the strategy). Bids go straight to it — not through the launcher.

```
submitBid(uint256 maxPrice, uint128 amount, address owner, uint256 prevTickPrice, bytes hookData) payable -> bidId
checkpoint()                       // permissionless, advances auction state
exitBid(uint256 bidId)             // after the end (or a failed auction): refund
claimTokensBatch(address owner, uint256[] bidIds)
migrate(address auction)           // on the crowd strategy: seeds the v4 pool
```

Rules a bidder actually meets, each one learned from a revert:

- `maxPrice` must sit on a tick boundary — `floorPrice() + n * tickSpacing()`,
  else `TickPriceNotAtBoundary()`.
- It must be strictly above the live `clearingPrice()`, else
  `BidMustBeAboveClearingPrice()`.
- `amount` equals the ETH sent; `prevTickPrice` is only a search hint.
- No exits while the auction runs (`AuctionIsNotOver()`), and no bids after it
  ends (`AuctionIsOver()`).
- Claims revert `NotGraduated()` until the raise clears its target; the bid
  stays exitable and refunds whole if it never does.
- Graduation seeds the pool at fee 2500 / spacing 50 via the strategy's
  permissionless `migrate`.

