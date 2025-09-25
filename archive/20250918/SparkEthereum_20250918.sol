// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IMetaMorpho, MarketParams } from 'metamorpho/interfaces/IMetaMorpho.sol';

import { Ethereum } from 'spark-address-registry/Ethereum.sol';

import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";
import { IALMProxy }         from "spark-alm-controller/src/interfaces/IALMProxy.sol";
import { IRateLimits }       from "spark-alm-controller/src/interfaces/IRateLimits.sol";

import { ICapAutomator } from "sparklend-cap-automator/interfaces/ICapAutomator.sol";

import { CCTPForwarder } from "xchain-helpers/forwarders/CCTPForwarder.sol";

import { SparkPayloadEthereum, SLLHelpers } from "src/SparkPayloadEthereum.sol";

/**
 * @title  September 18, 2025 Spark Ethereum Proposal
 * @notice Spark Liquidity Layer:
 *         - Upgrade ALM Controller to v1.7
 *         - Increase USDC CCTP Rate Limits
 *         - Onboard USDS SPK Farm
 *         - Onboard PYUSD/USDS Curve Pool
 *         Spark USDS Morpho Vault:
 *         - Onboard December PT-USDS-SPK
 *         SparkLend:
 *         - Increase USDT Cap Automator Rate Limits
 *         - Claim Accrued Reserves for USDS and DAI
 * @author Phoenix Labs
 * Forum:  https://forum.sky.money/t/september-18-2025-proposed-changes-to-spark-for-upcoming-spell/27153
 * Vote:   https://vote.sky.money/polling/QmXzyYyJ
 *         https://vote.sky.money/polling/QmUv9fbY
 *         https://vote.sky.money/polling/Qme1KAbo
 *         https://vote.sky.money/polling/QmdX2eGt
 *         https://vote.sky.money/polling/QmeyqTyQ
 *         https://vote.sky.money/polling/Qmc8PHPC
 *         https://vote.sky.money/polling/QmX3Lfa6
 */
contract SparkEthereum_20250918 is SparkPayloadEthereum {

    address internal constant NEW_ALM_CONTROLLER = 0x577Fa18a498e1775939b668B0224A5e5a1e56fc3;
    address internal constant USDS_SPK_FARM      = 0x173e314C7635B45322cd8Cb14f44b312e079F3af;

    address internal constant PT_USDS_SPK_18DEC2025            = 0xA2a420230A5cb045db052E377D20b9c156805b95;
    address internal constant PT_USDS_SPK_18DEC2025_PRICE_FEED = 0x2bDA5e778fA40109b3C9fe9AF42332017810492B;

    constructor() {
        PAYLOAD_BASE = 0x282dAfE8B97e2Db5053761a4601ab2E1CB976318;
    }

    function _postExecute() internal override {
        // Upgrade ALM Controller to v1.7
        _upgradeController(Ethereum.ALM_CONTROLLER, NEW_ALM_CONTROLLER);

        // Increase USDC CCTP Rate Limits
        SLLHelpers.setUSDCToDomainRateLimit(
            Ethereum.ALM_RATE_LIMITS,
            CCTPForwarder.DOMAIN_ID_CIRCLE_BASE,
            200_000_000e6,
            500_000_000e6 / uint256(1 days)
        );

        // Onboard USDS SPK Farm
        SLLHelpers.setRateLimitData(
            RateLimitHelpers.makeAssetKey(
                MainnetController(NEW_ALM_CONTROLLER).LIMIT_FARM_DEPOSIT(),
                USDS_SPK_FARM
            ),
            Ethereum.ALM_RATE_LIMITS,
            250_000_000e18,
            50_000_000e18 / uint256(1 days),
            18
        );

        IRateLimits(Ethereum.ALM_RATE_LIMITS).setUnlimitedRateLimitData(
            RateLimitHelpers.makeAssetKey(
                MainnetController(NEW_ALM_CONTROLLER).LIMIT_FARM_WITHDRAW(),
                USDS_SPK_FARM
            )
        );

        // Onboard December PT-USDS-SPK
        IMetaMorpho(Ethereum.MORPHO_VAULT_USDS).submitCap(
            MarketParams({
                loanToken:       Ethereum.USDS,
                collateralToken: PT_USDS_SPK_18DEC2025,
                oracle:          PT_USDS_SPK_18DEC2025_PRICE_FEED,
                irm:             Ethereum.MORPHO_DEFAULT_IRM,
                lltv:            0.965e18
            }),
            1_000_000_000e18
        );

        // Onboard PYUSD/USDS Curve Pool
        _configureCurvePool({
            controller:    NEW_ALM_CONTROLLER,
            pool:          Ethereum.CURVE_PYUSDUSDS,
            maxSlippage:   0.998e18,
            swapMax:       5_000_000e18,
            swapSlope:     50_000_000e18 / uint256(1 days),
            depositMax:    5_000_000e18,
            depositSlope:  50_000_000e18 / uint256(1 days),
            withdrawMax:   5_000_000e18,
            withdrawSlope: 100_000_000e18 / uint256(1 days)
        });

        // Increase USDT Cap Automator Rate Limits
        ICapAutomator(Ethereum.CAP_AUTOMATOR).setSupplyCapConfig({
            asset:            Ethereum.USDT,
            max:              5_000_000_000,
            gap:              1_000_000_000,
            increaseCooldown: 12 hours
        });
        ICapAutomator(Ethereum.CAP_AUTOMATOR).setBorrowCapConfig({
            asset:            Ethereum.USDT,
            max:              5_000_000_000,
            gap:              200_000_000,
            increaseCooldown: 12 hours
        });

        // Withdraw USDS and DAI Reserves from SparkLend
        address[] memory aTokens = new address[](2);
        aTokens[0] = Ethereum.DAI_SPTOKEN;
        aTokens[1] = Ethereum.USDS_SPTOKEN;

        _transferFromSparkLendTreasury(aTokens);
    }

}
