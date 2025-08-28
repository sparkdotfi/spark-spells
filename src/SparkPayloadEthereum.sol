// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import './AaveV3PayloadBase.sol';

import { IERC20 } from 'forge-std/interfaces/IERC20.sol';

import { IMetaMorpho, MarketParams, Id, IERC4626 } from 'metamorpho/interfaces/IMetaMorpho.sol';
import { IMetaMorphoFactory }        from 'metamorpho/interfaces/IMetaMorphoFactory.sol';

import { MarketParamsLib } from "morpho-blue/src/libraries/MarketParamsLib.sol";

import { Arbitrum } from 'spark-address-registry/Arbitrum.sol';
import { Base }     from 'spark-address-registry/Base.sol';
import { Ethereum } from 'spark-address-registry/Ethereum.sol';
import { Gnosis }   from 'spark-address-registry/Gnosis.sol';
import { Optimism } from 'spark-address-registry/Optimism.sol';
import { Unichain } from 'spark-address-registry/Unichain.sol';

import { IALMProxy }         from 'spark-alm-controller/src/interfaces/IALMProxy.sol';
import { MainnetController } from 'spark-alm-controller/src/MainnetController.sol';

import { IExecutor } from 'spark-gov-relay/src/interfaces/IExecutor.sol';

import { IAToken } from 'sparklend-v1-core/interfaces/IAToken.sol';
import { IPool }   from 'sparklend-v1-core/interfaces/IPool.sol';

import { AMBForwarder }      from 'xchain-helpers/forwarders/AMBForwarder.sol';
import { ArbitrumForwarder } from 'xchain-helpers/forwarders/ArbitrumForwarder.sol';
import { OptimismForwarder } from 'xchain-helpers/forwarders/OptimismForwarder.sol';

import { SLLHelpers } from './libraries/SLLHelpers.sol';

interface ITreasuryController {
    function transfer(
        address collector,
        address token,
        address recipient,
        uint256 amount
    ) external;
}

/**
 * @dev Base smart contract for Ethereum.
 * @author Phoenix Labs
 */
abstract contract SparkPayloadEthereum is
    AaveV3PayloadBase(IEngine(Ethereum.CONFIG_ENGINE))
{

    // These need to be immutable (delegatecall) and can only be set in constructor
    address public immutable PAYLOAD_ARBITRUM;
    address public immutable PAYLOAD_BASE;
    address public immutable PAYLOAD_GNOSIS;
    address public immutable PAYLOAD_OPTIMISM;
    address public immutable PAYLOAD_UNICHAIN;

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
    }

    function getPoolContext() public pure override returns (IEngine.PoolContext memory) {
        return IEngine.PoolContext({networkName: 'Ethereum', networkAbbreviation: 'Eth'});
    }

    function _encodePayloadQueue(address _payload) internal pure returns (bytes memory) {
        address[] memory targets        = new address[](1);
        uint256[] memory values         = new uint256[](1);
        string[] memory signatures      = new string[](1);
        bytes[] memory calldatas        = new bytes[](1);
        bool[] memory withDelegatecalls = new bool[](1);

        targets[0]           = _payload;
        values[0]            = 0;
        signatures[0]        = 'execute()';
        calldatas[0]         = '';
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

        IPool(Ethereum.POOL).mintToTreasury(assets);

        for (uint256 i; i < aTokens.length; i++) {
            ITreasuryController(Ethereum.TREASURY_CONTROLLER).transfer({
                collector: Ethereum.TREASURY,
                token:     aTokens[i],
                recipient: Ethereum.SPARK_PROXY,
                amount:    IERC20(aTokens[i]).balanceOf(Ethereum.TREASURY)
            });
        }
    }

    function _setupNewMorphoVault(
        address               asset,
        string         memory name,
        string         memory symbol,
        MarketParams[] memory markets,
        uint256[]      memory caps,
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
            salt:            bytes32(0)
        });

        require(markets.length == caps.length, "Markets and caps length mismatch");

        Id[] memory ids = new Id[](markets.length + 1);

        for (uint256 i; i < markets.length; i++) {
            vault.submitCap(markets[i], caps[i]);
            vault.acceptCap(markets[i]);

            ids[i] = MarketParamsLib.id(markets[i]);
        }

        // Submit and accept cap for idle market
        MarketParams memory idleMarket = SLLHelpers.morphoIdleMarket(asset);
        vault.submitCap(idleMarket, type(uint184).max);
        vault.acceptCap(idleMarket);

        // Add idle market to supply queue
        ids[ids.length - 1] = MarketParamsLib.id(idleMarket);

        // Set Spark Proxy as allocator temporarily to set supply queue
        vault.setIsAllocator(
            Ethereum.SPARK_PROXY,
            true
        );
        vault.setSupplyQueue(ids);
        vault.setIsAllocator(
            Ethereum.SPARK_PROXY,
            false
        );

        // Set ALM Relayer as allocator.
        vault.setIsAllocator(
            Ethereum.ALM_RELAYER,
            true
        );

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

}
