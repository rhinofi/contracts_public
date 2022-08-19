// SPDX-License-Identifier: Apache-2.0.
pragma solidity >=0.8.0;

/**
  Interface for starkEx
 */
interface IStarkEx {
  function VERSION() external view returns(string memory);

  /**
   * Deposits and withdrawals
  */
  function depositERC20ToVault(uint256 assetId, uint256 vaultId, uint256 quantizedAmount) external;
  function depositEthToVault(uint256 assetId, uint256 vaultId) external payable;
  function withdrawFromVault(uint256 assetId, uint256 vaultId, uint256 quantizedAmount) external;
  function getVaultBalance(address ethKey, uint256 assetId, uint256 vaultId) external view returns (uint256);
  function getQuantizedVaultBalance(address ethKey, uint256 assetId, uint256 vaultId) external view returns (uint256);

  function orderRegistryAddress() external returns (address);
  function getAssetInfo(uint256 assetType) external view returns (bytes memory);
  function getQuantum(uint assetId) external view returns(uint);
}
