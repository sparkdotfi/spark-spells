// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { Ethereum }  from "spark-address-registry/Ethereum.sol";
import { SparkLend } from "spark-address-registry/SparkLend.sol";

import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";

import { ICapAutomator } from "sparklend-cap-automator/interfaces/ICapAutomator.sol";

import { SparkPayloadEthereum, SLLHelpers } from "src/SparkPayloadEthereum.sol";

import { ISparkVaultV2Like } from "src/interfaces/Interfaces.sol";

/**
 * @title  November 27, 2025 Spark Ethereum Proposal
 * @notice 
 * @author Phoenix Labs
 * Forum:  
 * Vote:   
 */
contract SparkEthereum_20251127 is SparkPayloadEthereum {

    using SLLHelpers for address;

    address internal constant NEW_ALM_CONTROLLER = 0xE52d643B27601D4d2BAB2052f30cf936ed413cec;
    address internal constant SYRUP_USDT         = 0x356B8d89c1e1239Cbbb9dE4815c39A1474d5BA7D;

    constructor() {
        // PAYLOAD_ARBITRUM  = 0xC0bcbb2554D4694fe7b34bB68b9DdfbB55D896BC;
        // PAYLOAD_AVALANCHE = 0xC0bcbb2554D4694fe7b34bB68b9DdfbB55D896BC;
        // PAYLOAD_BASE      = 0x709096f46e0C53bB4ABf41051Ad1709d438A5234;
        // PAYLOAD_OPTIMISM  = 0x709096f46e0C53bB4ABf41051Ad1709d438A5234;
        // PAYLOAD_UNICHAIN  = 0x709096f46e0C53bB4ABf41051Ad1709d438A5234;
    }

    function _postExecute() internal override {
        _upgradeController(Ethereum.ALM_CONTROLLER, NEW_ALM_CONTROLLER);

        NEW_ALM_CONTROLLER.setMaxExchangeRate(Ethereum.MORPHO_VAULT_USDC_BC, 1, 10);
        NEW_ALM_CONTROLLER.setMaxExchangeRate(Ethereum.MORPHO_VAULT_DAI_1,   1, 10);
        NEW_ALM_CONTROLLER.setMaxExchangeRate(Ethereum.MORPHO_VAULT_USDS,    1, 10);
        NEW_ALM_CONTROLLER.setMaxExchangeRate(Ethereum.SUSDS,                1, 10);
        NEW_ALM_CONTROLLER.setMaxExchangeRate(Ethereum.FLUID_SUSDS,          1, 10);
        NEW_ALM_CONTROLLER.setMaxExchangeRate(Ethereum.SUSDE,                1, 10);
        NEW_ALM_CONTROLLER.setMaxExchangeRate(Ethereum.SYRUP_USDC,           1, 10);
        NEW_ALM_CONTROLLER.setMaxExchangeRate(SYRUP_USDT,                    1, 10);

        MainnetController(NEW_ALM_CONTROLLER).setMaxSlippage(Ethereum.ATOKEN_CORE_USDT,  0.99e18);
        MainnetController(NEW_ALM_CONTROLLER).setMaxSlippage(SparkLend.DAI_SPTOKEN,      0.99e18);
        MainnetController(NEW_ALM_CONTROLLER).setMaxSlippage(Ethereum.ATOKEN_PRIME_USDS, 0.99e18);
        MainnetController(NEW_ALM_CONTROLLER).setMaxSlippage(Ethereum.ATOKEN_CORE_USDC,  0.99e18);
        MainnetController(NEW_ALM_CONTROLLER).setMaxSlippage(Ethereum.ATOKEN_CORE_USDS,  0.99e18);
        MainnetController(NEW_ALM_CONTROLLER).setMaxSlippage(SparkLend.PYUSD_SPTOKEN,    0.99e18);
        MainnetController(NEW_ALM_CONTROLLER).setMaxSlippage(SparkLend.WETH_SPTOKEN,     0.99e18);
        MainnetController(NEW_ALM_CONTROLLER).setMaxSlippage(SparkLend.USDC_SPTOKEN,     0.99e18);
        MainnetController(NEW_ALM_CONTROLLER).setMaxSlippage(Ethereum.ATOKEN_CORE_USDE,  0.99e18);
        MainnetController(NEW_ALM_CONTROLLER).setMaxSlippage(SparkLend.USDS_SPTOKEN,     0.99e18);
        MainnetController(NEW_ALM_CONTROLLER).setMaxSlippage(SparkLend.USDT_SPTOKEN,     0.99e18);
    }

}
