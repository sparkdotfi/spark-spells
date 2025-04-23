// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { Ethereum } from 'spark-address-registry/Ethereum.sol';

import { IMetaMorpho, MarketParams } from 'metamorpho/interfaces/IMetaMorpho.sol';

import { SparkPayloadEthereum, IEngine, EngineFlags, Rates } from "../../SparkPayloadEthereum.sol";

/**
 * @title  April 17, 2025 Spark Ethereum Proposal
 * @notice Spark Liquidity Layer:
 *         - Onboard SparkLend USDT
 *         - Onboard AAVE Core USDT
 *         SparkLend:
 *         - Update DAI IRM
 *         - Update USDS IRM
 *         - Update USDC IRM
 *         - Update USDT IRM
 *         - Adjust USDT Cap Automator Parameters
 * @author Phoenix Labs
 * Forum:  https://forum.sky.money/t/may-1-2025-proposed-changes-to-spark-for-upcoming-spell/26288
 * Vote:   TODO
 */
contract SparkEthereum_20250501 is SparkPayloadEthereum {

    address constant DAI_USDS_IRM  = 0x7729E1CE24d7c4A82e76b4A2c118E328C35E6566;  // DAI  and USDS use the same params, same IRM
    address constant USDC_USDT_IRM = 0x7F2fc6A7E3b3c658A84999b26ad2013C4Dc87061;  // USDC and USDT use the same params, same IRM

    function _postExecute() internal override {
        LISTING_ENGINE.POOL_CONFIGURATOR().setReserveInterestRateStrategyAddress(Ethereum.DAI,  DAI_USDS_IRM);
        LISTING_ENGINE.POOL_CONFIGURATOR().setReserveInterestRateStrategyAddress(Ethereum.USDS, DAI_USDS_IRM);
        LISTING_ENGINE.POOL_CONFIGURATOR().setReserveInterestRateStrategyAddress(Ethereum.USDC, USDC_USDT_IRM);
        LISTING_ENGINE.POOL_CONFIGURATOR().setReserveInterestRateStrategyAddress(Ethereum.USDT, USDC_USDT_IRM);

    }

}
