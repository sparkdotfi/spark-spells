// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { XLayer } from "spark-address-registry/XLayer.sol";

interface IControllerLike {

    function erc4626_getDepositRateLimitKey(address token, address asset) external view returns (bytes32);

    function erc4626_getWithdrawRateLimitKey(address token) external view returns (bytes32);

    function erc4626_setMaxExchangeRate(address token, uint256 shares, uint256 maxExpectedAssets) external;

    function updateIntegrations(bytes32[] calldata ids) external;

}

interface IRateLimitsLike {

    function setRateLimitData(bytes32 key, uint256 maxAmount, uint256 slope) external;

    function setUnlimitedRateLimitData(bytes32 key) external;

}

/**
 * @title  November 19, 2026 Spark XLayer Proposal
 * @author Phoenix Labs
 * @notice Spark Savings - Onboard the Spark-curated Morpho USDC vault to the spUSDC PAU through the ERC4626 facet.
 * Forum:  https://forum.skyeco.com/t/november-19-2026-proposed-changes-to-spark-for-upcoming-spell/28390
 * Vote:   https://snapshot.org/#/s:sparkfi.eth/proposal/0x807d260ba5b828e4e886727c66b4bb5666a76a8dcf78cff89bb2584f7580ea17
 */
contract SparkXLayer_20261119 {

    bytes32 internal constant ERC4626_FACET_ID = "ERC4626_FACET";

    // PLACEHOLDER: the Spark-curated Morpho USDC vault on X-Layer is not deployed yet. Replace with the deployed
    //              address before review. Until then the tests create a bare Morpho VaultV2 at this address
    //              (VaultV2Factory.createVaultV2(XLayer.SPARK_EXECUTOR, XLayer.USDC, bytes32(0))).
    address internal constant MORPHO_VAULT_USDC = 0x3F2C1Abd139ECc99892034edCCBbcF5e1696a1bE;

    function execute() external {
        IControllerLike controller = IControllerLike(XLayer.SPUSDC_PAU_CONTROLLER);
        IRateLimitsLike rateLimits = IRateLimitsLike(XLayer.SPUSDC_PAU_RATELIMITS);

        // 6. Onboard the Spark-curated Morpho USDC vault to the spUSDC PAU through the ERC4626 facet.
        bytes32[] memory integrationIds = new bytes32[](1);
        integrationIds[0] = ERC4626_FACET_ID;

        controller.updateIntegrations(integrationIds);

        rateLimits.setRateLimitData(
            controller.erc4626_getDepositRateLimitKey(MORPHO_VAULT_USDC, XLayer.USDC),
            5_000_000e6,
            uint256(25_000_000e6) / 1 days
        );
        rateLimits.setUnlimitedRateLimitData(controller.erc4626_getWithdrawRateLimitKey(MORPHO_VAULT_USDC));

        controller.erc4626_setMaxExchangeRate(MORPHO_VAULT_USDC, 1e18, 3e6);
    }

}
