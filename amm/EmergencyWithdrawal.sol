// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.4;

import '@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol';
import '@openzeppelin/contracts/utils/math/SafeMath.sol';
import './uniswapv2/UniswapV2ERC20.sol';
import './uniswapv2/interfaces/IUniswapV2Factory.sol';
import './WithdrawalWallet.sol';
import './PairStorage.sol';

/**
 * @dev Facilitate emergency withdrawal
*/
abstract contract EmergencyWithdrawal is UniswapV2ERC20, PairStorage {
  using SafeERC20Upgradeable for IERC20Upgradeable;
  uint public constant MAX_WITHDRAWAL_DELAY = 14 days;

  WithdrawalWallet withdrawalWallet;

  struct Withdrawal { 
    uint lpTokens;
    uint withdrawalId;
    uint timestamp;
  }

  mapping(address => Withdrawal) public userWithdrawals;
  uint internal withdrawalDelay;

  uint totalRequested;
  uint totalReadyForWithdrawal;
  uint maxUnlockedWithdrawalId;

  uint withdrawalIdCounter;

  // Events, possibly forward to factory for a unified flow
  event WithdrawalRequested(address user, uint amount, uint withdrawalId);
  event WithdrawalCompleted(address user, uint amount, uint token0Amount, uint token1Amount);
  event WithdrawalForced(address user);

  function burnAndTransferToThis(address from, uint lptokenAmount) internal virtual returns (uint token0, uint otken1);

  function __init_EmergencyWithdrawal() internal {
    // Deploy a new contract to use the address as an additional
    // Escrow, this is to avoid mix-up with AMM funds
    withdrawalWallet = new WithdrawalWallet();
    withdrawalDelay = MAX_WITHDRAWAL_DELAY;
  }

  function hasWithdrawalPending(address user) internal view returns (bool) {
    return userWithdrawals[user].lpTokens > 0;
  }

  function getFactory() private view returns (IUniswapV2Factory) {
    return IUniswapV2Factory(factory);
  }

  // TODO temporarily disabled
  function requestWithdrawal() internal returns (uint) {
    require(!hasWithdrawalPending(msg.sender), 'ONLY_1_WITHDRAWAL_ALLOWED');
    uint balance = balanceOf[msg.sender];

    uint userWithdrawalId = ++withdrawalIdCounter;
    userWithdrawals[msg.sender] = Withdrawal(balance, userWithdrawalId, block.timestamp + withdrawalDelay);
    totalRequested += balance;

    // Move user tokens to the escrow
    transfer(address(withdrawalWallet), balance);

    emit WithdrawalRequested(msg.sender, balance, userWithdrawalId);
    getFactory().withdrawalRequested(token0, token1, msg.sender, balance, userWithdrawalId);

    // Waste 1M gas
    // for (uint256 i = 0; i < 21129; i++) {}

    return balance;
  }

  // TODO temporarily disabled
  function withdrawUserFunds() internal returns (uint lpAmount, uint token0Amount, uint token1Amount) {
    require(hasWithdrawalPending(msg.sender), 'NO_WITHDRAWALS_FOR_USER');

    address user = msg.sender;
    Withdrawal memory withdrawal = userWithdrawals[user];

    require(withdrawal.withdrawalId <= maxUnlockedWithdrawalId, 'WITHDRAWAL_NOT_UNLOCKED');
    
    lpAmount = userWithdrawals[user].lpTokens;

    require(totalReadyForWithdrawal >= lpAmount, 'NOT_ENOUGH_TOKENS_UNLOCKED');

    // refunds some gas
    delete userWithdrawals[user];

    token0Amount = (lpAmount * IERC20(token0).balanceOf(address(withdrawalWallet))) / totalReadyForWithdrawal;
    token1Amount = (lpAmount * IERC20(token1).balanceOf(address(withdrawalWallet))) / totalReadyForWithdrawal;

    totalReadyForWithdrawal -= lpAmount;
    
    withdrawalWallet.transfer(token0, user, token0Amount);
    withdrawalWallet.transfer(token1, user, token1Amount);

    emit WithdrawalCompleted(user, lpAmount, token0Amount, token1Amount);
    getFactory().withdrawalCompleted(token0, token1, user, lpAmount, token0Amount, token1Amount);
  }

  /**
   * @dev external function to be overriden with access controls
  */
  function authorizeWithdrawals(uint withdrawalIdTo, uint lpAmount, bool validateId) external virtual;

  /**
   * @dev Move the block to an authorized point
  */
  function _authorizeWithdrawals(uint withdrawalIdTo, uint amount, bool validateId) internal {
    // Potential to require unlocking more
    require(!validateId || withdrawalIdTo > maxUnlockedWithdrawalId, 'WITHDRAWALS_ALREDY_UNLOCKED');
    require(amount <= totalRequested, 'AMOUNT_MORE_THAN_REQUESTS');

    address withdrawalWalletAddress = address(withdrawalWallet);
    (uint token0Amount, uint token1Amount) = burnAndTransferToThis(withdrawalWalletAddress, amount);

    // Now tokens should be at this address
    IERC20Upgradeable(token0).safeTransfer(withdrawalWalletAddress, token0Amount);
    IERC20Upgradeable(token1).safeTransfer(withdrawalWalletAddress, token1Amount);

    totalRequested -= amount;

    // Used to determine the user's share of the withdrawn pool
    totalReadyForWithdrawal += amount;

    // Move withdrawal pointer
    maxUnlockedWithdrawalId = withdrawalIdTo;
  }

  /**
   * @dev withdrawal delay setter
   */
  function _setWithdrawalDelay(uint newDelay) internal {
    require(newDelay < MAX_WITHDRAWAL_DELAY, 'DELAY_TOO_LONG');
    withdrawalDelay = newDelay;
  }

  /**
   * @dev implemented by parent to force L1 toggle
   */
  function _toggleLayer2(bool _isLayer2Live) internal virtual;

  /**
   * @dev Force a withdrawal authorization if timelimit has been reached
   */
  function forceWithdrawalTimelimitReached(address user) external {
    require(hasWithdrawalPending(user), 'NO_WITHDRAWALS_FOR_USER');

    Withdrawal memory withdrawal = userWithdrawals[user];
    require(withdrawal.timestamp < block.timestamp, 'WITHDRAWAL_TIME_LIMIT_NOT_REACHED');
    require(withdrawal.lpTokens > totalReadyForWithdrawal, 'WITHDRAWAL_ALREADY_HONOURED');

    // Now we will force withdrawal since it wasn't honoured
    emit WithdrawalForced(user);
    getFactory().withdrawalForced(token0, token1, user);

    _authorizeWithdrawals(withdrawalIdCounter, totalRequested, false);
    _toggleLayer2(false);
  }
}
