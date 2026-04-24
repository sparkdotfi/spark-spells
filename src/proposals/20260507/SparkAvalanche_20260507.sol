// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { Avalanche }  from "spark-address-registry/Avalanche.sol";

import { ForeignController } from "spark-alm-controller/src/ForeignController.sol";
import { IRateLimits }       from "spark-alm-controller/src/interfaces/IRateLimits.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";

import { SparkPayloadAvalanche } from "src/SparkPayloadAvalanche.sol";

interface IEndpointV2 {
    function setConfig(address receiver, address uln, SetConfigParam[] memory configParams) external;
}

struct SetConfigParam {
    uint32 eid;
    uint32 configType;
    bytes  config;
}

/**
 * @title  May 7, 2026 Spark Avalanche Proposal
 * @author Phoenix Labs
 * @notice Spark Liquidity Layer:
 *         - Offboard Aave USDC.
 *         - Update Bridge DVN Configuration.
 * Forum:  
 * Vote:   
 */
contract SparkAvalanche_20260507 is SparkPayloadAvalanche {

    // the formal properties are documented in the setter functions
    struct UlnConfig {
        uint64    confirmations;
        // we store the length of required DVNs and optional DVNs instead of using DVN.length directly to save gas
        uint8     requiredDVNCount; // 0 indicate DEFAULT, NIL_DVN_COUNT indicate NONE (to override the value of default)
        uint8     optionalDVNCount; // 0 indicate DEFAULT, NIL_DVN_COUNT indicate NONE (to override the value of default)
        uint8     optionalDVNThreshold; // (0, optionalDVNCount]
        address[] requiredDVNs; // no duplicates. sorted an an ascending order. allowed overlap with optionalDVNs
        address[] optionalDVNs; // no duplicates. sorted an an ascending order. allowed overlap with requiredDVNs
    }

    uint32 internal constant ETHEREUM_MAINNET_EID = 30101;

    address internal constant LAYERZERO_ENDPOINT_V2 = 0x1a44076050125825900e736c501f859c50fE728c;
    address internal constant RECEIVE_ULN_302       = 0xbf3521d309642FA9B1c91A08609505BA09752c61;

    function execute() external {
        // 1. Update Bridge DVN Configuration

        address[] memory requiredDVNs = new address[](0);

        address[] memory optionalDVNs = new address[](7);
        optionalDVNs[0] = 0x07C05EaB7716AcB6f83ebF6268F8EECDA8892Ba1;  // Horizen
        optionalDVNs[1] = 0x962F502A63F5FBeB44DC9ab932122648E8352959;  // LayerZero Labs
        optionalDVNs[2] = 0xa59BA433ac34D2927232918Ef5B2eaAfcF130BA5;  // Nethermind
        optionalDVNs[3] = 0xbe57e9E7d9eB16B92C6383792aBe28D64a18c0F1;  // Deutsche Telekom
        optionalDVNs[4] = 0xcC49E6fca014c77E1Eb604351cc1E08C84511760;  // Canary
        optionalDVNs[5] = 0xE4193136B92bA91402313e95347c8e9FAD8d27d0;  // Luganodes
        optionalDVNs[6] = 0xE94aE34DfCC87A61836938641444080B98402c75;  // P2P

        UlnConfig memory ulnConfig = UlnConfig({
            confirmations        : 15,
            requiredDVNCount     : 255,
            optionalDVNCount     : 7,
            optionalDVNThreshold : 4,
            requiredDVNs         : requiredDVNs,
            optionalDVNs         : optionalDVNs
        });

        SetConfigParam[] memory configParams = new SetConfigParam[](1);
        configParams[0] = SetConfigParam({
            eid        : ETHEREUM_MAINNET_EID,
            configType : 2,
            config     : abi.encode(ulnConfig)
        });

        IEndpointV2(LAYERZERO_ENDPOINT_V2).setConfig(Avalanche.SPARK_RECEIVER, RECEIVE_ULN_302, configParams);

        // 2. Offboard Aave USDC.

        ForeignController almController = ForeignController(Avalanche.ALM_CONTROLLER);
        IRateLimits       rateLimits    = IRateLimits(Avalanche.ALM_RATE_LIMITS);

        bytes32 aaveDepositKey  = almController.LIMIT_AAVE_DEPOSIT();
        bytes32 aaveWithdrawKey = almController.LIMIT_AAVE_WITHDRAW();

        bytes32 ATOKEN_CORE_USDC_DEPOSIT_KEY  = RateLimitHelpers.makeAddressKey(aaveDepositKey,  Avalanche.ATOKEN_CORE_USDC);
        bytes32 ATOKEN_CORE_USDC_WITHDRAW_KEY = RateLimitHelpers.makeAddressKey(aaveWithdrawKey, Avalanche.ATOKEN_CORE_USDC);

        rateLimits.setRateLimitData(ATOKEN_CORE_USDC_DEPOSIT_KEY,  0, 0);
        rateLimits.setRateLimitData(ATOKEN_CORE_USDC_WITHDRAW_KEY, 0, 0);
    }

}
