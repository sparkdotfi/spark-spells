// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { Ethereum }  from "spark-address-registry/Ethereum.sol";
import { SparkLend } from "spark-address-registry/SparkLend.sol";

import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";

import { SparkPayloadEthereum, SLLHelpers } from "src/SparkPayloadEthereum.sol";

/**
 * @title  November 27, 2025 Spark Ethereum Proposal
 * @notice Spark Treasury:
           - Foundation Grant for December 2025
           - Transfer Funds to Foundation for Arkis Investment
           Spark Liquidity Layer:
           - Onboard to B2C2
           - Upgrade Controller to v1.8
           SparkLend:
           - Claim Reserves for USDS and DAI Markets
 * @author Phoenix Labs
 * Forum:  https://forum.sky.money/t/november-27-2025-proposed-changes-to-spark-for-upcoming-spell/27418
 * Vote:   https://snapshot.box/#/s:sparkfi.eth/proposal/0xcaafeb100a8ec75ae1e1e9d4059f7d2ec2db31aa55a09be2ec2c7467e0f10799
 */
contract SparkEthereum_20251127 is SparkPayloadEthereum {

    using SLLHelpers for address;

    address internal constant B2C2               = 0xa29E963992597B21bcDCaa969d571984869C4FF5;
    address internal constant NEW_ALM_CONTROLLER = 0xE52d643B27601D4d2BAB2052f30cf936ed413cec;

    uint256 internal constant AMOUNT_TO_ARKIS      = 4_000_000e18;
    uint256 internal constant AMOUNT_TO_FOUNDATION = 1_100_000e18;

    constructor() {
        PAYLOAD_ARBITRUM  = 0xC0bcbb2554D4694fe7b34bB68b9DdfbB55D896BC;
        PAYLOAD_AVALANCHE = 0x282dAfE8B97e2Db5053761a4601ab2E1CB976318;
        PAYLOAD_BASE      = 0x3968a022D955Bbb7927cc011A48601B65a33F346;
        PAYLOAD_OPTIMISM  = 0x2F66666fB60c038f10948e9645Ca969bb397E2d5;
        PAYLOAD_UNICHAIN  = 0x41EdbF09cd2f272175c7fACB857B767859543D15;
    }

    function _postExecute() internal override {
        // Foundation Grant for December 2025 + Transfer Funds to Foundation for Arkis Investment
        IERC20(Ethereum.USDS).transfer(Ethereum.SPARK_FOUNDATION_MULTISIG, AMOUNT_TO_ARKIS + AMOUNT_TO_FOUNDATION);

        // Onboard to B2C2
        SLLHelpers.setRateLimitData(
            RateLimitHelpers.makeAddressAddressKey(
                MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_ASSET_TRANSFER(),
                Ethereum.USDC,
                B2C2
            ),
            Ethereum.ALM_RATE_LIMITS,
            1_000_000e6,
            20_000_000e6 / uint256(1 days),
            6
        );

        SLLHelpers.setRateLimitData(
            RateLimitHelpers.makeAddressAddressKey(
                MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_ASSET_TRANSFER(),
                Ethereum.USDT,
                B2C2
            ),
            Ethereum.ALM_RATE_LIMITS,
            1_000_000e6,
            20_000_000e6 / uint256(1 days),
            6
        );

        SLLHelpers.setRateLimitData(
            RateLimitHelpers.makeAddressAddressKey(
                MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_ASSET_TRANSFER(),
                Ethereum.PYUSD,
                B2C2
            ),
            Ethereum.ALM_RATE_LIMITS,
            1_000_000e6,
            20_000_000e6 / uint256(1 days),
            6
        );

        // Upgrade Controller to v1.8
        _upgradeController(Ethereum.ALM_CONTROLLER, NEW_ALM_CONTROLLER);

        NEW_ALM_CONTROLLER.setMaxExchangeRate(Ethereum.MORPHO_VAULT_USDC_BC, 1, 10);
        NEW_ALM_CONTROLLER.setMaxExchangeRate(Ethereum.MORPHO_VAULT_DAI_1,   1, 10);
        NEW_ALM_CONTROLLER.setMaxExchangeRate(Ethereum.MORPHO_VAULT_USDS,    1, 10);
        NEW_ALM_CONTROLLER.setMaxExchangeRate(Ethereum.SUSDS,                1, 10);
        NEW_ALM_CONTROLLER.setMaxExchangeRate(Ethereum.FLUID_SUSDS,          1, 10);
        NEW_ALM_CONTROLLER.setMaxExchangeRate(Ethereum.SUSDE,                1, 10);
        NEW_ALM_CONTROLLER.setMaxExchangeRate(Ethereum.SYRUP_USDC,           1, 10);
        NEW_ALM_CONTROLLER.setMaxExchangeRate(Ethereum.SYRUP_USDT,           1, 10);

        MainnetController(NEW_ALM_CONTROLLER).setMaxSlippage(Ethereum.ATOKEN_CORE_USDC,  0.99999e18);
        MainnetController(NEW_ALM_CONTROLLER).setMaxSlippage(Ethereum.ATOKEN_CORE_USDE,  0.99999e18);
        MainnetController(NEW_ALM_CONTROLLER).setMaxSlippage(Ethereum.ATOKEN_CORE_USDS,  0.99999e18);
        MainnetController(NEW_ALM_CONTROLLER).setMaxSlippage(Ethereum.ATOKEN_CORE_USDT,  0.99999e18);
        MainnetController(NEW_ALM_CONTROLLER).setMaxSlippage(Ethereum.ATOKEN_PRIME_USDS, 0.99999e18);

        MainnetController(NEW_ALM_CONTROLLER).setMaxSlippage(SparkLend.DAI_SPTOKEN,   0.99999e18);
        MainnetController(NEW_ALM_CONTROLLER).setMaxSlippage(SparkLend.USDC_SPTOKEN,  0.99999e18);
        MainnetController(NEW_ALM_CONTROLLER).setMaxSlippage(SparkLend.USDS_SPTOKEN,  0.99999e18);
        MainnetController(NEW_ALM_CONTROLLER).setMaxSlippage(SparkLend.USDT_SPTOKEN,  0.99999e18);
        MainnetController(NEW_ALM_CONTROLLER).setMaxSlippage(SparkLend.PYUSD_SPTOKEN, 0.99999e18);
        MainnetController(NEW_ALM_CONTROLLER).setMaxSlippage(SparkLend.WETH_SPTOKEN,  0.99999e18);

        // Claim Reserves for USDS and DAI Markets
        address[] memory aTokens = new address[](2);
        aTokens[0] = SparkLend.DAI_SPTOKEN;
        aTokens[1] = SparkLend.USDS_SPTOKEN;

        _transferFromSparkLendTreasury(aTokens);
    }

}
