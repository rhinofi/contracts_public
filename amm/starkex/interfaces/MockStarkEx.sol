// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.0;

import "./IStarkEx.sol";
import "./IStarkExOrderRegistry.sol";
import "./MFreezable.sol";
import "./MockFreezable.sol";
import "../../uniswapv2/interfaces/IERC20.sol";

contract MockStarkEx is IStarkEx, IStarkExOrderRegistry, MockFreezable {
  string public override VERSION = "3.0.1";

  struct Order {
    address exchangeAddress;
    uint256 tokenIdSell;
    uint256 tokenIdBuy;
    uint256 tokenIdFee;
    uint256 amountSell;
    uint256 amountBuy;
    uint256 amountFee;
    uint256 vaultIdSell;
    uint256 vaultIdBuy;
    uint256 vaultIdFee;
    uint256 nonce;
    uint256 expirationTimestamp;
  }

  event AssetRegistered(uint indexed assetId, address indexed token);

  Order[] public orders;
  mapping(uint => mapping(uint => uint)) public vaults;
  mapping(uint => address) public assets;
  mapping(uint => bytes) public assetInfo;
  mapping(uint => uint) public assetQuantum;

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
  ) external override {
    require(vaultIdSell == vaultIdBuy, 'MockStarkEx: MISMATCHING_VAULTS');
    orders.push(
      Order(
        exchangeAddress,
        tokenIdSell,
        tokenIdBuy,
        tokenIdFee,
        amountSell,
        amountBuy,
        amountFee,
        vaultIdSell,
        vaultIdBuy,
        vaultIdFee,
        nonce,
        expirationTimestamp
      )
    );
  }

  modifier validAsset(uint assetId) {
    require(assets[assetId] != address(0), "Asset Not registered");
    _;
  }

  function register(uint assetId, address token) external {
    emit AssetRegistered(assetId, token);
    assets[assetId] = token;
  }

  function ordersLength() external view returns(uint) {
    return orders.length;
  }

  /**
   * Deposits and withdrawals
  */
  function depositERC20ToVault(uint256 assetId, uint256 vaultId, uint256 quantizedAmount) external validAsset(assetId) override {
    IERC20Uniswap(assets[assetId]).transferFrom(msg.sender, address(this), fromQuantized(quantizedAmount, assetQuantum[assetId]));
    vaults[assetId][vaultId] += quantizedAmount;
  }

  function depositEthToVault(uint256 assetId, uint256 vaultId) external payable override {
    vaults[assetId][vaultId] += toQuantized(msg.value, assetQuantum[assetId]);
  }

  function withdrawFromVault(uint256 assetId, uint256 vaultId, uint256 quantizedAmount) external validAsset(assetId) override {
    require(vaults[assetId][vaultId] >= quantizedAmount, 'StarkEx NOT ENOUGH BALANCE');
    if (isEther(assetId)) {
      uint value = fromQuantized(quantizedAmount, assetQuantum[assetId]);
      payable(msg.sender).transfer(value);
    } else {
      IERC20Uniswap(assets[assetId]).transfer(msg.sender, fromQuantized(quantizedAmount, assetQuantum[assetId]));
    }

    vaults[assetId][vaultId] -= quantizedAmount;
  }

  function getVaultBalance(address, uint256 assetId, uint256 vaultId) external override view returns (uint256) {
    return fromQuantized(vaults[assetId][vaultId], assetQuantum[assetId]);
  }

  function getQuantizedVaultBalance(address, uint256 assetId, uint256 vaultId) external override view returns (uint256) {
    return vaults[assetId][vaultId];
  }

  function orderRegistryAddress() external view override returns (address) {
    return address(this);
  }

  // Mock function to emulate order settlement
  function modifyVault(uint assetId, uint vaultId, uint newValue) external {
    vaults[assetId][vaultId] = newValue;
  }

  // Mock function to emulate order settlement
  function reduceVault(uint assetId, uint vaultId, uint valuetoReduce) external {
    require(vaults[assetId][vaultId] >= valuetoReduce, 'StarkEx: NOT_ENOUGH_BALANCE_TO_REDUCE');
    vaults[assetId][vaultId] -= valuetoReduce;
  }

  function registerToken(uint assetId, bytes memory _assetInfo, uint _quantum) external {
    assetInfo[assetId] = _assetInfo;
    assetQuantum[assetId] = _quantum;
  }

  function getQuantum(uint assetId) external view override returns(uint) {
    return assetQuantum[assetId];
  }

  function getAssetInfo(uint assetId) public view override returns (bytes memory) {
    return assetInfo[assetId];
  }

  function fromQuantized(uint256 quantizedAmount, uint quantum)
      internal pure returns (uint256 amount) {
      amount = quantizedAmount * quantum;
      require(amount / quantum == quantizedAmount, "DEQUANTIZATION_OVERFLOW");
  }

  function toQuantized(uint256 amount, uint quantum)
      internal pure returns (uint256 quantizedAmount) {
      require(amount % quantum == 0, "INVALID_AMOUNT");
      quantizedAmount = amount / quantum;
  }

  uint256 internal constant SELECTOR_OFFSET = 0x20;
  uint256 internal constant SELECTOR_SIZE = 4;
  uint256 internal constant TOKEN_CONTRACT_ADDRESS_OFFSET = SELECTOR_OFFSET + SELECTOR_SIZE;
  function extractTokenSelector(bytes memory _assetInfo) internal pure
      returns (bytes4 selector) {
      assembly {
          selector := and(
              0xffffffff00000000000000000000000000000000000000000000000000000000,
              mload(add(_assetInfo, SELECTOR_OFFSET))
          )
      }
  }
  bytes4 internal constant ETH_SELECTOR = bytes4(keccak256("ETH()"));
  function isEther(uint256 assetType) internal view returns (bool) {
      return extractTokenSelector(getAssetInfo(assetType)) == ETH_SELECTOR;
  }

}
