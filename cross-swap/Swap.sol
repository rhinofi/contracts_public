// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "./EIP712Upgradeable.sol";
import "./libs/ECDSAUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "./Storage.sol";
import "./UserWallet.sol";
import "./Relayer.sol";

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
  }

 bytes32 public constant _SWAPV2_TRANSACTION_TYPEHASH =
   keccak256("SwapV2(address user,bytes32 swapGateway,address[] tokensFrom,address[] tokensTo,uint256[] amountsFrom,uint256[] minAmountsTo,uint256 nonce,uint256 deadline,uint256 chainId)");

  struct SwapV2Constraints {
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
  }

  event SwapPerformed(bytes32 swapId, bytes32 swapGateway, address indexed user,
   address indexed tokenFrom, uint256 amountFrom, address indexed tokenTo,
   uint256 amountTo, uint256 amountToFee, bool fundsBridged);

  event SwapPerformedV2(bytes32 swapId, bytes32 swapGateway, address indexed user,
   address[] tokensFrom, uint256[] amountsFrom, address[] tokensTo,
   uint256[] amountsTo, uint256[] amountsToFee, bool fundsBridged);

  error Quote(uint256[] amountsToUser, uint256[] amountsToFee);

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

  function executeSwapV2WithSignature(
    address vm,
    SwapV2Constraints memory swapV2Constraints,
    bytes32 swapId,
    bytes memory signature,
    bytes calldata data
  ) external onlyRole(OPERATOR_ROLE) withUniqueId(swapId) {
    ensureDeadline(swapV2Constraints.deadline);

    verifySwapV2Signature(swapV2Constraints, signature);

    (uint256[] memory amountsToUser, uint256[] memory amountsToFee) = 
      performSwapV2(
        vm,
        data,
        swapV2Constraints
      );

    // // based on swapGateway decide to tunnel the funds back into
    // // Our pool or not, this can be done inside performSwap as well
    // // to save ~3 extra addition/subtraction
    bool fundsBridged = swapV2Constraints.swapGateway == DEVERSIFI_GATEWAY;
    if (fundsBridged) {
      transfer(swapV2Constraints.user, swapV2Constraints.tokensTo, address(this), amountsToUser);
    }

    emit SwapPerformedV2(swapId, swapV2Constraints.swapGateway, swapV2Constraints.user, swapV2Constraints.tokensFrom,
     swapV2Constraints.amountsFrom, swapV2Constraints.tokensTo, amountsToUser, amountsToFee, fundsBridged);
  }

  function executeSwapV2Quote(
    address vm,
    SwapV2Constraints memory swapV2Constraints,
    bytes calldata data
  ) external onlyRole(OPERATOR_ROLE) {

    uint256[] memory amountsToUser = balancesOf(swapV2Constraints.tokensTo);
    uint256[] memory amountsToFee = new uint256[](amountsToUser.length);

    // Transfer tokens to the VM
    for(uint i=0; i<swapV2Constraints.tokensFrom.length;i++) {
      IERC20Upgradeable(swapV2Constraints.tokensFrom[i]).safeTransfer(vm, swapV2Constraints.amountsFrom[i]);
    }

    // execute all vm calldata
    Relayer(relayer).relay(vm,data);

    // credit for the balance differences of the specified tokens
    for(uint i=0; i<swapV2Constraints.tokensTo.length;i++) {
      amountsToUser[i] = _contractBalance(IERC20Upgradeable(swapV2Constraints.tokensTo[i])) - amountsToUser[i];
      amountsToFee[i] = amountsToUser[i] - swapV2Constraints.minAmountsTo[i];
      // Fee is expresses as a max amount. The rest (ex: positive slippage) goes to the user
      // This logic should allow an higher success rate while the amounts quoted to users remain attractive.
      amountsToFee[i] = amountsToFee[i] > swapV2Constraints.maxFeesTo[i] ? swapV2Constraints.maxFeesTo[i] : amountsToFee[i];

      // Deduct fees from the amount that the user will receive
      amountsToUser[i] = amountsToUser[i] - amountsToFee[i];
    }

    revert Quote ({
      amountsToUser: amountsToUser,
      amountsToFee: amountsToFee
    });
  }

  function executeSwapV2WithSelfLiquidity(
    address vm,
    SwapV2Constraints memory swapV2Constraints,
    bytes32 swapId,
    bytes calldata data
  ) external onlyRole(OPERATOR_ROLE) withUniqueId(swapId) {
    ensureDeadline(swapV2Constraints.deadline);
    transfer(address(this), swapV2Constraints.tokensFrom, swapV2Constraints.user, swapV2Constraints.amountsFrom);
    (uint256[] memory amountsToUser, uint256[] memory amountsToFee) = 
      performSwapV2(
        vm,
        data,
        swapV2Constraints
      );
    emit SwapPerformedV2(swapId, swapV2Constraints.swapGateway, swapV2Constraints.user, swapV2Constraints.tokensFrom,
     swapV2Constraints.amountsFrom, swapV2Constraints.tokensTo, amountsToUser, amountsToFee, false);
  }

  function executeSwapWithSignature(
    SwapConstraints calldata swapConstraints,
    bytes32 swapId,
    bytes memory signature,
    bytes calldata data
  ) external onlyRole(OPERATOR_ROLE) withUniqueId(swapId) {
    ensureDeadline(swapConstraints.deadline);

    verifySwapSignature(swapConstraints, signature);

    (,uint256 amountToUser, uint256 amountToFee) = performSwap(swapConstraints.user, swapConstraints.tokenFrom, swapConstraints.tokenTo, swapConstraints.amountFrom, swapConstraints.minAmountTo, swapConstraints.maxFeeTo, data);

    // based on swapGateway decide to tunnel the funds back into
    // Our pool or not, this can be done inside performSwap as well
    // to save ~3 extra addition/subtraction
    bool fundsBridged = postSwap(swapConstraints.swapGateway, amountToUser, swapConstraints.tokenTo, swapConstraints.user);

    emit SwapPerformed(swapId, swapConstraints.swapGateway, swapConstraints.user, swapConstraints.tokenFrom,
     swapConstraints.amountFrom, swapConstraints.tokenTo, amountToUser, amountToFee, fundsBridged);
  }

  function executeSwapWithSelfLiquidity(
    SwapConstraints calldata swapConstraints,
    bytes32 swapId,
    bytes calldata data
  ) external onlyRole(LIQUIDITY_SPENDER_ROLE) withUniqueId(swapId) {
    ensureDeadline(swapConstraints.deadline);
    // Currently transfers from this contract's vault
    // We can also place them in operator's vault and use msg.sender
    transfer(address(this), swapConstraints.tokenFrom, swapConstraints.user, swapConstraints.amountFrom);
    (,uint256 amountToUser, uint256 amountToFee) = performSwap(swapConstraints.user, swapConstraints.tokenFrom, swapConstraints.tokenTo,
     swapConstraints.amountFrom, swapConstraints.minAmountTo, swapConstraints.maxFeeTo, data);

    emit SwapPerformed(swapId, bytes32(0), swapConstraints.user, swapConstraints.tokenFrom, swapConstraints.amountFrom,
     swapConstraints.tokenTo, amountToUser, amountToFee, false);
  }

  function postSwap(
    bytes32 swapGateway,
    uint256 receivedtokenAmount,
    address receivedToken,
    address user
  ) internal returns (bool fundsBridged) {
    if (swapGateway == DEVERSIFI_GATEWAY) {
      transfer(user, receivedToken, address(this), receivedtokenAmount);
      return true;
    }

    return false;
  }

  function balancesOf(
    address[] memory tokens
  ) internal view returns (uint256[] memory amounts) {
    amounts = new uint256[](tokens.length);
    for(uint i=0; i<tokens.length;i++) {
      amounts[i] = _contractBalance(IERC20Upgradeable(tokens[i]));
    }
    return amounts;
  }

  function performSwapV2(
    address vm,
    bytes calldata data,
    SwapV2Constraints memory swapV2Constraints
  ) private returns(uint256[] memory amountsToUser, uint256[] memory amountsToFee) {

    amountsToUser = balancesOf(swapV2Constraints.tokensTo);
    amountsToFee = new uint256[](amountsToUser.length);

    require(
      swapV2Constraints.tokensFrom.length == swapV2Constraints.amountsFrom.length,
      "TOKENS_FROM_AMOUNT_LENGTH_MISMATCH");
    require(
      swapV2Constraints.tokensTo.length == swapV2Constraints.minAmountsTo.length,
      "TOKENS_TO_AMOUNT_LENGTH_MISMATCH");
    require(
      swapV2Constraints.minAmountsTo.length == swapV2Constraints.maxFeesTo.length,
      "MAX_FEES_TO_AMOUNT_LENGTH_MISMATCH");

    // Transfer tokens to the VM
    for(uint i=0; i<swapV2Constraints.tokensFrom.length;i++) {
      _decreaseBalance(swapV2Constraints.tokensFrom[i], swapV2Constraints.user, swapV2Constraints.amountsFrom[i]);
      IERC20Upgradeable(swapV2Constraints.tokensFrom[i]).safeTransfer(vm, swapV2Constraints.amountsFrom[i]);
      _accountingSanityCheck(swapV2Constraints.tokensFrom[i], "SWAPV2_ACCOUNTING_FROM_FAILURE");
    }

    // execute all vm calldata
    Relayer(relayer).relay(vm,data);

    // credit for the balance differences of the specified tokens
    for(uint i=0; i<swapV2Constraints.tokensTo.length;i++) {
      amountsToUser[i] = _contractBalance(IERC20Upgradeable(swapV2Constraints.tokensTo[i])) - amountsToUser[i];
      amountsToFee[i] = amountsToUser[i] - swapV2Constraints.minAmountsTo[i];
      // Fee is expresses as a max amount. The rest (ex: positive slippage) goes to the user
      // This logic should allow an higher success rate while the amounts quoted to users remain attractive.
      amountsToFee[i] = amountsToFee[i] > swapV2Constraints.maxFeesTo[i] ? swapV2Constraints.maxFeesTo[i] : amountsToFee[i];

      // Deduct fees from the amount that the user will receive
      amountsToUser[i] = amountsToUser[i] - amountsToFee[i];

      _increaseBalance(swapV2Constraints.tokensTo[i], swapV2Constraints.user, amountsToUser[i]);
      _increaseBalance(swapV2Constraints.tokensTo[i], address(this), amountsToFee[i]);
 
      require(amountsToUser[i] >= swapV2Constraints.minAmountsTo[i], "LOWER_THAN_MIN_AMOUNT_TO");
      _accountingSanityCheck(swapV2Constraints.tokensTo[i], "SWAPV2_ACCOUNTING_TO_FAILURE");
    }
  }

  function performSwap(
    address user,
    address tokenFrom,
    address tokenTo,
    uint256 amountFrom,
    uint256 minAmountTo,
    uint256 maxFeeTo,
    bytes calldata data
  ) private returns(uint256 tokenFromAmount, uint256 amountToUser, uint256 amountToFee) {
    tokenFromAmount = _contractBalance(IERC20Upgradeable(tokenFrom));
    // Using amountToUser name all the way in order to use a single variable
    amountToUser = _contractBalance(IERC20Upgradeable(tokenTo));

    // Only approve one token for the max amount
    IERC20Upgradeable(tokenFrom).safeApprove(paraswapTransferProxy, amountFrom);
    // Do swap
    // Arbitary call, must validate the state after
    safeExecuteOnParaswap(data);

    // After swap, reuse variables to save stack space
    tokenFromAmount = tokenFromAmount - _contractBalance(IERC20Upgradeable(tokenFrom));
    amountToUser = _contractBalance(IERC20Upgradeable(tokenTo)) - amountToUser;

    require(tokenFromAmount <= amountFrom, "HIGHER_THAN_AMOUNT_FROM");
    require(amountToUser >= minAmountTo, "LOWER_THAN_MIN_AMOUNT_TO");

    amountToFee = amountToUser - minAmountTo;
    // Fee is expresses as a max amount. The rest (ex: positive slippage) goes to the user in the MVP.
    // This logic should allow an higer success rate while the amounts quoted to users remain attractive.
    amountToFee = amountToFee > maxFeeTo ? maxFeeTo : amountToFee;
    // Final actual value of this variable
    amountToUser = amountToUser - amountToFee;

    _decreaseBalance(tokenFrom, user, tokenFromAmount);
    _increaseBalance(tokenTo, user, amountToUser);
    _increaseBalance(tokenTo, address(this), amountToFee);
    _accountingSanityCheck(tokenFrom, "SWAPV1_ACCOUNTING_FROM_FAILURE");
    _accountingSanityCheck(tokenTo, "SWAPV1_ACCOUNTING_TO_FAILURE");

    // Ensure any amount not spent is disallowed
    IERC20Upgradeable(tokenFrom).safeApprove(paraswapTransferProxy, 0);
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

    address signer = ECDSAUpgradeable.recover(structHash, signature);
    require(signer == swapConstraints.user, "INVALID_SIGNATURE");

    userNonces[swapConstraints.user] = swapConstraints.nonce;
  }

  function verifySwapV2Signature(
    SwapV2Constraints memory swapV2Constraints,
    bytes memory signature
  ) private {
    require(swapV2Constraints.nonce > userNonces[swapV2Constraints.user], "NONCE_ALREADY_USED");
    require(swapV2Constraints.chainId == block.chainid, "INVALID_CHAIN");

    bytes32 structHash = _hashTypedDataV4(keccak256(
      abi.encode(
        _SWAPV2_TRANSACTION_TYPEHASH,
        swapV2Constraints.user,
        swapV2Constraints.swapGateway,
        keccak256(abi.encodePacked(swapV2Constraints.tokensFrom)),
        keccak256(abi.encodePacked(swapV2Constraints.tokensTo)),
        keccak256(abi.encodePacked(swapV2Constraints.amountsFrom)),
        keccak256(abi.encodePacked(swapV2Constraints.minAmountsTo)),
        swapV2Constraints.nonce,
        swapV2Constraints.deadline,
        swapV2Constraints.chainId
      )
    ));

    address signer = ECDSAUpgradeable.recover(structHash, signature);
    require(signer == swapV2Constraints.user, "INVALID_SIGNATURE");

    userNonces[swapV2Constraints.user] = swapV2Constraints.nonce;
  }
}