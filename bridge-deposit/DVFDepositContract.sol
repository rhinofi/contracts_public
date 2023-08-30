// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

/**
 * Deversifi escrow contract for other chains to allow distribution of tokens
 * from mainnet to other networks
 */
contract DVFDepositContract is OwnableUpgradeable {
  using SafeERC20Upgradeable for IERC20Upgradeable;

  mapping(address => bool) public authorized;
  mapping(string => bool) public processedWithdrawalIds;
  bool public depositsDisallowed;

  modifier _isAuthorized() {
    require(
      authorized[msg.sender],
      "UNAUTHORIZED"
    );
    _;
  }

  modifier _areDepositsAllowed() {
    require(
      !depositsDisallowed,
      "DEPOSITS_NOT_ALLOWED"
    );
    _;
  }

  modifier _withUniqueWithdrawalId(string calldata withdrawalId) {
    require(
      bytes(withdrawalId).length > 0,
      "Withdrawal ID is required"
    );
    require(
      !processedWithdrawalIds[withdrawalId],
      "Withdrawal ID Already processed"
    );
    processedWithdrawalIds[withdrawalId] = true;
    _;
  }

  event BridgedDeposit(address indexed user, address indexed token, uint256 amount);
  event BridgedWithdrawal(address indexed user, address indexed token, uint256 amount, string withdrawalId);

  function initialize() public initializer {
    __Ownable_init();
    authorized[_msgSender()] = true;
  }

  /**
    * @dev Deposit ERC20 tokens into the contract address, must be approved
    */
  function deposit(address token, uint256 amount) external _areDepositsAllowed {
    IERC20Upgradeable(token).safeTransferFrom(msg.sender, address(this), amount);

    // Explicitly avoid confusion with depositNative as a safety
    require(token != address(0), 'BLACKHOLE_NOT_ALLOWED');

    emit BridgedDeposit(msg.sender, token, amount);
  }

  /**
    * @dev Deposit native chain currency into contract address
    */
  function depositNative() external payable _areDepositsAllowed {
    emit BridgedDeposit(msg.sender, address(0), msg.value); // Maybe create new events for ETH deposit/withdraw
  }

  /**
    * @dev Deposit ERC20 token into the contract address
    * NOTE: Restricted deposit function for rebalancing
    */
  function addFunds(address token, uint256 amount) external _isAuthorized {
    IERC20Upgradeable(token).safeTransferFrom(msg.sender, address(this), amount);
  }

  /**
    * @dev Deposit native chain currency into the contract address
    * NOTE: Restricted deposit function for rebalancing
    */
  function addFundsNative() external payable _isAuthorized { }

  /**
    * @dev withdraw ERC20 tokens from the contract address
    * NOTE: only for authorized users
    */
  function withdraw(address token, address to, uint256 amount, string calldata withdrawalId) external
    _isAuthorized
    _withUniqueWithdrawalId(withdrawalId)
  {
    IERC20Upgradeable(token).safeTransfer(to, amount);
    emit BridgedWithdrawal(to, token, amount, withdrawalId);
  }

  /**
    * @dev withdraw ERC20 tokens from the contract address
    * NOTE: only for authorized users
    */
  function withdrawV2(address token, address to, uint256 amount) external
    _isAuthorized
  {
    IERC20Upgradeable(token).safeTransfer(to, amount);
    emit BridgedWithdrawal(to, token, amount, '');
  }

  /**
    * @dev withdraw native chain currency from the contract address
    * NOTE: only for authorized users
    */
  function withdrawNative(address payable to, uint256 amount, string calldata withdrawalId) external
    _isAuthorized
    _withUniqueWithdrawalId(withdrawalId)
  {
    removeFundsNative(to, amount);
    emit BridgedWithdrawal(to, address(0), amount, withdrawalId);
  }

  /**
    * @dev withdraw native chain currency from the contract address
    * NOTE: only for authorized users
    */
  function withdrawNativeV2(address payable to, uint256 amount) external
    _isAuthorized
  {
    (bool success,) = to.call{value: amount}("");
    require(success, "FAILED_TO_SEND_ETH");
    emit BridgedWithdrawal(to, address(0), amount, '');
  }

  /**
    * @dev withdraw ERC20 token from the contract address
    * NOTE: only for authorized users for rebalancing
    */
  function removeFunds(address token, address to, uint256 amount) external
    _isAuthorized
  {
    IERC20Upgradeable(token).safeTransfer(to, amount);
  }

  /**
    * @dev withdraw native chain currency from the contract address
    * NOTE: only for authorized users for rebalancing
    */
  function removeFundsNative(address payable to, uint256 amount) public
    _isAuthorized
  {
    require(address(this).balance >= amount, "INSUFFICIENT_BALANCE");
    to.call{value: amount}("");
  }

  /**
    * @dev add or remove authorized users
    * NOTE: only owner
    */
  function authorize(address user, bool value) external onlyOwner {
    authorized[user] = value;
  }

  function transferOwner(address newOwner) external onlyOwner {
    require(newOwner != owner(), "SAME_OWNER");
    authorized[newOwner] = true;
    authorized[owner()] = false;
    transferOwnership(newOwner);
  }

  function renounceOwnership() public view override onlyOwner {
    require(false, "Unable to renounce ownership");
  }

  function allowDeposits(bool value) external onlyOwner {
    depositsDisallowed = !value;
  }

  receive() external payable { }
}
