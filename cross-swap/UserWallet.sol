// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import "./Storage.sol";
import "./DVFAccessControl.sol";
import "./EIP712Upgradeable.sol";

abstract contract UserWallet is Storage, DVFAccessControl, EIP712Upgradeable, ReentrancyGuardUpgradeable {
  using SafeERC20Upgradeable for IERC20Upgradeable;

  event BalanceUpdated(address indexed user, address indexed token, uint256 newBalance);
  event Deposit(address indexed user, address indexed token, uint256 amount);
  event Withdraw(address indexed user, address indexed token, uint256 amount);
  event DelegatedWithdraw(bytes32 id, address indexed user, address indexed token, uint256 amount);
  event LogEmergencyWithdrawalRequested(address indexed user, address indexed token);
  event LogEmergencyWithdrawalSettled(address indexed user, address indexed token);

  bytes32 public constant _WITHDRAW_TYPEHASH =
   keccak256("Withdraw(address user,address token,address to,uint256 amount,uint256 maxFee,uint256 nonce,uint256 deadline,uint256 chainId)");
  uint256 public constant MAX_WITHDRAWAL_DELAY = 24 hours;

  struct WithdrawConstraints {
    address user;
    address token;
    address to;
    uint256 amount;
    uint256 maxFee;
    uint256 nonce;
    uint256 deadline;
    uint256 chainId;
  }

  function __UserWallet_Init() public onlyInitializing {
      withdrawalDelay = MAX_WITHDRAWAL_DELAY;
  }
  
  function emitBalanceUpdated(address user, address token) internal {
    emit BalanceUpdated(user, token, userBalances[user][token]);
  }

  function _accountingSanityCheck(address token, string memory failureMessage) internal view {
      require(
        _contractBalance(token) >= tokenReserves[token],
        failureMessage);
  }
  /**
   * @dev Deposit tokens directly into this contract
   */
  function deposit(address _token, uint256 amount) external {
    depositTo(msg.sender, _token, amount);

    emit Deposit(msg.sender, _token, amount);
  }

  /**
   * @dev Deposit tokens directly into this contract and credit 
   * liquidity provision pool
   */
  function depositToContract(address _token, uint256 amount) external {
    depositTo(address(this), _token, amount);
  }

  /**
   * @dev Deposit tokens directly into this contract and credit {to}
   */
  function depositTo(address to, address token, uint256 amount) public nonReentrant {
    uint256 balanceBefore = _contractBalance(token);
    IERC20Upgradeable(token).safeTransferFrom(msg.sender, address(this), amount);
    uint256 balanceAfter = _contractBalance(token);
    _increaseBalance(token, to, balanceAfter - balanceBefore);
    _accountingSanityCheck(token, "DEPOSIT_TO_ACCOUNTING_FAILURE");
    emitBalanceUpdated(to, token);
  }

  /**
   * @dev Delegated withdraw to withdraw funds on a user's behalf
   * with a valid signature
   */
  function withdraw(
    WithdrawConstraints calldata constraints,
    uint256 feeTaken,
    bytes32 withdrawalId,
    bytes memory signature
  ) external onlyRole(OPERATOR_ROLE) withUniqueId(withdrawalId) {
    ensureDeadline(constraints.deadline);
    require(feeTaken <= constraints.maxFee, 'FEE_TOO_HIGH');

    verifyWithdrawSignature(constraints, signature);

    // Pay the fee to our liquidity pool
    transfer(constraints.user, constraints.token, address(this), feeTaken);

    _withdraw(constraints.user, constraints.token, constraints.amount, constraints.to);

    emitBalanceUpdated(address(this), constraints.token);
    emitBalanceUpdated(constraints.user, constraints.token);
    // TODO find a way to merge this with withdraw
    emit DelegatedWithdraw(withdrawalId, constraints.user, constraints.token, constraints.amount);
  }

  /**
   * @dev Withdraw funds directly from this contract from liquidity pool
   */
  function withdrawFromContract(
    address token,
    uint256 amount,
    address to
  ) public onlyRole(LIQUIDITY_SPENDER_ROLE) {
    _withdraw(address(this), token, amount, to);
    emitBalanceUpdated(address(this), token);
  }

  /**
   * @dev Withdraw all funds creditted to this contract
   */
  function withdrawFromContract(
    address [] calldata  tokens,
    address to
  ) external onlyRole(LIQUIDITY_SPENDER_ROLE) {
    for(uint i=0; i<tokens.length; i++) {
      withdrawFromContract(tokens[i], userBalances[address(this)][tokens[i]], to);
    }
  }

  function _withdraw(address user, address _token, uint256 amount, address to) internal {
    _ensureUserBalance(user, _token, amount);

    IERC20Upgradeable token = IERC20Upgradeable(_token);

    _decreaseBalance(_token, user, amount);

    token.safeTransfer(to, amount);
    _accountingSanityCheck(_token, "WITHDRAW_ACCOUNTING_FAILURE");
  }

  function transfer(address user, address token, address to, uint256 amount) internal {
    _ensureUserBalance(user, token, amount);
    userBalances[user][token] -= amount;
    userBalances[to][token] += amount;
  }

   /**
   * @dev Transfer the specified list of tokens 
   *      from the cross-swap contract to the provided address
   */
  function transfer(
    address [] calldata  tokens,
    address to
  ) external onlyRole(LIQUIDITY_SPENDER_ROLE) {
    for(uint i=0; i<tokens.length; i++) {
      transfer(
        address(this),
        tokens[i],
        to,
        userBalances[address(this)][tokens[i]]);
      emitBalanceUpdated(address(this), tokens[i]);
      emitBalanceUpdated(to, tokens[i]);
    }
  }

  function _increaseBalance(address token, address user, uint256 amount) internal {
    userBalances[user][token] += amount;
    tokenReserves[token] += amount;
  }

  function _decreaseBalance(address token, address user, uint256 amount) internal {
    userBalances[user][token] -= amount;
    tokenReserves[token] -= amount;
  }

  function _ensureUserBalance(address user, address token, uint256 amount) internal view {
    require(userBalances[user][token] >= amount, "INSUFFICIENT_FUNDS");
  }

  /**
   * @dev Unassigned token balances
   */
  function skim(address token, address to) external onlyRole(OPERATOR_ROLE) {
    uint256 currentBalance = _contractBalance(token);
    require(currentBalance > tokenReserves[token], "NOTHING_TO_SKIM");

    IERC20Upgradeable(token).safeTransfer(to, currentBalance - tokenReserves[token]);
  }

  /**
   * @dev deposit unassigned funds to the contract
   */
  function skimToContract(address token) external {
    uint256 currentBalance = _contractBalance(token);
    require(currentBalance > tokenReserves[token], "NOTHING_TO_SKIM");

    uint256 amountAdded = currentBalance - tokenReserves[token];

    _increaseBalance(token, address(this), amountAdded);
    emitBalanceUpdated(address(this), token);
  }

  function _contractBalance(address erc20TokenAddress) internal view returns (uint256) {
    return IERC20Upgradeable(erc20TokenAddress).balanceOf(address(this));
  }

  /**
   * @dev Signature validation for the WithdrawConstraints
   */
  function verifyWithdrawSignature(
    WithdrawConstraints calldata withdrawConstraints,
    bytes memory signature
  ) private {
    require(withdrawConstraints.nonce > userNonces[withdrawConstraints.user], "NONCE_ALREADY_USED");
    require(withdrawConstraints.chainId == block.chainid, "INVALID_CHAIN");

    bytes32 structHash = _hashTypedDataV4(keccak256(
      abi.encode(
        _WITHDRAW_TYPEHASH,
        withdrawConstraints.user,
        withdrawConstraints.token,
        withdrawConstraints.to,
        withdrawConstraints.amount,
        withdrawConstraints.maxFee,
        withdrawConstraints.nonce,
        withdrawConstraints.deadline,
        withdrawConstraints.chainId
      )
    ));

    require(
      SignatureChecker.isValidSignatureNow(withdrawConstraints.user, structHash, signature),
      "INVALID_SIGNATURE");

    userNonces[withdrawConstraints.user] = withdrawConstraints.nonce;
  }

  // TODO de-duplicate and move to a library
  function ensureDeadline(uint256 deadline) internal view {
    // solhint-disable-next-line not-rely-on-time
    require(block.timestamp <= deadline, "DEADLINE_EXPIRED");
  }

  /**
   * @dev Set the 2 step withdrawal required delay, by default 24 hours  
   */
  function setEmergencyWithdrawalDelay(uint256 delay) external onlyRole(DEFAULT_ADMIN_ROLE){
    require(delay <= MAX_WITHDRAWAL_DELAY, 'WITHDRAWAL_DELAY_OVER_MAX');
    withdrawalDelay = delay;
  }

  /**
   * @dev Start emergency withdrawal
   *      Records the current timestamp, when the time elapsed exceeds ${withdrawalDelay} 
   *      funds can be requested via settleEmergencyWithdrawal
   */
  function requestEmergencyWithdrawal(address _token) external {
    emergencyWithdrawalRequests[msg.sender][_token] = block.timestamp;
    emit LogEmergencyWithdrawalRequested(msg.sender, _token);
  }

  /**
   * @dev Settle emergency withdrawal
   *      Withdraws all funds from the specified token
   *      Balance for this token will be set to 0
   *      Emergency withdrawal timer will be reset
   */
  function settleEmergencyWithdrawal(address token) external {
    address sender = msg.sender;
    {
      uint256 requestTimestamp = emergencyWithdrawalRequests[sender][token];
      emergencyWithdrawalRequests[sender][token] = 0;
      require(requestTimestamp > 0, "EMERGENCY_WITHDRAWAL_NOT_REQUESTED");
      require(requestTimestamp + withdrawalDelay < block.timestamp, "EMERGENCY_WITHDRAWAL_STILL_IN_PROGRESS");
    }
    {
      uint256 balance = userBalances[sender][token];
      _withdraw(sender, token, balance, sender);
      emitBalanceUpdated(sender, token);
    }
    emit LogEmergencyWithdrawalSettled(sender, token);
  }
}