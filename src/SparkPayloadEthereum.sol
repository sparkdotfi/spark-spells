// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import './AaveV3PayloadBase.sol';

import { Arbitrum } from 'spark-address-registry/Arbitrum.sol';
import { Base }     from 'spark-address-registry/Base.sol';
import { Ethereum } from 'spark-address-registry/Ethereum.sol';
import { Gnosis }   from 'spark-address-registry/Gnosis.sol';

import { IExecutor } from 'spark-gov-relay/src/interfaces/IExecutor.sol';

import { AMBForwarder }      from "xchain-helpers/forwarders/AMBForwarder.sol";
import { ArbitrumForwarder } from "xchain-helpers/forwarders/ArbitrumForwarder.sol";
import { CCTPForwarder }     from "xchain-helpers/forwarders/CCTPForwarder.sol";
import { OptimismForwarder } from "xchain-helpers/forwarders/OptimismForwarder.sol";

import { ControllerInstance }              from "spark-alm-controller/deploy/ControllerInstance.sol";
import { MainnetControllerInit }           from "spark-alm-controller/deploy/MainnetControllerInit.sol";
import { MainnetController }               from "spark-alm-controller/src/MainnetController.sol";
import { RateLimitHelpers, RateLimitData } from "spark-alm-controller/src/RateLimitHelpers.sol";

import { SparkLiquidityLayerHelpers } from './libraries/SparkLiquidityLayerHelpers.sol';

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
    
    function _upgradeController(
        address oldController,
        address newController
    ) internal {
        MainnetControllerInit.MintRecipient[] memory mintRecipients = new MainnetControllerInit.MintRecipient[](2);
        mintRecipients[0] = MainnetControllerInit.MintRecipient({
            domain        : CCTPForwarder.DOMAIN_ID_CIRCLE_BASE,
            mintRecipient : SparkLiquidityLayerHelpers.addrToBytes32(Base.ALM_PROXY)
        });
        mintRecipients[1] = MainnetControllerInit.MintRecipient({
            domain        : CCTPForwarder.DOMAIN_ID_CIRCLE_ARBITRUM_ONE,
            mintRecipient : SparkLiquidityLayerHelpers.addrToBytes32(Arbitrum.ALM_PROXY)
        });

        MainnetControllerInit.upgradeController({
            controllerInst: ControllerInstance({
                almProxy   : Ethereum.ALM_PROXY,
                controller : newController,
                rateLimits : Ethereum.ALM_RATE_LIMITS
            }),
            configAddresses: MainnetControllerInit.ConfigAddressParams({
                freezer       : Ethereum.ALM_FREEZER,
                relayer       : Ethereum.ALM_RELAYER,
                oldController : oldController
            }),
            checkAddresses: MainnetControllerInit.CheckAddressParams({
                admin      : Ethereum.SPARK_PROXY,
                proxy      : Ethereum.ALM_PROXY,
                rateLimits : Ethereum.ALM_RATE_LIMITS,
                vault      : Ethereum.ALLOCATOR_VAULT,
                psm        : Ethereum.PSM,
                daiUsds    : Ethereum.DAI_USDS,
                cctp       : Ethereum.CCTP_TOKEN_MESSENGER
            }),
            mintRecipients: mintRecipients
        });
        // TODO add gov-ops relayer
    }

    function _onboardAaveToken(address token, uint256 depositMax, uint256 depositSlope) internal {
        SparkLiquidityLayerHelpers.onboardAaveToken(
            Ethereum.ALM_RATE_LIMITS,
            token,
            depositMax,
            depositSlope
        );
    }

    function _onboardERC4626Vault(address vault, uint256 depositMax, uint256 depositSlope) internal {
        SparkLiquidityLayerHelpers.onboardERC4626Vault(
            Ethereum.ALM_RATE_LIMITS,
            vault,
            depositMax,
            depositSlope
        );
    }

}
