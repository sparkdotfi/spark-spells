// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { Ethereum } from 'spark-address-registry/Ethereum.sol';

import { ICapAutomator } from "sparklend-cap-automator/interfaces/ICapAutomator.sol";

import { SparkPayloadEthereum } from "../../SparkPayloadEthereum.sol";

/**
 * @title  May 1, 2025 Spark Ethereum Proposal
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
 * Vote:   https://vote.makerdao.com/polling/QmfJ5yDF
 *         https://vote.makerdao.com/polling/QmQM99z5
 *         https://vote.makerdao.com/polling/Qmdc28Ag
 *         https://vote.makerdao.com/polling/QmeNB8S1
 *         https://vote.makerdao.com/polling/Qmee2jez
 *         https://vote.makerdao.com/polling/QmfBmrxq
 *         https://vote.makerdao.com/polling/QmZ2vydY
 */
contract SparkEthereum_20250501 is SparkPayloadEthereum {

    address constant DAI_USDS_IRM  = 0x7729E1CE24d7c4A82e76b4A2c118E328C35E6566;  // DAI  and USDS use the same params, same IRM
    address constant USDC_USDT_IRM = 0x7F2fc6A7E3b3c658A84999b26ad2013C4Dc87061;  // USDC and USDT use the same params, same IRM

    address constant AAVE_CORE_AUSDT = 0x23878914EFE38d27C4D67Ab83ed1b93A74D4086a;

    function _postExecute() internal override {
        LISTING_ENGINE.POOL_CONFIGURATOR().setReserveInterestRateStrategyAddress(Ethereum.DAI,  DAI_USDS_IRM);
        LISTING_ENGINE.POOL_CONFIGURATOR().setReserveInterestRateStrategyAddress(Ethereum.USDS, DAI_USDS_IRM);
        LISTING_ENGINE.POOL_CONFIGURATOR().setReserveInterestRateStrategyAddress(Ethereum.USDC, USDC_USDT_IRM);
        LISTING_ENGINE.POOL_CONFIGURATOR().setReserveInterestRateStrategyAddress(Ethereum.USDT, USDC_USDT_IRM);

        _onboardAaveToken(Ethereum.USDT_ATOKEN, 100_000_000e6, uint256(50_000_000e6) / 1 days);
        _onboardAaveToken(AAVE_CORE_AUSDT,      50_000_000e6,  uint256(25_000_000e6) / 1 days);

        ICapAutomator capAutomator = ICapAutomator(Ethereum.CAP_AUTOMATOR);

        capAutomator.setSupplyCapConfig({ asset: Ethereum.USDT, max: 500_000_000, gap: 100_000_000, increaseCooldown: 12 hours });
        capAutomator.setBorrowCapConfig({ asset: Ethereum.USDT, max: 450_000_000, gap: 50_000_000,  increaseCooldown: 12 hours });
    }

}
