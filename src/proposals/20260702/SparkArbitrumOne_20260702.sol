// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IERC20, SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import { Ethereum } from "spark-address-registry/Ethereum.sol";

import { ForeignController } from "spark-alm-controller/src/ForeignController.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";
import { IRateLimits }       from "spark-alm-controller/src/interfaces/IRateLimits.sol";

import { Arbitrum, SparkPayloadArbitrumOne } from "../../SparkPayloadArbitrumOne.sol";

interface IALMProxyFreezableLike {

    function ALLOCATOR_ROLE() external view returns (bytes32);

    function FREEZER_ROLE() external view returns (bytes32);

    function grantRole(bytes32 role, address account) external;

}

interface ISparkVaultV2 {

    function asset() external view returns (address);

    function deposit(uint256 assets, address receiver) external returns (uint256 shares);

    function grantRole(bytes32 role, address account) external;

    function setDepositCap(uint256 newCap) external;

    function SETTER_ROLE() external view returns (bytes32);

    function setVsrBounds(uint256 minVsr_, uint256 maxVsr_) external;

    function TAKER_ROLE() external view returns (bytes32);

}

/**
 * @title  July 2, 2026 Spark Arbitrum Proposal
 * @notice Spark Liquidity Layer - Update Controller to v1.8
 * @author Phoenix Labs
 * Forum:  https://forum.skyeco.com/t/july-2-2026-proposed-changes-to-spark-for-upcoming-spell/27982
 * Vote:   https://snapshot.box/#/s:sparkfi.eth/proposal/0xbf91a06534d47861b5810c646ccc1560eb7730ff14ab1c16a1e0b92fc535a073
 */
contract SparkArbitrumOne_20260702 is SparkPayloadArbitrumOne {

    address internal constant ALM_PROXY_FREEZABLE   = 0x4eE67c8Db1BAa6ddE99d936C7D313B5d31e8fa38;
    address internal constant SPARK_VAULT_V2_SPUSDT = 0x45d91340B3B7B96985A72b5c678F7D9e8D664b62;
    address internal constant USDT_OFT              = 0x14E4A1B13bf7F943c8ff7C51fb60FA964A298D92;

    uint32  internal constant LZ_ENDPOINT_ETHEREUM = 30101;

    // > bc -l <<< 'scale=27; e( l(1.06)/(60 * 60 * 24 * 365) )'
    //   1.000000001847694957439350562
    uint256 internal constant SIX_PCT_APY = 1.000000001847694957439350562e27;

    function execute() external {
        // Grant ALLOCATOR_ROLE Role for Relayer 1 and 2 on ALM_PROXY_FREEZABLE and FREEZER_ROLE role to the ALM_FREEZER_MULTISIG
        IALMProxyFreezableLike proxy = IALMProxyFreezableLike(ALM_PROXY_FREEZABLE);

        proxy.grantRole(proxy.ALLOCATOR_ROLE(), Arbitrum.ALM_RELAYER_MULTISIG);
        proxy.grantRole(proxy.ALLOCATOR_ROLE(), Arbitrum.ALM_BACKSTOP_RELAYER_MULTISIG);
        proxy.grantRole(proxy.FREEZER_ROLE(),   Arbitrum.ALM_FREEZER_MULTISIG);

        _configureVaultsV2({
            vault_        : SPARK_VAULT_V2_SPUSDT,
            supplyCap     : 250_000_000e6,
            minVsr        : 1e27,
            maxVsr        : SIX_PCT_APY,
            depositAmount : 1e6
        });

        // Enable USDT Bridging to Ethereum.
        ForeignController foreignController = ForeignController(Arbitrum.ALM_CONTROLLER);
        IRateLimits       rateLimits        = IRateLimits(Arbitrum.ALM_RATE_LIMITS);

        foreignController.setLayerZeroRecipient(
            LZ_ENDPOINT_ETHEREUM,
            bytes32(uint256(uint160(Ethereum.ALM_PROXY)))
        );

        rateLimits.setUnlimitedRateLimitData(
            keccak256(
                abi.encode(
                    foreignController.LIMIT_LAYERZERO_TRANSFER(),
                    USDT_OFT,
                    LZ_ENDPOINT_ETHEREUM
                )
            )
        );
    }

    function _configureVaultsV2(
        address vault_,
        uint256 supplyCap,
        uint256 minVsr,
        uint256 maxVsr,
        uint256 depositAmount
    ) internal {
        ISparkVaultV2     vault      = ISparkVaultV2(vault_);
        IRateLimits       rateLimits = IRateLimits(Arbitrum.ALM_RATE_LIMITS);
        ForeignController controller = ForeignController(Arbitrum.ALM_CONTROLLER);

        // Grant SETTER_ROLE to Spark Operations Safe
        vault.grantRole(vault.SETTER_ROLE(), ALM_PROXY_FREEZABLE);

        // Grant TAKER_ROLE to Alm Proxy
        vault.grantRole(vault.TAKER_ROLE(), Arbitrum.ALM_PROXY);

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
