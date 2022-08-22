// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.4;

import './uniswapv2/UniswapV2Pair.sol';
import './uniswapv2/UniswapV2ERC20.sol';
import './uniswapv2/interfaces/IERC20.sol';
import './uniswapv2/interfaces/IUniswapV2Factory.sol';
import './starkex/interfaces/IStarkEx.sol';
import './starkex/interfaces/IStarkExOrderRegistry.sol';
import './uniswapv2/libraries/SafeMath.sol';
import './uniswapv2/libraries/TransferHelper.sol';
import './StarkWareAssetData.sol';
import './uniswapv2/interfaces/IWETH.sol';
import './starkex/libraries/StarkLib.sol';
import './EmergencyWithdrawal.sol';
import './StarkWareSyncDtos.sol';
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract PairWithL2Overlay is UniswapV2Pair, EmergencyWithdrawal, StarkWareAssetData, Initializable {
  using SafeMathUniswap for uint;
  using StarkLib for uint;

  event Layer2StateChange(bool isLayer2, uint balance0, uint balance1, uint totalSupply);

  modifier l2OperatorOnly() {
    if(isLayer2Live) {
      requireOperator();
    }
    _;
  }

  modifier l2Only() {
    require(isLayer2Live, 'DVF: ONLY_IN_LAYER2');
    _;
  }

  modifier operatorOnly() {
    requireOperator();
    _;
  }

  function validateTokenAssetId(uint assetId) private view {
    require(assetId == token0AssetId || assetId == token1AssetId, 'DVF: INVALID_ASSET_ID');
  }

  receive() external payable {
      // accept ETH from WETH and StarkEx
  }

  function getQuantums() public override view returns (uint, uint, uint) {
    require(token0Quanatum != 0, 'DVF: STARKWARE_NOT_SETUP');
    return (lpQuantum, token0Quanatum, token1Quanatum);
  }

  function setupStarkware(uint _assetId, uint _token0AssetId, uint _token1AssetId) external operatorOnly {
    require(_assetId != 0, 'ALREADY_SETUP');
    IStarkEx starkEx = getStarkEx();
    require(extractContractAddress(starkEx, _assetId) == address(this), 'INVALID_ASSET_ID');
    require(isValidAssetId(starkEx, _token0AssetId, token0), 'INVALID_TOKENA_ASSET_ID');
    require(isValidAssetId(starkEx, _token1AssetId, token1), 'INVALID_TOKENB_ASSET_ID');
    lpAssetId = _assetId;
    token0AssetId = _token0AssetId;
    token1AssetId = _token1AssetId;
    token0Quanatum = starkEx.getQuantum(_token0AssetId);
    token1Quanatum = starkEx.getQuantum(_token1AssetId);
  }

  /*
   * Ensure ETH assetId is provided instead of WETH to successfully trade the underlying token
  */
  function isValidAssetId(IStarkEx starkEx, uint assetId, address token) internal view returns(bool) {
    if (token == weth) {
      require(isEther(starkEx, assetId), 'DVF: EXPECTED_ETH_SELECTOR');
      return true;
    }

    address contractAddress = extractContractAddress(starkEx, assetId);

    return token == contractAddress;
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() initializer { }

  function initialize(address _token0, address _token1, address _weth) initializer external {
    super.initialize(_token0, _token1);
    __init_EmergencyWithdrawal();
    weth = _weth;
  }

  function getStarkEx() internal view returns (IStarkEx) {
    return IStarkEx(IUniswapV2Factory(factory).starkExContract());
  }

  function getStarkExRegistry(IStarkEx starkEx) internal returns (IStarkExOrderRegistry) {
    return IStarkExOrderRegistry(starkEx.orderRegistryAddress());
  }

  function requireOperator() internal view {
    require(isOperator(), 'OPERATOR_ONLY');
  }

  function isOperator() internal view returns(bool) {
    return IUniswapV2Factory(factory).isOperator();
  }

  function depositStarkWare(IStarkEx starkEx, address token, uint _quantum, uint _assetId, uint vaultId, uint quantizedAmount) internal {
    if (token == weth) {
      // Must unwrap and deposit ETH
      uint amount = _quantum.fromQuantized(quantizedAmount);

      IWETH(weth).withdraw(amount);
      starkEx.depositEthToVault{value: amount}(_assetId, vaultId);
    } else {
      starkEx.depositERC20ToVault(_assetId, vaultId, quantizedAmount);
    }
  }

  function _swapStarkWare( 
    StarkwareSyncDtos.SwapArgs memory swapArgs,
    uint256 _reserve0,
    uint256 _reserve1,
    address exchangeAddress) private returns(uint, uint) {
    // Local reassignment to avoid stack too deep
    uint tokenAmmSell = swapArgs.tokenUserBuy;
    uint tokenAmmBuy = swapArgs.tokenUserSell;
    uint amountAmmSell = swapArgs.amountUserBuy;
    uint amountAmmBuy = swapArgs.amountUserSell;

    require(tokenAmmSell != tokenAmmBuy, 'DVF: SWAP_PATHS_IDENTICAL');
    require(amountAmmSell > 0 || amountAmmBuy > 0, 'DVF: BOTH_SWAP_AMOUNTS_ZERO');

    validateTokenAssetId(tokenAmmSell);
    validateTokenAssetId(tokenAmmBuy);

    // Validate the swap amounts
    uint balance0;
    uint balance1;
    // Calculate post swap balance
    if (tokenAmmSell == token0AssetId) {
      balance0 = _reserve0 - amountAmmSell;
      balance1 =_reserve1 + amountAmmBuy;
    } else {
      balance0 = _reserve0 + amountAmmBuy;
      balance1 =_reserve1 - amountAmmSell;
    }
    IStarkEx starkEx = getStarkEx();

    uint256 vault = currentVault;

    getStarkExRegistry(starkEx).registerLimitOrder(exchangeAddress, tokenAmmSell, tokenAmmBuy,
      tokenAmmBuy, amountAmmSell, amountAmmBuy, 0, vault, vault, vault, nonce, unsignedInt22);

    return (balance0, balance1);
  }

  function verifyNonceAndLocked(uint nonceToUse) private view {
    bool isLockedLocal = isLocked();
    bool isNonceUsed = nonce > nonceToUse; // TODO revert, temporary change

    require(!(isLockedLocal && nonce == nonceToUse), 'DVF: DUPLICATE_REQUEST');
    require(!isLockedLocal, 'DVF: LOCK_IN_PROGRESS');
    require(!isNonceUsed, 'DVF: NONCE_ALREADY_USED');
  }

  function fundingArgsToOrderedAmounts (
    StarkwareSyncDtos.FundingArgs memory fundingArgs
  ) internal view returns (uint256 token0Amount, uint256 token1Amount) {
    if (fundingArgs.tokenA == token0) {
      return (fundingArgs.tokenAAmount, fundingArgs.tokenBAmount);
    }

    return (fundingArgs.tokenBAmount, fundingArgs.tokenAAmount);
  }

  function verifyTransition(
    StarkwareSyncDtos.SwapArgs memory swapArgs,
    StarkwareSyncDtos.FundingArgs memory fundingArgs
  ) internal pure {
    // Ensure we either have mint/burn
    // or we have a valid swap
    require(fundingArgs.lpAmount > 0 || 
      (swapArgs.tokenUserBuy > 0 && swapArgs.tokenUserSell > 0),
      'DVF: INVALID_SYNC_REQUEST'
    );
  }

  function syncStarkware(
    StarkwareSyncDtos.SwapArgs memory swapArgs,
    StarkwareSyncDtos.FundingArgs memory fundingArgs,
    uint nonceToUse,
    address exchangeAddress
  ) external operatorOnly l2Only {
    verifyNonceAndLocked(nonceToUse);
    verifyTransition(swapArgs, fundingArgs);
    setLock(true);

    nonce = nonceToUse;

    (uint256 initialBalance0, uint256 initialBalance1,) = getReserves();
    initialBalance0 = token0Quanatum.toQuantizedUnsafe(initialBalance0);
    initialBalance1 = token1Quanatum.toQuantizedUnsafe(initialBalance1);
    uint256 balance0 = initialBalance0;
    uint256 balance1 = initialBalance1;
    uint256 initialBalanceLp = lpQuantum.toQuantizedUnsafe(totalSupply);
    uint256 balanceLp = initialBalanceLp;
    bool hasSwap = swapArgs.tokenUserBuy != 0;

    if (fundingArgs.lpAmount > 0) {
      (uint256 token0Amount, uint256 token1Amount) = fundingArgsToOrderedAmounts(fundingArgs);

      if (fundingArgs.isMint) {
        // Mint case
        (balance0, balance1) = _mintStarkware(
          fundingArgs.lpAmount,
          balance0,
          balance1,
          // These need to be in the right order
          token0Amount,
          token1Amount,
          exchangeAddress,
          hasSwap
        );
        // Apply balanceLp update
        balanceLp = initialBalanceLp + fundingArgs.lpAmount;
      } else {
        // Burn case
        (balance0, balance1) = _burnStarkware(
          fundingArgs.lpAmount,
          balance0,
          balance1,
          // These need to be in the right order
          token0Amount,
          token1Amount,
          exchangeAddress,
          hasSwap
        );
        // Apply balanceLp update
        balanceLp = initialBalanceLp - fundingArgs.lpAmount;
      }
    }

    if (hasSwap) {
      require(swapArgs.tokenUserSell != 0, 'DVF: INVALID_SWAP_TOKEN_TO');

      (balance0, balance1) = _swapStarkWare(swapArgs, balance0, balance1, exchangeAddress);

      // If it was swap only
      if (fundingArgs.lpAmount == 0) {
        starkWareState = 3;
      }
    }

    // Universal validation logic here
    universalStateTransition(initialBalanceLp, initialBalance0, initialBalance1, balanceLp, balance0, balance1);

    // Balances expected after sync is completed
    token0ExpectedBalance = balance0;
    token1ExpectedBalance = balance1;
  }

  function universalStateTransition(
    uint256 initialBalanceLp,
    uint256 initialBalance0,
    uint256 initialBalance1,
    uint256 balanceLp,
    uint256 balance0,
    uint256 balance1
  ) public pure returns (bool) {
    // Pre-quantize all numbers to avoid extra quantization calculation here
    // l2^2 × x0 × y0 <= x2 × y2 × l0^2
    require(
      balanceLp.square() * initialBalance0 * initialBalance1
      <=
      initialBalanceLp.square() * balance0 * balance1,
      'DVF: BAD_SYNC_TRANSITION'
    );

    return true;
  }

  function _mintStarkware(
    // All amounts are quantized
    uint256 lpAmount,
    uint256 balance0,
    uint256 balance1,
    uint256 token0Amount,
    uint256 token1Amount,
    address exchangeAddress,
    bool validateAmounts
  ) internal returns (uint256 finalBalance0, uint256 finalBalance1) {
    {
    uint baseLpAmount = lpQuantum.fromQuantized(lpAmount);
    uint _totalSupply = lpQuantum.toQuantizedUnsafe(totalSupply); 
    { // avoid stack errors

    /*
     * In case of mint only (no swap) we don't require mint to be optimal in
     * order to allow donations to the amm. So we skip validation here and
     * rely solely on validateStateTransition executed at the end of
     * syncStarkware. 
     * 
     * However in mint + swap case, we enforce an optimal mint here, so that the
     * contract cannot be exploited but inflating token0/token1 balance with
     * a mint (which never gets settled), and then extracting value by
     * settling only the swap stark order. This would be possible due to the fact 
     * that we cannot enforce all Stark orders created for the sync to be settled, 
     * and could be prevented if, int the future, StarkEx added support for multi 
     * asset orders/settlements.
     */
    if (validateAmounts) {
      uint liquidity = Math.min(token0Amount.mul(_totalSupply) / balance0, token1Amount.mul(_totalSupply) / balance1);
      require(liquidity == lpAmount, 'DVF_LIQUIDITY_REQUESTED_MISMATCH');
    }

    finalBalance0 = balance0.add(token0Amount);
    finalBalance1 = balance1.add(token1Amount);
    }

    _mint(address(this), baseLpAmount);
    syncLpChange = lpAmount;

    // now create L1 limit order
    // Must allow starkEx contract to transfer the tokens from this pair
    _approve(address(this), IUniswapV2Factory(factory).starkExContract(), baseLpAmount);
    }

    // Extracted into a function due to stack limit
    _mintStarkwareOrders(lpAmount, token0Amount, token1Amount, exchangeAddress);

    starkWareState = 1;
  }

  function _mintStarkwareOrders(
    uint256 lpAmount,
    uint256 token0Amount,
    uint256 token1Amount,
    address exchangeAddress
  ) private {
    IStarkEx starkEx = getStarkEx();
    uint256 vault = currentVault;
    starkEx.depositERC20ToVault(lpAssetId, vault, lpAmount);

    // Reassigning to registry, no new variables to limit stack
    uint lpAmountA = lpAmount / 2;
    uint localNonce = nonce;
    IStarkExOrderRegistry starkExOrderRegistry = getStarkExRegistry(starkEx);

    starkExOrderRegistry.registerLimitOrder(exchangeAddress, lpAssetId, token0AssetId,
    token0AssetId, lpAmountA, token0Amount, 0, vault, vault, vault, localNonce, unsignedInt22);

    uint lpAmountB = lpAmount - lpAmountA;
    starkExOrderRegistry.registerLimitOrder(exchangeAddress, lpAssetId, token1AssetId,
    token1AssetId, lpAmountB, token1Amount, 0, vault, vault, vault, localNonce, unsignedInt22);
  }

  function _burnStarkware(
    // All amounts are quantized
    uint256 lpAmount,
    uint256 balance0,
    uint256 balance1,
    uint256 token0Amount,
    uint256 token1Amount,
    address exchangeAddress,
    bool validateAmounts
  ) internal returns (uint256 finalBalance0, uint256 finalBalance1) {
    {

    /*
     * In case of burn only (no swap) we don't require burn to be optimal in
     * order to allow donations to the amm. So we skip validation here and
     * rely solely on validateStateTransition executed at the end of
     * syncStarkware. 
     * 
     * However in burn + swap case, we enforce an optimal burn here, so that the
     * contract cannot be exploited but inflating token0/token1 balance with
     * a burn (which never gets settled), and then extracting value by
     * settling only the swap stark order. This would be possible due to the fact 
     * that we cannot enforce all Stark orders created for the sync to be settled, 
     * and could be prevented if, int the future, StarkEx added support for multi 
     * asset orders/settlements.
     */
    if (validateAmounts) {
      uint _totalSupply = lpQuantum.toQuantizedUnsafe(totalSupply); // gas savings, must be defined here since totalSupply can update in _mintFee
      uint amount0 = lpAmount.mul(balance0) / _totalSupply; // using balances ensures pro-rata distribution
      uint amount1 = lpAmount.mul(balance1) / _totalSupply; // using balances ensures pro-rata distribution

      // Validate exact match
      require(amount0 == token0Amount, 'DVF: MIN_TOKEN_A');
      require(amount1 == token1Amount, 'DVF: MIN_TOKEN_B');
    }

    finalBalance0 = balance0 - token0Amount;
    finalBalance1 = balance1 - token1Amount;
    }

    // Reassigning to registry, no new variables to limit stack
    uint lpAmountA = lpAmount / 2;
    uint localNonce = nonce;
    uint256 vault = currentVault;

    IStarkExOrderRegistry starkExOrderRegistry = getStarkExRegistry(getStarkEx());

    starkExOrderRegistry.registerLimitOrder(exchangeAddress, token0AssetId, lpAssetId,
    lpAssetId, token0Amount, lpAmountA, 0, vault, vault, vault, localNonce, unsignedInt22);

    uint lpAmountB = lpAmount - lpAmountA;
    starkExOrderRegistry.registerLimitOrder(exchangeAddress, token1AssetId, lpAssetId,
    lpAssetId, token1Amount, lpAmountB, 0, vault, vault, vault, localNonce, unsignedInt22);

    syncLpChange = lpAmount;

    starkWareState = 2;
  }

  function settleStarkWare() external operatorOnly returns(bool) {
    uint16 _starkWareState = starkWareState; // gas savings
    require(_starkWareState > 0, 'DVF: NOTHING_TO_SETTLE');

    IStarkEx starkEx = getStarkEx();
    if (!isLayer2Live) {
      withdrawAllFromVaultIn(starkEx, token0, token0Quanatum, token0AssetId, currentVault);
      withdrawAllFromVaultIn(starkEx, token1, token1Quanatum, token1AssetId, currentVault);
    }
    {
      // withdraw from vault into this address and then burn it
      withdrawAllFromVaultIn(starkEx, address(this), lpQuantum, lpAssetId, currentVault);
      uint contractBalance = balanceOf[address(this)];
      if (_starkWareState == 2) {
        // Ensure we were paid enough LP for burn
        require(contractBalance >= lpQuantum.fromQuantized(syncLpChange), 'DVF: NOT_ENOUGH_LP');
      }

      if (contractBalance > 0) {
        _burn(address(this), contractBalance);
      }
    }

    // Ensure we have the expected ratio matching totalLoans
    { // block to avoid stack limit exceptions
      (uint balance0, uint balance1) = balances();
      balance0 = token0Quanatum.toQuantizedUnsafe(balance0);
      balance1 = token1Quanatum.toQuantizedUnsafe(balance1);
      // We can also use the universal state transition check here, however that would
      // open us to partial settlement of L1 orders
      require(balance0 >= token0ExpectedBalance && balance1 >= token1ExpectedBalance, 'DVF: INVALID_TOKEN_AMOUNTS');
    }

    _clearStarkwareStates();
    sync();
    return true;
  }

  function abortStarkware() external operatorOnly returns(uint256 newVaultId) {
    require(starkWareState != 0, 'DVF: NOT_IN_SYNC');
    require(isLayer2Live, 'DVF: NOT_IN_L2');
    
    _withdrawAllFromVault();

    // burn any extra LP tokens minted for orders
    _burn(address(this), balanceOf[address(this)]);

    // Withdraw all funds
    _clearStarkwareStates();

    // Increment currentVault, which, together with withdrawal of all funds
    // from the original vault, prevents L1 orders created for the sync being aborted 
    // from ever being settled.
    newVaultId  = ++currentVault;

    // Deposit funds back into new vaults
    // Will use the new currentVault
    // temporarily switch L2 mode off as balances
    // are withdrawn into this contract address
    isLayer2Live = false;
    _depositAllFundsToStarkware();
    isLayer2Live = true;

    sync();
  }

  function _clearStarkwareStates() private {
    token0ExpectedBalance = 0;
    token1ExpectedBalance = 0;
    syncLpChange = 0;
    starkWareState = 0;
    setLock(false);
  }

  function _withdrawAllFromVault() private {
    IStarkEx starkEx = getStarkEx();
    uint vaultId = currentVault;
    withdrawAllFromVaultIn(starkEx, address(this), lpQuantum, lpAssetId, vaultId);
    withdrawAllFromVaultIn(starkEx, token0, token0Quanatum, token0AssetId, vaultId);
    withdrawAllFromVaultIn(starkEx, token1, token1Quanatum, token1AssetId, vaultId);
  }

  function withdrawAllFromVaultIn(IStarkEx starkEx, address token, uint _quantum, uint _assetId, uint vaultId) private {
    uint balance = starkEx.getQuantizedVaultBalance(address(this), _assetId, vaultId);
    withdrawStarkWare(starkEx, token, _quantum, _assetId, vaultId, balance);
  }

  function withdrawStarkWare(IStarkEx starkEx, address token, uint _quantum, uint _assetId, uint vaultId, uint quantizedAmount) internal {
    if (quantizedAmount <= 0) {
      return;
    }

    starkEx.withdrawFromVault(_assetId, vaultId, quantizedAmount);

    // Wrap in WETH if it was ETH
    if (token == weth) {
      // Must unwrap and deposit ETH
      uint amount = _quantum.fromQuantized(quantizedAmount);
      IWETH(weth).deposit{value: amount}();
    } 
  }

  /**
   * Restrict for L2
  */
  function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) public override l2OperatorOnly {
    super.swap(amount0Out, amount1Out, to, data);
  }

  function mint(address to) public override l2OperatorOnly returns (uint liquidity) {
    return super.mint(to);
  }

  function burn(address to) public override l2OperatorOnly returns (uint amount0, uint amount1) {
    return super.burn(to);
  }

  function verifyTransfer(address to, uint value) private view {
    require(!(isLayer2Live && !isOperator() && to == address(this)), "DVF_AMM: CANNOT_MINT_L2");
    require(value % lpQuantum == 0, "DVF_AMM: AMOUNT_NOT_DIVISIBLE_BY_QUANTUM");
  }

  /**
  * @dev Transfer your tokens
  * For burning tokens transfers are done to this contact address first and they must be queued in L2 `queueBurnDirect`
  * User to User transfers follow standard ERC-20 pattern
  */
  function transfer(address to, uint value) public override returns (bool) { 
    verifyTransfer(to, value);

    require(super.transfer(to, value), "DVF_AMM: TRANSFER_FAILED");
    return true;
  }

  /**
  * @dev Transfer approved tokens
  * For burning tokens transfers are done to this contact address first and they must be queued in L2 `queueBurn`
  * User to User transfers follow standard ERC-20 pattern
  */
  function transferFrom(address from, address to, uint value) public override returns (bool) {
    verifyTransfer(to, value);

    require(super.transferFrom(from, to, value), "DVF_AMM: TRANSFER_FAILED");
    return true;
  }

  function skim(address to) public override l2OperatorOnly {
    super.skim(to);
  }

  function sync() public override l2OperatorOnly {
    super.sync();
  }

  function toggleLayer2(bool _isLayer2Live) external operatorOnly {
    require(!isLocked(), 'LOCKED');
    require(isLayer2Live != _isLayer2Live, 'DVF: NO_STATE_CHANGE');
    _toggleLayer2(_isLayer2Live);
  }

  function _toggleLayer2(bool _isLayer2Live) internal override {
    uint balance0;
    uint balance1;
    if (_isLayer2Live) {
      require(lpAssetId != 0, 'DVF_AMM: NOT_SETUP_FOR_L2');
      require(!IUniswapV2Factory(factory).isStarkExContractFrozen(), 'DVF_AMM: STARKEX_FROZEN');

      // Activate Layer2, move all funds to Starkware
      (balance0, balance1) = _depositAllFundsToStarkware();
      // LP not moved as this contract should not be holding LP tokens
    } else {
      // Deactivate Layer2, withdraw all funds
      _withdrawAllFromVault();
      _burn(address(this), balanceOf[address(this)]);
      (balance0, balance1) = balances();
    }

    isLayer2Live = _isLayer2Live;
    setLock(false);
    super.sync();
    // Fetch balances again since storage has changed
    (balance0, balance1) = balances();

    emit Layer2StateChange(_isLayer2Live, balance0, balance1, totalSupply);
  }

  function _depositAllFundsToStarkware() internal returns (uint balance0, uint balance1) {
    IStarkEx starkEx = getStarkEx();
    (balance0, balance1) = balances();
    TransferHelper.safeApprove(token0, address(starkEx), balance0);
    TransferHelper.safeApprove(token1, address(starkEx), balance1);
    depositStarkWare(starkEx, token0, token0Quanatum, token0AssetId, currentVault, token0Quanatum.toQuantizedUnsafe(balance0));
    depositStarkWare(starkEx, token1, token1Quanatum, token1AssetId, currentVault, token1Quanatum.toQuantizedUnsafe(balance1));
  }

  function emergencyDisableLayer2() external {
    require(isLayer2Live, 'DVF_AMM: LAYER2_ALREADY_DISABLED');
    require(IUniswapV2Factory(factory).isStarkExContractFrozen(), 'DVF_AMM: STARKEX_NOT_FROZEN');
    isLayer2Live = false;
    setLock(false);
  }

  function starkWareInfo(uint _assetId) public view returns (address _token, uint _quantum) {
    if (_assetId == lpAssetId) {
      return (address(this), lpQuantum);
    } else if (_assetId == token0AssetId) {
      return (token0, token0Quanatum);
    } else if (_assetId == token1AssetId) {
      return (token1, token1Quanatum);
    } 

    require(false, 'DVF_NO_STARKWARE_INFO');
  }

  function setLock(bool state) internal {
    unlocked = state ? 0 : 1;
  }

  function isLocked() internal view returns (bool) {
    return unlocked == 0;
  }

  // TESTING
  function balancesPub() external view returns (uint b0, uint b1, uint112 r0, uint112 r1, uint out0, uint out1, uint loans) {
    (b0, b1) = balances();
    (r0, r1,) = getReserves();
    out0 = token0ExpectedBalance;
    out1 = token1ExpectedBalance;
    loans = syncLpChange;
  }

  function token_info() external view returns (uint _lpAssetId, uint _token0AssetId, uint _token1AssetId) {
    return (lpAssetId, token0AssetId, token1AssetId);
  }

  function balances() internal view override returns (uint balance0, uint balance1) {
    if (isLayer2Live) {
      IStarkEx starkEx = getStarkEx();
      balance0 = starkEx.getVaultBalance(address(this), token0AssetId, currentVault);
      balance1 = starkEx.getVaultBalance(address(this), token1AssetId, currentVault);
    } else {
      return super.balances();
    }
  }

  /**
   * @dev Used by EmergencyWithdrawal to burn the tokens by operator as requested by users
  */
  function burnAndTransferToThis(address from, uint lptokenAmount) 
    internal 
    override 
    returns (uint token0Amount, uint token1Amount) 
  {
    (uint balance0, uint balance1) = balances();
    require(balanceOf[from] >= lptokenAmount, 'NOT_ENOUGH_LP_LIQUIDITY');

    {
    uint _totalSupply = totalSupply; 
    token0Amount = lptokenAmount.mul(balance0) / _totalSupply;
    token1Amount = lptokenAmount.mul(balance1) / _totalSupply;
    }

    if (isLayer2Live) {
      // Must withdraw tokens from the StarkEx vault
     IStarkEx starkEx = getStarkEx();
     withdrawStarkWare(starkEx, token0, token0Quanatum, token0AssetId, currentVault, token0Quanatum.toQuantizedUnsafe(token0Amount));
     withdrawStarkWare(starkEx, token1, token1Quanatum, token1AssetId, currentVault, token1Quanatum.toQuantizedUnsafe(token1Amount));
     // Truncate since quantization will not take dust into account
     token0Amount = token0Quanatum.truncate(token0Amount);
     token1Amount = token1Quanatum.truncate(token1Amount);
    }

    _burn(from, lptokenAmount);
  }

  function authorizeWithdrawals(uint blockNumberTo, uint lpAmount, bool validateId) external override operatorOnly {
    _authorizeWithdrawals(blockNumberTo, lpAmount, validateId);
  }

  function setWithdrawalDelay(uint newDelay) external operatorOnly {
    _setWithdrawalDelay(newDelay);
  }
}
