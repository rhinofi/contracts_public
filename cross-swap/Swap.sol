// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "./EIP712Upgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "./Storage.sol";
import "./UserWallet.sol";
import "./Relayer.sol";
import "./IDVFDepositContract.sol";

abstract contract Swap is Storage, UserWallet {
  using SafeERC20Upgradeable for IERC20Upgradeable;

  bytes32 public constant DEVERSIFI_GATEWAY = "DeversifiGateway";

  bytes32 public constant _SWAP_TYPEHASH =
   keccak256("Swap(address user,bytes32 swapGateway,address tokenFrom,address tokenTo,uint256 amountFrom,uint256 minAmountTo,uint256 nonce,uint256 deadline,uint256 chainId)");

  struct SwapConstraints {
    address user;
    bytes32 swapGateway;
    address tokenFrom;
    address tokenTo;
    uint256 amountFrom;
    uint256 minAmountTo;
    uint256 nonce;
    uint256 deadline;
    uint256 chainId;
    // maxFeeTo set as extra argument in calls but not part of the EIP712 signature
    uint256 maxFeeTo;
    address bridge;
  }

  enum BridgeDirection {
    XCHAIN_TO_XCHAIN,
    XCHAIN_TO_BRIDGE,
    BRIDGE_TO_XCHAIN,
    BRIDGE_TO_BRIDGE
  }

  bytes32 public constant _SWAPV3_TRANSACTION_TYPEHASH =
    keccak256("SwapV3(address user,bytes32 swapGateway,address[] tokensFrom,address[] tokensTo,uint256[] amountsFrom,uint256[] minAmountsTo,uint256 nonce,uint256 deadline,uint256 chainId,address bridge)");


  struct SwapV3Constraints {
    address user;
    bytes32 swapGateway;
    address[] tokensFrom;
    address[] tokensTo;
    uint256[] amountsFrom;
    uint256[] minAmountsTo;
    // maxFeeTo set as extra argument in calls but not part of the EIP712 signature
    uint256[] maxFeesTo;
    uint256 nonce;
    uint256 deadline;
    uint256 chainId;
    address bridge;
  }

  event SwapPerformed(bytes32 swapId, bytes32 swapGateway, address indexed user,
   address indexed tokenFrom, uint256 amountFrom, address indexed tokenTo,
   uint256 amountTo, uint256 amountToFee, bool fundsBridged);

  event SwapPerformedV3(bytes32 swapId, bytes32 swapGateway, address indexed user,
   address[] tokensFrom, uint256[] amountsFrom, address[] tokensTo,
   uint256[] amountsTo, uint256[] amountsToFee, bool fundsBridged);

  event BridgeRebalancedV3(
    address[] tokensFrom, uint256[] amountsFrom,
    address[] tokensTo, uint256[] amountsTo);

  error QuoteV3(uint256[] amountsToUser, uint256[] amountsToFee);

  // solhint-disable-next-line func-name-mixedcase
  function __Swap_init(
    address _admin,
    address _paraswap,
    address _paraswapTransferProxy
  ) internal onlyInitializing {
    paraswap = _paraswap;
    paraswapTransferProxy = _paraswapTransferProxy;
    _createRelayerContract(_admin);
    __EIP712_init("RhinoFi Cross Chain Swap", "1");
    __UserWallet_Init();
  }

  function _createRelayerContract(
    address _admin
  ) internal {
    relayer = new Relayer();
    relayer.grantRole(DEFAULT_ADMIN_ROLE, _admin);
  }

  function createRelayerContract() 
    external onlyRole(DEFAULT_ADMIN_ROLE) {
    _createRelayerContract(msg.sender);
  }

  function setRelayerAddress(
    address _relayer
  ) external onlyRole(DEFAULT_ADMIN_ROLE) {
    relayer = Relayer(_relayer);
    relayer.grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    relayer.grantRole(relayer.OPERATOR_ROLE(), address(this));
  }

  function isBridgingFrom(BridgeDirection bridgeDirection) internal pure returns (bool) {
    return bridgeDirection == BridgeDirection.BRIDGE_TO_XCHAIN || bridgeDirection == BridgeDirection.BRIDGE_TO_BRIDGE;
  }

  function isBridgingTo(BridgeDirection bridgeDirection) internal pure returns (bool) {
    return bridgeDirection == BridgeDirection.XCHAIN_TO_BRIDGE || bridgeDirection == BridgeDirection.BRIDGE_TO_BRIDGE;
  }

  function executeSwapV3WithSignature(
    address vm,
    SwapV3Constraints memory swapV3Constraints,
    bytes32 swapId,
    bytes memory signature,
    bytes calldata data
  ) external onlyRole(OPERATOR_ROLE) withUniqueId(swapId) {
    ensureDeadline(swapV3Constraints.deadline);

    verifySwapV3Signature(swapV3Constraints, signature);

    bool fundsBridged = swapV3Constraints.swapGateway == DEVERSIFI_GATEWAY;

    (uint256[] memory amountsToUser, uint256[] memory amountsToFee) = 
      performSwapV3(
        vm,
        data,
        swapV3Constraints,
        fundsBridged ? BridgeDirection.XCHAIN_TO_BRIDGE : BridgeDirection.XCHAIN_TO_XCHAIN
      );

    emit SwapPerformedV3(swapId, swapV3Constraints.swapGateway, swapV3Constraints.user, swapV3Constraints.tokensFrom,
     swapV3Constraints.amountsFrom, swapV3Constraints.tokensTo, amountsToUser, amountsToFee, fundsBridged);
  }

  function executeSwapV3Quote(
    address vm,
    SwapV3Constraints memory swapV3Constraints,
    bytes calldata data,
    bool bridgeFrom
  ) external onlyRole(OPERATOR_ROLE) {

    // Transfer tokens to the VM
    for(uint i=0; i<swapV3Constraints.tokensFrom.length;i++) {
      if(bridgeFrom) {
        transferLiquidityFromBridge(
          swapV3Constraints.tokensFrom[i],
          swapV3Constraints.amountsFrom[i],
          vm,
          swapV3Constraints.bridge);
      } else {
        IERC20Upgradeable(swapV3Constraints.tokensFrom[i]).safeTransfer(vm, swapV3Constraints.amountsFrom[i]);
      }
    }

    bool bridgeTo = swapV3Constraints.swapGateway == DEVERSIFI_GATEWAY;
    // address where the destination tokens are going to be credited
    address destinationOfTokensAddress = 
      bridgeTo ? 
        address(swapV3Constraints.bridge) : 
        address(this);

    uint256[] memory amountsToUser = balancesOf(destinationOfTokensAddress, swapV3Constraints.tokensTo);
    uint256[] memory amountsToFee = new uint256[](amountsToUser.length);

    // execute all vm calldata
    Relayer(relayer).relay(vm,data);

    // credit for the balance differences of the specified tokens
    for(uint i=0; i<swapV3Constraints.tokensTo.length;i++) {
      amountsToUser[i] = IERC20Upgradeable(swapV3Constraints.tokensTo[i]).balanceOf(destinationOfTokensAddress) - amountsToUser[i];
      amountsToFee[i] = amountsToUser[i] - swapV3Constraints.minAmountsTo[i];
      // Fee is expresses as a max amount. The rest (ex: positive slippage) goes to the user
      // This logic should allow an higher success rate while the amounts quoted to users remain attractive.
      amountsToFee[i] = amountsToFee[i] > swapV3Constraints.maxFeesTo[i] ? swapV3Constraints.maxFeesTo[i] : amountsToFee[i];

      // Deduct fees from the amount that the user will receive
      amountsToUser[i] = amountsToUser[i] - amountsToFee[i];
    }

    revert QuoteV3 ({
      amountsToUser: amountsToUser,
      amountsToFee: amountsToFee
    });
  }

  function transferLiquidityFromBridge(
    address token,
    uint256 amount,
    address to,
    address bridge
  ) internal {
    IDVFDepositContract(bridge).removeFunds(token, to, amount);
  }

  function transferLiquidityFromBridge(
    address[] memory tokens,
    uint256[] memory amounts,
    address to,
    address bridge
  ) internal {
    for(uint i=0; i<tokens.length;i++) {
      transferLiquidityFromBridge(tokens[i], amounts[i], to, bridge);
    }
  }

  function executeSwapV3BridgeRebalance(
    address vm,
    SwapV3Constraints memory swapV3Constraints,
    bytes calldata data
  ) external onlyRole(LIQUIDITY_SPENDER_ROLE) {
      ensureDeadline(swapV3Constraints.deadline);
      (uint256[] memory amountsToUser, ) = 
        performSwapV3(
          vm,
          data,
          swapV3Constraints,
          BridgeDirection.BRIDGE_TO_BRIDGE
        );
      emit BridgeRebalancedV3(
        swapV3Constraints.tokensFrom, swapV3Constraints.amountsFrom,
        swapV3Constraints.tokensTo, amountsToUser);
  }

  function executeSwapV3WithSelfLiquidity(
    address vm,
    SwapV3Constraints memory swapV3Constraints,
    bytes32 swapId,
    bytes calldata data
  ) external onlyRole(LIQUIDITY_SPENDER_ROLE) withUniqueId(swapId) {
    ensureDeadline(swapV3Constraints.deadline);
    (uint256[] memory amountsToUser, uint256[] memory amountsToFee) = 
      performSwapV3(
        vm,
        data,
        swapV3Constraints,
        BridgeDirection.BRIDGE_TO_XCHAIN
      );
    emit SwapPerformedV3(swapId, swapV3Constraints.swapGateway, swapV3Constraints.user, swapV3Constraints.tokensFrom,
     swapV3Constraints.amountsFrom, swapV3Constraints.tokensTo, amountsToUser, amountsToFee, false);
  }

  function balancesOf(
    address contractAddress,
    address[] memory tokens
  ) internal view returns (uint256[] memory amounts) {
    amounts = new uint256[](tokens.length);
    for(uint i=0; i<tokens.length;i++) {
      amounts[i] = IERC20Upgradeable(tokens[i]).balanceOf(contractAddress);
    }
    return amounts;
  }

  function executeSwapWithSignature(
    SwapConstraints calldata swapConstraints,
    bytes32 swapId,
    bytes memory signature,
    bytes calldata data
  ) external onlyRole(OPERATOR_ROLE) withUniqueId(swapId) {
    ensureDeadline(swapConstraints.deadline);

    verifySwapSignature(swapConstraints, signature);

    // Wether we must bridge the received tokens back to the bridge contract
    bool fundsBridged = swapConstraints.swapGateway == DEVERSIFI_GATEWAY;

    (,uint256 amountToUser, uint256 amountToFee) = 
      performSwap(
        swapConstraints,
        data,
        fundsBridged ? 
          BridgeDirection.XCHAIN_TO_BRIDGE : 
          BridgeDirection.XCHAIN_TO_XCHAIN
      );

    emit SwapPerformed(swapId, swapConstraints.swapGateway, swapConstraints.user, swapConstraints.tokenFrom,
     swapConstraints.amountFrom, swapConstraints.tokenTo, amountToUser, amountToFee, fundsBridged);
  }

  function executeSwapWithSelfLiquidity(
    SwapConstraints calldata swapConstraints,
    bytes32 swapId,
    bytes calldata data
  ) external onlyRole(LIQUIDITY_SPENDER_ROLE) withUniqueId(swapId) {
    ensureDeadline(swapConstraints.deadline);

    (,uint256 amountToUser, uint256 amountToFee) = 
      performSwap(
        swapConstraints,
        data,
        BridgeDirection.BRIDGE_TO_XCHAIN
      );

    emit SwapPerformed(swapId, bytes32(0), swapConstraints.user, swapConstraints.tokenFrom, swapConstraints.amountFrom,
     swapConstraints.tokenTo, amountToUser, amountToFee, false);
  }

  function balancesOf(
    address[] memory tokens
  ) internal view returns (uint256[] memory amounts) {
    amounts = new uint256[](tokens.length);
    for(uint i=0; i<tokens.length;i++) {
      amounts[i] = _contractBalance(tokens[i]);
    }
    return amounts;
  }
  function performSwapV3(
    address vm,
    bytes calldata data,
    SwapV3Constraints memory swapV3Constraints,
    BridgeDirection bridgeDirection
  ) private returns(uint256[] memory amountsToUser, uint256[] memory amountsToFee) {

    require(
      swapV3Constraints.tokensFrom.length == swapV3Constraints.amountsFrom.length,
      "TOKENS_FROM_AMOUNT_LENGTH_MISMATCH");
    require(
      swapV3Constraints.tokensTo.length == swapV3Constraints.minAmountsTo.length,
      "TOKENS_TO_AMOUNT_LENGTH_MISMATCH");
    require(
      swapV3Constraints.minAmountsTo.length == swapV3Constraints.maxFeesTo.length,
      "MAX_FEES_TO_AMOUNT_LENGTH_MISMATCH");

    // Fund the VM with bridge liquidity or xchain tokens
    if(isBridgingFrom(bridgeDirection)) {
      transferLiquidityFromBridge(
        swapV3Constraints.tokensFrom,
        swapV3Constraints.amountsFrom,
        vm,
        swapV3Constraints.bridge);
    } else {
      // Transfer tokens to the VM
      for(uint i=0; i<swapV3Constraints.tokensFrom.length;++i) {
        _decreaseBalance(swapV3Constraints.tokensFrom[i], swapV3Constraints.user, swapV3Constraints.amountsFrom[i]);
        IERC20Upgradeable(swapV3Constraints.tokensFrom[i]).safeTransfer(vm, swapV3Constraints.amountsFrom[i]);
        _accountingSanityCheck(swapV3Constraints.tokensFrom[i], "SWAPV3_ACCOUNTING_FROM_FAILURE");
        emitBalanceUpdated(swapV3Constraints.user, swapV3Constraints.tokensFrom[i]);
      }
    }

    // address where the destination tokens are going to be credited
    address destinationOfTokensAddress = 
      isBridgingTo(bridgeDirection) ? 
        address(swapV3Constraints.bridge) : 
        address(this);

    // at this point the VM is funded
    // before executing the transaction we check the balances of the bridge contract when using bridge funds
    // or the balances of the cross-swap contract when using cross-swap funds

    amountsToUser = balancesOf(destinationOfTokensAddress, swapV3Constraints.tokensTo);

    amountsToFee = new uint256[](amountsToUser.length);

    // execute all vm calldata
    Relayer(relayer).relay(vm,data);

    // credit for the balance differences of the specified tokens
    for(uint i=0; i<swapV3Constraints.tokensTo.length;++i) {

      amountsToUser[i] = IERC20Upgradeable(swapV3Constraints.tokensTo[i]).balanceOf(destinationOfTokensAddress) - amountsToUser[i];

      amountsToFee[i] = amountsToUser[i] - swapV3Constraints.minAmountsTo[i];
      // Fee is expresses as a max amount. The rest (ex: positive slippage) goes to the user
      // This logic should allow an higher success rate while the amounts quoted to users remain attractive.
      amountsToFee[i] = amountsToFee[i] > swapV3Constraints.maxFeesTo[i] ? swapV3Constraints.maxFeesTo[i] : amountsToFee[i];

      // Deduct fees from the amount that the user will receive
      amountsToUser[i] = amountsToUser[i] - amountsToFee[i];

      if(!isBridgingTo(bridgeDirection)) {
          // Funds can only be credited to the user when the destination is the cross-swap contract
          // Credit the user with the received amount
          _increaseBalance(swapV3Constraints.tokensTo[i], swapV3Constraints.user, amountsToUser[i]);
          _increaseBalance(swapV3Constraints.tokensTo[i], address(this), amountsToFee[i]);
          emitBalanceUpdated(swapV3Constraints.user, swapV3Constraints.tokensTo[i]);
          emitBalanceUpdated(address(this), swapV3Constraints.tokensTo[i]);
          _accountingSanityCheck(swapV3Constraints.tokensTo[i], "SWAPV3_ACCOUNTING_TO_FAILURE");
      }

      require(amountsToUser[i] >= swapV3Constraints.minAmountsTo[i], "LOWER_THAN_MIN_AMOUNT_TO");
    }
  }

  function performSwap(
    SwapConstraints memory swapConstraints,
    bytes calldata data,
    BridgeDirection bridgeDirection
  ) private returns(uint256 tokenFromAmount, uint256 amountToUser, uint256 amountToFee) {

    if(isBridgingFrom(bridgeDirection)) {
      // transfer the input token from bridge to cross-swap contract
      transferLiquidityFromBridge(
        swapConstraints.tokenFrom,
        swapConstraints.amountFrom,
        address(this),
        swapConstraints.bridge
      );
    }

    tokenFromAmount = _contractBalance(swapConstraints.tokenFrom);
    // Using amountToUser name all the way in order to use a single variable
    amountToUser = _contractBalance(swapConstraints.tokenTo);

    // Only approve one token for the max amount
    IERC20Upgradeable(swapConstraints.tokenFrom).safeApprove(paraswapTransferProxy, swapConstraints.amountFrom);
    // Do swap
    // Arbitary call, must validate the state after
    safeExecuteOnParaswap(data);

    // After swap, reuse variables to save stack space
    tokenFromAmount = tokenFromAmount - _contractBalance(swapConstraints.tokenFrom);
    amountToUser = _contractBalance(swapConstraints.tokenTo) - amountToUser;

    require(tokenFromAmount <= swapConstraints.amountFrom, "HIGHER_THAN_AMOUNT_FROM");
    require(amountToUser >= swapConstraints.minAmountTo, "LOWER_THAN_MIN_AMOUNT_TO");

    amountToFee = amountToUser - swapConstraints.minAmountTo;
    // Fee is expresses as a max amount. The rest (ex: positive slippage) goes to the user in the MVP.
    // This logic should allow an higer success rate while the amounts quoted to users remain attractive.
    amountToFee = amountToFee > swapConstraints.maxFeeTo ? swapConstraints.maxFeeTo : amountToFee;
    // Final actual value of this variable
    amountToUser = amountToUser - amountToFee;

    // Only deduct to the user when it's using its own funds
    if(!isBridgingFrom(bridgeDirection)) {
      _decreaseBalance(swapConstraints.tokenFrom, swapConstraints.user, tokenFromAmount);
    }

    if(isBridgingTo(bridgeDirection)) {
      // transfer back the received tokens to bridge contract
      IERC20Upgradeable(swapConstraints.tokenTo).safeTransfer(swapConstraints.bridge, amountToUser);
    } else {
      // only credit balances when the destination is the cross-swap contract
      _increaseBalance(swapConstraints.tokenTo, swapConstraints.user, amountToUser);
      _increaseBalance(swapConstraints.tokenTo, address(this), amountToFee);
      emitBalanceUpdated(swapConstraints.user, swapConstraints.tokenTo);
      emitBalanceUpdated(address(this), swapConstraints.tokenTo);
    }
    _accountingSanityCheck(swapConstraints.tokenFrom, "SWAPV1_ACCOUNTING_FROM_FAILURE");
    _accountingSanityCheck(swapConstraints.tokenTo, "SWAPV1_ACCOUNTING_TO_FAILURE");

    emitBalanceUpdated(swapConstraints.user, swapConstraints.tokenFrom);
    emitBalanceUpdated(address(this), swapConstraints.tokenFrom); 

    // Ensure any amount not spent is disallowed
    IERC20Upgradeable(swapConstraints.tokenFrom).safeApprove(paraswapTransferProxy, 0);
  }

  function safeExecuteOnParaswap(
    bytes calldata _data
  ) private {
    AddressUpgradeable.functionCall(paraswap, _data, "PARASWAP_CALL_FAILED");
  }

  function verifySwapSignature(
    SwapConstraints calldata swapConstraints,
    bytes memory signature
  ) private {
    require(swapConstraints.nonce > userNonces[swapConstraints.user], "NONCE_ALREADY_USED");
    require(swapConstraints.chainId == block.chainid, "INVALID_CHAIN");

    bytes32 structHash = _hashTypedDataV4(keccak256(
      abi.encode(
        _SWAP_TYPEHASH,
        swapConstraints.user,
        swapConstraints.swapGateway,
        swapConstraints.tokenFrom,
        swapConstraints.tokenTo,
        swapConstraints.amountFrom,
        swapConstraints.minAmountTo,
        swapConstraints.nonce,
        swapConstraints.deadline,
        swapConstraints.chainId
      )
    ));

    require(
      SignatureChecker.isValidSignatureNow(swapConstraints.user, structHash, signature),
      "INVALID_SIGNATURE");

    userNonces[swapConstraints.user] = swapConstraints.nonce;
  }

  function verifySwapV3Signature(
    SwapV3Constraints memory swapV3Constraints,
    bytes memory signature
  ) private {
    require(swapV3Constraints.nonce > userNonces[swapV3Constraints.user], "NONCE_ALREADY_USED");
    require(swapV3Constraints.chainId == block.chainid, "INVALID_CHAIN");

    bytes32 structHash = _hashTypedDataV4(keccak256(
      abi.encode(
        _SWAPV3_TRANSACTION_TYPEHASH,
        swapV3Constraints.user,
        swapV3Constraints.swapGateway,
        keccak256(abi.encodePacked(swapV3Constraints.tokensFrom)),
        keccak256(abi.encodePacked(swapV3Constraints.tokensTo)),
        keccak256(abi.encodePacked(swapV3Constraints.amountsFrom)),
        keccak256(abi.encodePacked(swapV3Constraints.minAmountsTo)),
        swapV3Constraints.nonce,
        swapV3Constraints.deadline,
        swapV3Constraints.chainId,
        swapV3Constraints.bridge
      )
    ));

    require(
      SignatureChecker.isValidSignatureNow(swapV3Constraints.user, structHash, signature),
      "INVALID_SIGNATURE");

    userNonces[swapV3Constraints.user] = swapV3Constraints.nonce;
  }
}