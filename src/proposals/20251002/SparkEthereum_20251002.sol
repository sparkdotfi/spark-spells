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
 * Forum:  https://forum.sky.money/t/september-18-2025-proposed-changes-to-spark-for-upcoming-spell/27153
 * Vote:   
 */
contract SparkEthereum_20251002 is SparkPayloadEthereum {

    function _postExecute() internal override {
        // Launch Savings v2 Vaults for USDC, USDT, and ETH

        // NOTE: 10% APY for SPUSDC and SPUSDT 
        // > bc -l <<< 'scale=27; e( l(1.1)/(60 * 60 * 24 * 365) )'
        //   1.000000003022265980097387650
        _configureVaultsV2(Ethereum.SPARK_VAULT_V2_SPUSDC, 50_000_000e6, 1e27, 1.000000003022265980097387650e27);
        _configureVaultsV2(Ethereum.SPARK_VAULT_V2_SPUSDT, 50_000_000e6, 1e27, 1.000000003022265980097387650e27);

        // NOTE: 5% APY for SPETH
        // ❯ bc -l <<< 'scale=27; e( l(1.05)/(60 * 60 * 24 * 365) )'
        // 1.000000001547125957863212448
        _configureVaultsV2(Ethereum.SPARK_VAULT_V2_SPETH,  10_000e18, 1e27, 1.000000001547125957863212448e27);

        // Withdraw USDS and DAI Reserves from SparkLend
        address[] memory aTokens = new address[](2);
        aTokens[0] = Ethereum.DAI_SPTOKEN;
        aTokens[1] = Ethereum.USDS_SPTOKEN;

        _transferFromSparkLendTreasury(aTokens);
    }

    function _configureVaultsV2(
        address vault,
        uint256 supplyCap,
        uint256 minVsr,
        uint256 maxVsr
    ) internal {
        // Grant SETTER_ROLE to Spark Operations Safe
        ISparkVaultV2(vault).grantRole(ISparkVaultV2(vault).SETTER_ROLE(), Ethereum.ALM_OPS_MULTISIG);

        // Grant TAKER_ROLE to Alm Proxy
        ISparkVaultV2(vault).grantRole(ISparkVaultV2(vault).TAKER_ROLE(), Ethereum.ALM_PROXY);

        // Set VSR bounds
        ISparkVaultV2(vault).setVsrBounds(minVsr, maxVsr);

        // Set the supply cap
        ISparkVaultV2(vault).setDepositCap(supplyCap);

        IRateLimits(Ethereum.ALM_RATE_LIMITS).setUnlimitedRateLimitData(
            RateLimitHelpers.makeAssetKey(
                MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_SPARK_VAULT_TAKE(),
                vault
            )
        );

        IRateLimits(Ethereum.ALM_RATE_LIMITS).setUnlimitedRateLimitData(
            RateLimitHelpers.makeAssetDestinationKey(
                MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_ASSET_TRANSFER(),
                ISparkVaultV2(vault).asset(),
                vault
            )
        );
    }

}
