// SPDX-License-Identifier: Apache-2.0.
pragma solidity >=0.8.0;

/**
 * Interface for StarkEx Order Registry
 * https://github.com/starkware-libs/starkex-contracts/blob/0efa9ce324b04226de5dcd7a0139b109bca8f074/scalable-dex/contracts/src/starkex/components/OrderRegistry.sol#L6
 */
interface IStarkExOrderRegistry {
  event LogL1LimitOrderRegistered( address userAddress, address exchangeAddress, uint256 tokenIdSell, uint256 tokenIdBuy,
      uint256 tokenIdFee, uint256 amountSell, uint256 amountBuy, uint256 amountFee, uint256 vaultIdSell, uint256 vaultIdBuy,
      uint256 vaultIdFee, uint256 nonce, uint256 expirationTimestamp);

  /**
   * Register an L1 limit order
   */
  function registerLimitOrder(
      address exchangeAddress,
      uint256 tokenIdSell,
      uint256 tokenIdBuy,
      uint256 tokenIdFee,
      uint256 amountSell,
      uint256 amountBuy,
      uint256 amountFee,
      uint256 vaultIdSell,
      uint256 vaultIdBuy,
      uint256 vaultIdFee,
      uint256 nonce,
      uint256 expirationTimestamp
  ) external;
}
