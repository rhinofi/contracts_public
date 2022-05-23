// SPDX-License-Identifier: GPL-3
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "./Storage.sol";
import "./DVFAccessControl.sol";

abstract contract UserWallet is Storage, DVFAccessControl {
  using SafeERC20Upgradeable for IERC20Upgradeable;

  event BalanceUpdated(address indexed user, address indexed token, uint256 newBalance);
  event Deposit(address indexed user, address indexed token, uint256 amount);
  event Withdraw(address indexed user, address indexed token, uint256 amount);

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
  function depositTo(address to, address _token, uint256 amount) public {
    IERC20Upgradeable token = IERC20Upgradeable(_token);

    uint256 balanceBefore = _contractBalance(token);
    token.safeTransferFrom(msg.sender, address(this), amount);
    uint256 amountAdded = _contractBalance(token) - balanceBefore;

    _increaseBalance(_token, to, amountAdded);
  }

  /**
   * @dev Withdraw funds directly from this contract for yourself
   */
  function withdraw(address _token, uint256 amount) external {
    _withdraw(msg.sender, _token, amount, msg.sender);

    emit Withdraw(msg.sender, _token, amount);
  }

  /**
   * @dev Withdraw funds directly from this contract from liquidity pool
   */
  function withdrawFromContract(
    address _token,
    uint256 amount,
    address to
  ) external onlyRole(LIQUIDITY_SPENDER_ROLE) {
    _withdraw(address(this), _token, amount, to);
  }

  function _withdraw(address user, address _token, uint256 amount, address to) internal {
    _ensureUserBalance(user, _token, amount);

    IERC20Upgradeable token = IERC20Upgradeable(_token);

    token.safeTransfer(to, amount);

    _decreaseBalance(_token, user, amount);
  }

  /**
   * @dev Transfer funds internally between two users
   */
  function transferTo(address token, address to, uint256 amount) external {
    transfer(msg.sender, token, to, amount);
  }

  function transfer(address user, address token, address to, uint256 amount) internal {
    _ensureUserBalance(user, token, amount);
    userBalances[user][token] -= amount;
    userBalances[to][token] += amount;


    emit BalanceUpdated(user, token, userBalances[user][token]);
    emit BalanceUpdated(to, token, userBalances[to][token]);
  }

  function _increaseBalance(address token, address user, uint256 amount) internal {
    userBalances[user][token] += amount;
    tokenReserves[token] += amount;

    emit BalanceUpdated(user, token, userBalances[user][token]);
  }

  function _decreaseBalance(address token, address user, uint256 amount) internal {
    userBalances[user][token] -= amount;
    tokenReserves[token] -= amount;

    emit BalanceUpdated(user, token, userBalances[user][token]);
  }

  function _ensureUserBalance(address user, address token, uint256 amount) internal view {
    require(userBalances[user][token] >= amount, "INSUFFICIENT_FUNDS");
  }

  /**
   * @dev Unassigned token balances
   */
  function skim(address _token, address to) external onlyRole(OPERATOR_ROLE) {
    IERC20Upgradeable token = IERC20Upgradeable(_token);
    uint256 currentBalance = token.balanceOf(address(this));
    require(currentBalance > tokenReserves[_token], "NOTHING_TO_SKIM");

    token.safeTransfer(to, currentBalance - tokenReserves[_token]);
  }

  /**
   * @dev deposit unassigned funds to the contract
   */
  function skimToContract(address _token) external {
    IERC20Upgradeable token = IERC20Upgradeable(_token);
    uint256 currentBalance = token.balanceOf(address(this));
    require(currentBalance > tokenReserves[_token], "NOTHING_TO_SKIM");

    uint256 amountAdded = currentBalance - tokenReserves[_token];

    _increaseBalance(_token, address(this), amountAdded);
  }

  function _contractBalance(IERC20Upgradeable token) internal view returns (uint256) {
    return token.balanceOf(address(this));
  }
}