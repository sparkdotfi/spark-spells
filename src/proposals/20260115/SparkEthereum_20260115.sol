// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { Ethereum }  from "spark-address-registry/Ethereum.sol";
import { SparkLend } from "spark-address-registry/SparkLend.sol";

import { IKillSwitchOracle } from 'sparklend-kill-switch/interfaces/IKillSwitchOracle.sol';

import { SparkPayloadEthereum, SLLHelpers } from "src/SparkPayloadEthereum.sol";

import { IMorphoVaultLike, ISparkVaultV2Like } from "../../interfaces/Interfaces.sol";

/**
 * @title  January 15, 2026 Spark Ethereum Proposal
 * @author Phoenix Labs
 * @notice SparkLend - Add LBTC to Oracle Kill Switch
           Spark USDS Morpho Vault - Update Vault Roles
           Spark Blue Chip USDC Morpho Vault - Update Vault Roles
           Spark Savings:
           - Increase spUSDC Deposit Cap
           - Increase spETH Deposit Cap
           Spark Liquidity Layer:
           - Mint sUSDS to Arbitrum PSM3
           - Mint sUSDS to OP Mainnet PSM3
 * @author Phoenix Labs
 * Forum:  https://forum.sky.money/t/january-15-2026-proposed-changes-to-spark-for-upcoming-spell/27585
 * Vote:   
 */
contract SparkEthereum_20251211 is SparkPayloadEthereum {

    address internal constant SPARK_BC_USDC_MORPHO_VAULT_CURATOR_MULTISIG  = 0x38464507E02c983F20428a6E8566693fE9e422a9;
    address internal constant SPARK_USDS_MORPHO_VAULT_CURATOR_MULTISIG     = 0x38464507E02c983F20428a6E8566693fE9e422a9;
    address internal constant SPARK_BC_USDC_MORPHO_VAULT_GUARDIAN_MULTISIG = 0x38464507E02c983F20428a6E8566693fE9e422a9;
    address internal constant SPARK_USDS_MORPHO_VAULT_GUARDIAN_MULTISIG    = 0x38464507E02c983F20428a6E8566693fE9e422a9;

    address internal constant LBTC_BTC_ORACLE = 0x5c29868C58b6e15e2b962943278969Ab6a7D3212;

    constructor() {
    }

    function _postExecute() internal override {
        // Claim Reserves for USDS and DAI Markets
        address[] memory aTokens = new address[](2);
        aTokens[0] = SparkLend.DAI_SPTOKEN;
        aTokens[1] = SparkLend.USDS_SPTOKEN;

        _transferFromSparkLendTreasury(aTokens);

        // SparkLend - Add LBTC to Oracle Kill Switch
        IKillSwitchOracle(SparkLend.KILL_SWITCH_ORACLE).setOracle(LBTC_BTC_ORACLE, 0.95e8);

        // Spark USDS Morpho Vault - Update Vault Roles
        IMorphoVaultLike(Ethereum.MORPHO_VAULT_USDS).setCurator(SPARK_USDS_MORPHO_VAULT_CURATOR_MULTISIG);
        IMorphoVaultLike(Ethereum.MORPHO_VAULT_USDS).submitGuardian(SPARK_USDS_MORPHO_VAULT_GUARDIAN_MULTISIG);
        IMorphoVaultLike(Ethereum.MORPHO_VAULT_USDS).submitTimelock(10 days);

        // Spark Blue Chip USDC Morpho Vault - Update Vault Roles
        IMorphoVaultLike(Ethereum.MORPHO_VAULT_USDC_BC).setCurator(SPARK_BC_USDC_MORPHO_VAULT_CURATOR_MULTISIG);
        IMorphoVaultLike(Ethereum.MORPHO_VAULT_USDC_BC).submitGuardian(SPARK_BC_USDC_MORPHO_VAULT_GUARDIAN_MULTISIG);
        IMorphoVaultLike(Ethereum.MORPHO_VAULT_USDC_BC).submitTimelock(10 days);

        // Increase Vault Deposit Caps
        ISparkVaultV2Like(Ethereum.SPARK_VAULT_V2_SPUSDC).setDepositCap(1_000_000_000e6);
        ISparkVaultV2Like(Ethereum.SPARK_VAULT_V2_SPETH).setDepositCap(250_000e18);

        // // Mint USDS and sUSDS
        // AllocatorVault(Ethereum.ALLOCATOR_VAULT).draw(USDS_MINT_AMOUNT);
        // AllocatorBuffer(Ethereum.ALLOCATOR_BUFFER).approve(Ethereum.USDS, address(this), USDS_MINT_AMOUNT);
        // IERC20(Ethereum.USDS).transferFrom(Ethereum.ALLOCATOR_BUFFER, address(this), USDS_MINT_AMOUNT);
        // IERC20(Ethereum.USDS).approve(Ethereum.SUSDS, SUSDS_DEPOSIT_AMOUNT);
        // uint256 susdsShares = IERC4626(Ethereum.SUSDS).deposit(SUSDS_DEPOSIT_AMOUNT, address(this));

        // // Bridge to Arbitrum
        // uint256 susdsSharesOptimism = IERC4626(Ethereum.SUSDS).convertToShares(ARBITRUM_SUSDS_AMOUNT);
        // IERC20(Ethereum.SUSDS).approve(Ethereum.OPTIMISM_TOKEN_BRIDGE, susdsSharesOptimism);
        // IArbitrumTokenBridge(Ethereum.ARBITRUM_TOKEN_BRIDGE).bridgeERC20To(Ethereum.SUSDS, Optimism.SUSDS, Arbitrum.PSM3, susdsSharesOptimism, 1_000_000, "");

        // // Bridge to Optimism
        // uint256 susdsSharesOptimism = IERC4626(Ethereum.SUSDS).convertToShares(OPTIMISM_SUSDS_AMOUNT);
        // IERC20(Ethereum.SUSDS).approve(Ethereum.OPTIMISM_TOKEN_BRIDGE, susdsSharesOptimism);
        // IOptimismTokenBridge(Ethereum.OPTIMISM_TOKEN_BRIDGE).bridgeERC20To(Ethereum.SUSDS, Optimism.SUSDS, Optimism.PSM3, susdsSharesOptimism, 1_000_000, "");
    }

}
