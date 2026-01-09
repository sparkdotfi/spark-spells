// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;

import { IERC20 } from "forge-std/interfaces/IERC20.sol";

import { OptionsBuilder } from "lib/xchain-helpers/lib/devtools/packages/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

import { IMetaMorpho, MarketParams, Id, IERC4626 } from "metamorpho/interfaces/IMetaMorpho.sol";
import { IMetaMorphoFactory }                      from "metamorpho/interfaces/IMetaMorphoFactory.sol";

import { MarketParamsLib } from "morpho-blue/src/libraries/MarketParamsLib.sol";

import { Arbitrum }  from "spark-address-registry/Arbitrum.sol";
import { Avalanche } from "spark-address-registry/Avalanche.sol";
import { Base }      from "spark-address-registry/Base.sol";
import { Ethereum }  from "spark-address-registry/Ethereum.sol";
import { Gnosis }    from "spark-address-registry/Gnosis.sol";
import { Optimism }  from "spark-address-registry/Optimism.sol";
import { SparkLend } from "spark-address-registry/SparkLend.sol";
import { Unichain }  from "spark-address-registry/Unichain.sol";

import { IALMProxy }         from "spark-alm-controller/src/interfaces/IALMProxy.sol";
import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";

import { IExecutor } from "spark-gov-relay/src/interfaces/IExecutor.sol";

import { IAToken } from "sparklend-v1-core/interfaces/IAToken.sol";
import { IPool }   from "sparklend-v1-core/interfaces/IPool.sol";

import { AMBForwarder }                            from "xchain-helpers/forwarders/AMBForwarder.sol";
import { ArbitrumForwarder, ICrossDomainArbitrum } from "xchain-helpers/forwarders/ArbitrumForwarder.sol";
import { LZForwarder, ILayerZeroEndpointV2 }       from "xchain-helpers/forwarders/LZForwarder.sol";
import { OptimismForwarder }                       from "xchain-helpers/forwarders/OptimismForwarder.sol";


import { SLLHelpers } from "./libraries/SLLHelpers.sol";

import { ITreasuryControllerLike, IArbitrumTokenBridge, IOptimismTokenBridge } from "./interfaces/Interfaces.sol";

import { AaveV3PayloadBase, IEngine } from "./AaveV3PayloadBase.sol";

/**
 * @dev    Base smart contract for Ethereum.
 * @author Phoenix Labs
 */
