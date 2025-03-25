// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { Arbitrum } from "spark-address-registry/Arbitrum.sol";
import { Base }     from "spark-address-registry/Base.sol";
import { Ethereum } from 'spark-address-registry/Ethereum.sol';

import { CCTPForwarder } from "xchain-helpers/forwarders/CCTPForwarder.sol";

import { ControllerInstance }              from "spark-alm-controller/deploy/ControllerInstance.sol";
import { MainnetControllerInit }           from "spark-alm-controller/deploy/MainnetControllerInit.sol";
import { MainnetController }               from "spark-alm-controller/src/MainnetController.sol";
import { RateLimitHelpers, RateLimitData } from "spark-alm-controller/src/RateLimitHelpers.sol";

import { SparkPayloadEthereum } from "../../SparkPayloadEthereum.sol";

/**
 * @title  April 3, 2025 Spark Ethereum Proposal
 * @notice Spark Liquidity Layer: Onboard BUIDL-I, USTB, JTRSY, syrupUSDC
 *                                Increase USDC rate limit for SparkLend
 *         SparkLend: Increase USDC Supply/Borrow Caps
 * @author Phoenix Labs
 * Forum:  https://forum.sky.money/t/april-3-2025-proposed-changes-to-spark-for-upcoming-spell/26155
 * Vote:   TODO
 */
contract SparkEthereum_20250403 is SparkPayloadEthereum {

    constructor() {
    }

    function _postExecute() internal override {
        _upgradeController();
    }

    function _upgradeController() private {
        MainnetControllerInit.MintRecipient[] memory mintRecipients = new MainnetControllerInit.MintRecipient[](2);
        mintRecipients[0] = MainnetControllerInit.MintRecipient({
            domain        : CCTPForwarder.DOMAIN_ID_CIRCLE_BASE,
            mintRecipient : bytes32(uint256(uint160(Base.ALM_PROXY)))
        });
        mintRecipients[1] = MainnetControllerInit.MintRecipient({
            domain        : CCTPForwarder.DOMAIN_ID_CIRCLE_ARBITRUM_ONE,
            mintRecipient : bytes32(uint256(uint160(Arbitrum.ALM_PROXY)))
        });

        MainnetControllerInit.upgradeController({
            controllerInst: ControllerInstance({
                almProxy   : Ethereum.ALM_PROXY,
                controller : NEW_ALM_CONTROLLER,
                rateLimits : Ethereum.ALM_RATE_LIMITS
            }),
            configAddresses: MainnetControllerInit.ConfigAddressParams({
                freezer       : Ethereum.ALM_FREEZER,
                relayer       : Ethereum.ALM_RELAYER,
                oldController : Ethereum.ALM_CONTROLLER
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
    }

}
