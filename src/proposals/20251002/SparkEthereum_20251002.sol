// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { Ethereum } from 'spark-address-registry/Ethereum.sol';

import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";
import { IRateLimits }       from "spark-alm-controller/src/interfaces/IRateLimits.sol";

import { SparkPayloadEthereum } from "src/SparkPayloadEthereum.sol";

interface ISparkVaultV2 {
    function asset() external view returns (address);
    function grantRole(bytes32 role, address account) external;
    function setDepositCap(uint256 newCap) external;
    function SETTER_ROLE() external view returns (bytes32);
    function setVsrBounds(uint256 minVsr_, uint256 maxVsr_) external;
    function TAKER_ROLE() external view returns (bytes32);
}

/**
 * @title  October 02, 2025 Spark Ethereum Proposal
 * @notice Spark Savings:
 *         - Launch Savings v2 Vaults for USDC, USDT, and ETH
 *         SparkLend:
 *         - Claim Accrued Reserves for USDS and DAI
 * @author Phoenix Labs
 * Forum:  https://forum.sky.money/t/october-2-2025-proposed-changes-to-spark-for-upcoming-spell/27191
 * Vote:   
 */
contract SparkEthereum_20251002 is SparkPayloadEthereum {

    // > bc -l <<< 'scale=27; e( l(1.1)/(60 * 60 * 24 * 365) )'
    //   1.000000003022265980097387650
    uint256 internal constant TEN_PCT_APY = 1.000000003022265980097387650e27;

    // > bc -l <<< 'scale=27; e( l(1.05)/(60 * 60 * 24 * 365) )'
    //   1.000000001547125957863212448
    uint256 internal constant FIVE_PCT_APY = 1.000000001547125957863212448e27;

    function _postExecute() internal override {
        // Launch Savings v2 Vaults for USDC, USDT, and ETH
        _configureVaultsV2({
            vault_    : Ethereum.SPARK_VAULT_V2_SPUSDC,
            supplyCap : 50_000_000e6,
            minVsr    : 1e27,
            maxVsr    : TEN_PCT_APY
        });

        _configureVaultsV2({
            vault_    : Ethereum.SPARK_VAULT_V2_SPUSDT,
            supplyCap : 50_000_000e6,
            minVsr    : 1e27,
            maxVsr    : TEN_PCT_APY
        });

        _configureVaultsV2({
            vault_    : Ethereum.SPARK_VAULT_V2_SPETH,
            supplyCap : 10_000e18,
            minVsr    : 1e27,
            maxVsr    : FIVE_PCT_APY
        });

        // Withdraw USDS and DAI Reserves from SparkLend
        address[] memory aTokens = new address[](2);
        aTokens[0] = Ethereum.DAI_SPTOKEN;
        aTokens[1] = Ethereum.USDS_SPTOKEN;

        _transferFromSparkLendTreasury(aTokens);
    }

    function _configureVaultsV2(
        address vault_,
        uint256 supplyCap,
        uint256 minVsr,
        uint256 maxVsr
    ) internal {
        ISparkVaultV2     vault      = ISparkVaultV2(vault_);
        IRateLimits       rateLimits = IRateLimits(Ethereum.ALM_RATE_LIMITS);
        MainnetController controller = MainnetController(Ethereum.ALM_CONTROLLER);

        // Grant SETTER_ROLE to Spark Operations Safe
        vault.grantRole(vault.SETTER_ROLE(), Ethereum.ALM_OPS_MULTISIG);

        // Grant TAKER_ROLE to Alm Proxy
        vault.grantRole(vault.TAKER_ROLE(), Ethereum.ALM_PROXY);

        // Set VSR bounds
        vault.setVsrBounds(minVsr, maxVsr);

        // Set the supply cap
        vault.setDepositCap(supplyCap);

        rateLimits.setUnlimitedRateLimitData(
            RateLimitHelpers.makeAssetKey(
                controller.LIMIT_SPARK_VAULT_TAKE(),
                address(vault)
            )
        );

        rateLimits.setUnlimitedRateLimitData(
            RateLimitHelpers.makeAssetDestinationKey(
                controller.LIMIT_ASSET_TRANSFER(),
                vault.asset(),
                address(vault)
            )
        );
    }

}
