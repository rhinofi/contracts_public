// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.4.22 <0.9.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "./BridgeVM.sol";

/**
 * Deversifi escrow contract for other chains to allow distribution of tokens
 * from mainnet to other networks
 */
contract DVFDepositContract is OwnableUpgradeable {
  using SafeERC20Upgradeable for IERC20Upgradeable;

  mapping(address => bool) public authorized;
  mapping(string => bool) public processedWithdrawalIds;
  bool public depositsDisallowed;
  mapping(address => int) public maxDepositAmount;
  BridgeVM private vm;

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

  event BridgedDeposit(address indexed user, address indexed token, uint256 amount);
  event BridgedWithdrawal(address indexed user, address indexed token, uint256 amount, string withdrawalId);
  event BridgedWithdrawalWithNative(address indexed user, address indexed token, uint256 amountToken, uint256 amountNative);
  event BridgedWithdrawalWithData(address indexed token, uint256 amountToken, uint256 amountNative, bytes ref);

  function initialize() public virtual initializer {
    __Ownable_init();
    authorized[_msgSender()] = true;
    createVMContract();
  }

  function createVMContract() public {
    require(address(vm) == address(0), 'VM_ALREADY_DEPLOYED');
    vm = new BridgeVM();
  }

  function checkMaxDepositAmount(address token, uint256 amount) public view {
    int maxDeposit = maxDepositAmount[token];

    require(maxDeposit >= 0, "DEPOSITS_NOT_ALLOWED");

    if(maxDeposit == 0) {
      return;
    }

    require(amount <= uint(maxDeposit), "DEPOSIT_EXCEEDS_MAX");
  }
  /**
    * @dev Deposit ERC20 tokens into the contract address, must be approved
    */
  function deposit(address token, uint256 amount) external _areDepositsAllowed {
    IERC20Upgradeable(token).safeTransferFrom(msg.sender, address(this), amount);

    checkMaxDepositAmount(token, amount);
    // Explicitly avoid confusion with depositNative as a safety
    require(token != address(0), 'BLACKHOLE_NOT_ALLOWED');

    emit BridgedDeposit(msg.sender, token, amount);
  }

  /**
    * @dev Deposit native chain currency into contract address
    */
  function depositNative() external payable _areDepositsAllowed {
    checkMaxDepositAmount(address(0), msg.value);
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
  function withdrawV2(address token, address to, uint256 amount) external
    _isAuthorized
  {
    IERC20Upgradeable(token).safeTransfer(to, amount);
    emit BridgedWithdrawal(to, token, amount, '');
  }

  /**
    * @dev withdraw ERC20 tokens from the contract address and sends native chain currency
    * NOTE: only for authorized users
    */
 function withdrawV2WithNative(address token, address to, uint256 amountToken, uint256 amountNative) external
    _isAuthorized
  {
    (bool success,) = to.call{value: amountNative}("");
    require(success, "FAILED_TO_SEND_ETH");
    IERC20Upgradeable(token).safeTransfer(to, amountToken);
    emit BridgedWithdrawalWithNative(to, token, amountToken, amountNative);
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

 function withdrawWithData(address token, uint256 amount, uint256 amountNative, BridgeVM.Call[] calldata datas, bytes calldata ref)
    external
    _isAuthorized
  {
    require(address(vm) != address(0), 'VM_DOES_NOT_EXIST');
    IERC20Upgradeable(token).safeTransfer(address(vm), amount);
    vm.execute{value: amountNative}(datas);

    emit BridgedWithdrawalWithData(token, amount, amountNative, ref);
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
    authorized[newOwner] = true;
    authorized[owner()] = false;
    transferOwnership(newOwner);
  }

  function renounceOwnership() public view override onlyOwner {
    require(false, "Unable to renounce ownership");
  }

  function allowDepositsGlobal(bool value) external
    _isAuthorized
  {
    depositsDisallowed = !value;
  }

  /**
    * @dev limit deposit amount for a token
    * NOTE: negative amounts will disable deposits
    * NOTE: 0 will allow any amount
  */
  function allowDeposits(address tokenAddress, int256 maxAmount) external 
    _isAuthorized
  {
    maxDepositAmount[tokenAddress] = maxAmount;
  }

  /**
    * @dev Return any funds stuck in VM to this contract
  */
  function withdrawVmFunds(address token) external {
    require(address(vm) != address(0), 'VM_DOES_NOT_EXIST');
    vm.withdrawVmFunds(token);
  }

  receive() external payable { }
}
