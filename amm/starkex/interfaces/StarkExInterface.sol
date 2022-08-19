// SPDX-License-Identifier: Apache-2.0.
pragma solidity >=0.8.0;

/*
 * Interface to match deployed StarkEx contracts for interactions
*/
interface StarkExInterface {
  function VERSION() external view returns(string memory);
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

  /**
   * Deposits and withdrawals
  */
  function depositERC20ToVault(uint256 assetId, uint256 vaultId, uint256 quantizedAmount) external;
  function depositEthToVault(uint256 assetId, uint256 vaultId) external payable;
  function withdrawFromVault(uint256 assetId, uint256 vaultId, uint256 quantizedAmount) external;
  function getVaultBalance(address ethKey, uint256 assetId, uint256 vaultId) external view returns (uint256);
  function getQuantizedVaultBalance(address ethKey, uint256 assetId, uint256 vaultId) external view returns (uint256);
  function getWithdrawalBalance(uint256 ownerKey, uint256 assetId) external view returns (uint256 balance);

  function orderRegistryAddress() external returns (address);
  function getAssetInfo(uint256 assetType) external view returns (bytes memory);
  function getQuantum(uint assetId) external view returns(uint);

  function registerToken(uint256 assetType, bytes memory assetInfo, uint256 quantum) external;
  function isTokenAdmin(address testedAdmin) external view returns (bool);
  function registerTokenAdmin(address newAdmin) external;
  function isAssetRegistered(uint256 assetType) external view returns (bool);
}
