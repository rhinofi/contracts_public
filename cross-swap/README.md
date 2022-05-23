# Cross Swap

Cross swap contracts acts as an escrow that enables swapping tokens and keeping token balances

It also features a liquidity pool for collateralised swaps

Depends on:

- `@openzeppelin/contracts`
- `@openzeppelin/contracts-upgradeable`

## Layout

All files are composed together in a single contract `DVFCrossSwap`. Individual component also share the underlying `Storage` for safe upgrades