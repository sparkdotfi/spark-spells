// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { SafeERC20, IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import { Ethereum }  from "spark-address-registry/Ethereum.sol";

import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";
import { IRateLimits }       from "spark-alm-controller/src/interfaces/IRateLimits.sol";
import { IALMProxy }         from "spark-alm-controller/src/interfaces/IALMProxy.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";

import { SparkPayloadEthereum } from "src/SparkPayloadEthereum.sol";

import { ISparkVaultV2Like, IMorphoVaultLike } from "../../interfaces/Interfaces.sol";

interface IALMProxyFreezableLike {
    function FREEZER() external returns (bytes32);
}

/**
 * @title  December 11, 2025 Spark Ethereum Proposal
 * @notice 
 * @author Phoenix Labs
 * Forum:  https://forum.sky.money/t/december-11-2025-proposed-changes-to-spark-for-upcoming-spell/27481
 * Vote:   
 */
contract SparkEthereum_20251211 is SparkPayloadEthereum {

    address internal constant ALM_PROXY_FREEZABLE    = 0x9Ad87668d49ab69EEa0AF091de970EF52b0D5178;
    address internal constant SPARK_VAULT_V2_SPPYUSD = 0x80128DbB9f07b93DDE62A6daeadb69ED14a7D354;

    uint256 internal constant AMOUNT_TO_FOUNDATION = 1_100_000e18;

    // > bc -l <<< 'scale=27; e( l(1.1)/(60 * 60 * 24 * 365) )'
    //   1.000000003022265980097387650
    uint256 internal constant TEN_PCT_APY = 1.000000003022265980097387650e27;

    constructor() {
        // PAYLOAD_AVALANCHE = 0x282dAfE8B97e2Db5053761a4601ab2E1CB976318;
        // PAYLOAD_BASE      = 0x3968a022D955Bbb7927cc011A48601B65a33F346;
    }

    function _postExecute() internal override {
        // Foundation Grant for January 2025
        IERC20(Ethereum.USDS).transfer(Ethereum.SPARK_FOUNDATION_MULTISIG, AMOUNT_TO_FOUNDATION);

        // Grant CONTROLLER Role for Relayer 1 and 2 on ALM_PROXY_FREEZABLE and Freezer role to the ALM_FREEZER_MULTISIG
        IALMProxy(ALM_PROXY_FREEZABLE).grantRole(
            IALMProxy(ALM_PROXY_FREEZABLE).CONTROLLER(),
            Ethereum.ALM_RELAYER_MULTISIG
        );
        IALMProxy(ALM_PROXY_FREEZABLE).grantRole(
            IALMProxy(ALM_PROXY_FREEZABLE).CONTROLLER(),
            Ethereum.ALM_BACKSTOP_RELAYER_MULTISIG
        );
        IALMProxy(ALM_PROXY_FREEZABLE).grantRole(
            IALMProxyFreezableLike(ALM_PROXY_FREEZABLE).FREEZER(),
            Ethereum.ALM_FREEZER_MULTISIG
        );

        // Spark Savings - Update Setter Role to ALM Proxy Freezable for spUSDC, spUSDT, spETH
        ISparkVaultV2Like(Ethereum.SPARK_VAULT_V2_SPUSDC).grantRole(ISparkVaultV2Like(Ethereum.SPARK_VAULT_V2_SPUSDC).SETTER_ROLE(), ALM_PROXY_FREEZABLE);
        ISparkVaultV2Like(Ethereum.SPARK_VAULT_V2_SPUSDT).grantRole(ISparkVaultV2Like(Ethereum.SPARK_VAULT_V2_SPUSDC).SETTER_ROLE(), ALM_PROXY_FREEZABLE);
        ISparkVaultV2Like(Ethereum.SPARK_VAULT_V2_SPETH).grantRole(ISparkVaultV2Like(Ethereum.SPARK_VAULT_V2_SPUSDC).SETTER_ROLE(),  ALM_PROXY_FREEZABLE);

        // Spark USDC Morpho Vault - Update Allocator Role to ALM Proxy Freezable
        IMorphoVaultLike(Ethereum.MORPHO_VAULT_USDC_BC).setIsAllocator(ALM_PROXY_FREEZABLE, true);

        // Spark USDS Morpho Vault - Update Allocator Role to ALM Proxy Freezable
        IMorphoVaultLike(Ethereum.MORPHO_VAULT_USDS).setIsAllocator(ALM_PROXY_FREEZABLE, true);

        // Spark Savings - Launch Spark Savings spPYUSD
        _configureVaultsV2({
            vault_        : SPARK_VAULT_V2_SPPYUSD,
            supplyCap     : 250_000_000e6,
            minVsr        : 1e27,
            maxVsr        : TEN_PCT_APY,
            depositAmount : 1e6
        });
    }

    function _configureVaultsV2(
        address vault_,
        uint256 supplyCap,
        uint256 minVsr,
        uint256 maxVsr,
        uint256 depositAmount
    ) internal {
        ISparkVaultV2Like     vault  = ISparkVaultV2Like(vault_);
        IRateLimits       rateLimits = IRateLimits(Ethereum.ALM_RATE_LIMITS);
        MainnetController controller = MainnetController(Ethereum.ALM_CONTROLLER);

        // Grant SETTER_ROLE to Spark Operations Safe
        vault.grantRole(vault.SETTER_ROLE(), ALM_PROXY_FREEZABLE);

        // Grant TAKER_ROLE to Alm Proxy
        vault.grantRole(vault.TAKER_ROLE(), Ethereum.ALM_PROXY);

        // Set VSR bounds
        vault.setVsrBounds(minVsr, maxVsr);

        // Set the supply cap
        vault.setDepositCap(supplyCap);

        // Deposit into the vault
        SafeERC20.safeIncreaseAllowance(IERC20(vault.asset()), vault_, depositAmount);
        vault.deposit(depositAmount, address(1));

        rateLimits.setUnlimitedRateLimitData(
            RateLimitHelpers.makeAddressKey(
                controller.LIMIT_SPARK_VAULT_TAKE(),
                address(vault)
            )
        );

        rateLimits.setUnlimitedRateLimitData(
            RateLimitHelpers.makeAddressAddressKey(
                controller.LIMIT_ASSET_TRANSFER(),
                vault.asset(),
                address(vault)
            )
        );
    }

}
