// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { Ethereum } from 'spark-address-registry/Ethereum.sol';

import { ICapAutomator } from "sparklend-cap-automator/interfaces/ICapAutomator.sol";

import { IMetaMorpho, MarketParams } from 'metamorpho/interfaces/IMetaMorpho.sol';

import { MainnetController }               from "spark-alm-controller/src/MainnetController.sol";
import { RateLimitHelpers, RateLimitData } from "spark-alm-controller/src/RateLimitHelpers.sol";

import { SparkPayloadEthereum } from "../../SparkPayloadEthereum.sol";

/**
 * @title  April 17, 2025 Spark Ethereum Proposal
 * @notice Spark Liquidity Layer: Upgrade Controller to v1.4.0 on All Chains
 *                                Onboard SparkLend DAI
 *                                Onboard Curve sUSDS/USDT Pool
 *                                Onboard Curve USDC/USDT Pool
 *         SparkLend: Adjust cbBTC and tBTC Interest Rate Models
 *                    Reduce WBTC LT
 *                    Add sUSDS to USD Emode
 *         Morpho: Onboard July sUSDe PT
 * @author Phoenix Labs
 * Forum:  https://forum.sky.money/t/april-17-2025-proposed-changes-to-spark-for-upcoming-spell/26234
 * Vote:   https://vote.makerdao.com/polling/QmU3y9jf
 *         https://vote.makerdao.com/polling/QmQgnWbX
 *         https://vote.makerdao.com/polling/Qmc3WXej
 *         https://vote.makerdao.com/polling/QmQk4XKy
 *         https://vote.makerdao.com/polling/QmRkQDMT
 *         https://vote.makerdao.com/polling/QmbNssss
 *         https://vote.makerdao.com/polling/QmWgkXDA
 *         https://vote.makerdao.com/polling/QmWju9Uu
 */
contract SparkEthereum_20250417 is SparkPayloadEthereum {

    address internal constant OLD_ALM_CONTROLLER = Ethereum.ALM_CONTROLLER;
    address internal constant NEW_ALM_CONTROLLER = 0xF8Dff673b555a225e149218C5005FC88f4a13870;

    address internal constant PT_SUSDE_31JUL2025_PRICE_FEED = address(0);  // TODO
    address internal constant PT_SUSDE_31JUL2025            = address(0);  // TODO

    constructor() {
        PAYLOAD_ARBITRUM = address(0);  // TODO
    }

    function _postExecute() internal override {
        _upgradeController(
            OLD_ALM_CONTROLLER,
            NEW_ALM_CONTROLLER
        );

        _onboardAaveToken(
            Ethereum.DAI_ATOKEN,
            100_000_000e18,
            uint256(50_000_000e18) / 1 days
        );
        // TODO Curve pools

        // TODO Adjust cbBTC and tBTC Interest Rate Models
        // TODO Reduce WBTC LT
        // TODO Add sUSDS to USD Emode
        
        // Onboard PT-SUSDE-29MAY2025/DAI
        IMetaMorpho(Ethereum.MORPHO_VAULT_DAI_1).submitCap(
            MarketParams({
                loanToken:       Ethereum.DAI,
                collateralToken: PT_SUSDE_31JUL2025,
                oracle:          PT_SUSDE_31JUL2025_PRICE_FEED,
                irm:             Ethereum.MORPHO_DEFAULT_IRM,
                lltv:            0.915e18
            }),
            400_000_000e18
        );
    }

}