abstract contract SparkPayloadEthereum is AaveV3PayloadBase(SparkLend.CONFIG_ENGINE) {

    using OptionsBuilder for bytes;

    // These need to be immutable (delegatecall) and can only be set in constructor
    address public immutable PAYLOAD_ARBITRUM;
    address public immutable PAYLOAD_BASE;
    address public immutable PAYLOAD_GNOSIS;
    address public immutable PAYLOAD_OPTIMISM;
    address public immutable PAYLOAD_UNICHAIN;
    address public immutable PAYLOAD_AVALANCHE;

    function execute() public override {
        super.execute();

        if (PAYLOAD_ARBITRUM != address(0)) {
            ArbitrumForwarder.sendMessageL1toL2({
                l1CrossDomain: ArbitrumForwarder.L1_CROSS_DOMAIN_ARBITRUM_ONE,
                target:        Arbitrum.SPARK_RECEIVER,
                message:       _encodePayloadQueue(PAYLOAD_ARBITRUM),
                gasLimit:      1_000_000,
                maxFeePerGas:  50e9,
                baseFee:       block.basefee
            });
        }
        if (PAYLOAD_BASE != address(0)) {
            OptimismForwarder.sendMessageL1toL2({
                l1CrossDomain: OptimismForwarder.L1_CROSS_DOMAIN_BASE,
                target:        Base.SPARK_RECEIVER,
                message:       _encodePayloadQueue(PAYLOAD_BASE),
                gasLimit:      1_000_000
            });
        }
        if (PAYLOAD_GNOSIS != address(0)) {
            AMBForwarder.sendMessageEthereumToGnosisChain({
                target:   Gnosis.AMB_EXECUTOR,
                message:  _encodePayloadQueue(PAYLOAD_GNOSIS),
                gasLimit: 1_000_000
            });
        }
        if (PAYLOAD_OPTIMISM != address(0)) {
            OptimismForwarder.sendMessageL1toL2({
                l1CrossDomain: OptimismForwarder.L1_CROSS_DOMAIN_OPTIMISM,
                target:        Optimism.SPARK_RECEIVER,
                message:       _encodePayloadQueue(PAYLOAD_OPTIMISM),
                gasLimit:      1_000_000
            });
        }
        if (PAYLOAD_UNICHAIN != address(0)) {
            OptimismForwarder.sendMessageL1toL2({
                l1CrossDomain: OptimismForwarder.L1_CROSS_DOMAIN_UNICHAIN,
                target:        Unichain.SPARK_RECEIVER,
                message:       _encodePayloadQueue(PAYLOAD_UNICHAIN),
                gasLimit:      1_000_000
            });
        }
        if (PAYLOAD_AVALANCHE != address(0)) {
            bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(500_000, 0);

            LZForwarder.sendMessage({
                _dstEid:        LZForwarder.ENDPOINT_ID_AVALANCHE,
                _receiver:      SLLHelpers.addrToBytes32(Avalanche.SPARK_RECEIVER),
                endpoint:       ILayerZeroEndpointV2(LZForwarder.ENDPOINT_ETHEREUM),
                _message:       _encodePayloadQueue(PAYLOAD_AVALANCHE),
                _options:       options,
                _refundAddress: Ethereum.SPARK_PROXY,
                _payInLzToken:  false
            });
        }
    }

    /**
     * @notice Checks if the star payload is executable in the current block
     * @dev Required, useful for implementing "earliest launch date" or "office hours" strategy
     * @return result The result of the check (true = executable, false = not)
     */
    function isExecutable() external view returns (bool result) {
        result = true;  // TODO Change this
    }

    function getPoolContext() public pure override returns (IEngine.PoolContext memory) {
        return IEngine.PoolContext({networkName: "Ethereum", networkAbbreviation: "Eth"});
    }

    function _encodePayloadQueue(address _payload) internal pure returns (bytes memory) {
        address[] memory targets        = new address[](1);
        uint256[] memory values         = new uint256[](1);
        string[] memory signatures      = new string[](1);
        bytes[] memory calldatas        = new bytes[](1);
        bool[] memory withDelegatecalls = new bool[](1);

        targets[0]           = _payload;
        values[0]            = 0;
        signatures[0]        = "execute()";
        calldatas[0]         = "";
        withDelegatecalls[0] = true;

        return abi.encodeCall(IExecutor.queue, (
            targets,
            values,
            signatures,
            calldatas,
            withDelegatecalls
        ));
    }

    function _upgradeController(address oldController, address newController) internal {
        SLLHelpers.upgradeMainnetController(
            oldController,
            newController
        );
    }

    function _configureAaveToken(address token, uint256 depositMax, uint256 depositSlope) internal {
        SLLHelpers.configureAaveToken(
            Ethereum.ALM_RATE_LIMITS,
            token,
            depositMax,
            depositSlope
        );
    }

    function _configureERC4626Vault(address vault, uint256 depositMax, uint256 depositSlope) internal {
        SLLHelpers.configureERC4626Vault(
            Ethereum.ALM_RATE_LIMITS,
            vault,
            depositMax,
            depositSlope
        );
    }

    function _configureCurvePool(
        address controller,
        address pool,
        uint256 maxSlippage,
        uint256 swapMax,
        uint256 swapSlope,
        uint256 depositMax,
        uint256 depositSlope,
        uint256 withdrawMax,
        uint256 withdrawSlope
    ) internal {
        SLLHelpers.configureCurvePool(
            controller,
            Ethereum.ALM_RATE_LIMITS,
            pool,
            maxSlippage,
            swapMax,
            swapSlope,
            depositMax,
            depositSlope,
            withdrawMax,
            withdrawSlope
        );
    }

    function _transferAssetFromAlmProxy(
        address asset,
        address destination,
        uint256 amount
    ) internal {
        // Grant controller role to Spark Proxy
        MainnetController(Ethereum.ALM_PROXY).grantRole(
            IALMProxy(Ethereum.ALM_PROXY).CONTROLLER(),
            Ethereum.SPARK_PROXY
        );

        IALMProxy(Ethereum.ALM_PROXY).doCall(
            asset,
            abi.encodeCall(
                IERC20(asset).transfer,
                (destination, amount)
            )
        );

        // Revoke controller role from Spark Proxy
        MainnetController(Ethereum.ALM_PROXY).revokeRole(
            IALMProxy(Ethereum.ALM_PROXY).CONTROLLER(),
            Ethereum.SPARK_PROXY
        );
    }

    function _transferFromSparkLendTreasury(address[] memory aTokens) internal {
        address[] memory assets = new address[](aTokens.length);

        for (uint256 i; i < aTokens.length; i++) {
            assets[i] = IAToken(aTokens[i]).UNDERLYING_ASSET_ADDRESS();
        }

        IPool(SparkLend.POOL).mintToTreasury(assets);

        for (uint256 i; i < aTokens.length; i++) {
            address treasury = aTokens[i] == SparkLend.DAI_SPTOKEN
                ? SparkLend.DAI_TREASURY
                : SparkLend.TREASURY;

            ITreasuryControllerLike(SparkLend.TREASURY_CONTROLLER).transfer({
                collector: treasury,
                token:     aTokens[i],
                recipient: Ethereum.ALM_PROXY,
                amount:    IERC20(aTokens[i]).balanceOf(treasury)
            });
        }
    }

    function _setUpNewMorphoVault(
        address               asset,
        string         memory name,
        string         memory symbol,
        MarketParams[] memory markets,
        uint256[]      memory caps,
        uint256               vaultFee,
        uint256               initialDeposit,
        uint256               sllDepositMax,
        uint256               sllDepositSlope
    ) internal {
        IMetaMorpho vault = IMetaMorphoFactory(Ethereum.MORPHO_FACTORY).createMetaMorpho({
            initialOwner:    Ethereum.SPARK_PROXY,
            initialTimelock: 0,
            asset:           asset,
            name:            name,
            symbol:          symbol,
            salt:            ""
        });

        require(markets.length == caps.length, "Markets and caps length mismatch");

        for (uint256 i; i < markets.length; i++) {
            vault.submitCap(markets[i], caps[i]);
            vault.acceptCap(markets[i]);
        }

        // Submit and accept cap for idle market
        MarketParams memory idleMarket = SLLHelpers.morphoIdleMarket(asset);
        vault.submitCap(idleMarket, type(uint184).max);
        vault.acceptCap(idleMarket);

        // Add idle market to supply queue
        Id[] memory ids = new Id[](1);
        ids[0] = MarketParamsLib.id(idleMarket);

        vault.setSupplyQueue(ids);

        // Set ALM Relayer as allocator.
        vault.setIsAllocator(
            Ethereum.ALM_RELAYER_MULTISIG,
            true
        );

        // Set Vault Fee Recipient and Fee
        vault.setFeeRecipient(Ethereum.ALM_PROXY);
        vault.setFee(vaultFee);

        // Seed vault with initial deposit
        IERC20(asset).approve(address(vault), initialDeposit);
        IERC4626(address(vault)).deposit(initialDeposit, address(1));

        // Submit timelock for vault (Increases are immediate)
        vault.submitTimelock(1 days);

        if (sllDepositMax != 0 && sllDepositSlope != 0) {
            _configureERC4626Vault(
                address(vault),
                sllDepositMax,
                sllDepositSlope
            );
        }
    }

    function _sendOpTokens(address fromToken, address toToken, uint256 amount) internal {
        IERC20(fromToken).approve(Ethereum.OPTIMISM_TOKEN_BRIDGE, amount);

        IOptimismTokenBridge(Ethereum.OPTIMISM_TOKEN_BRIDGE).bridgeERC20To({
            _localToken  : fromToken,
            _remoteToken : toToken,
            _to          : Optimism.ALM_PROXY,
            _amount      : amount,
            _minGasLimit : 1_000_000,
            _extraData   : ""
        });
    }

    function _sendArbTokens(address token, uint256 amount) internal {
        // Gas submission adapted from ArbitrumForwarder.sendMessageL1toL2
        bytes memory finalizeDepositCalldata = IArbitrumTokenBridge(Ethereum.ARBITRUM_TOKEN_BRIDGE).getOutboundCalldata({
            l1Token: token,
            from:    address(this),
            to:      Arbitrum.ALM_PROXY,
            amount:  amount,
            data:    ""
        });

        uint256 gasLimit = 1_000_000;
        uint256 baseFee = block.basefee;
        uint256 maxFeePerGas = 50e9;
        uint256 maxSubmission = ICrossDomainArbitrum(ArbitrumForwarder.L1_CROSS_DOMAIN_ARBITRUM_ONE).calculateRetryableSubmissionFee(finalizeDepositCalldata.length, baseFee);
        uint256 maxRedemption = gasLimit * maxFeePerGas;

        IERC20(token).approve(Ethereum.ARBITRUM_TOKEN_BRIDGE, amount);
        IArbitrumTokenBridge(Ethereum.ARBITRUM_TOKEN_BRIDGE).outboundTransfer{value: maxSubmission + maxRedemption}({
            l1Token:     token, 
            to:          Arbitrum.ALM_PROXY, 
            amount:      amount, 
            maxGas:      gasLimit, 
            gasPriceBid: maxFeePerGas,
            data:        abi.encode(maxSubmission, bytes(""))
        });
    }

}
