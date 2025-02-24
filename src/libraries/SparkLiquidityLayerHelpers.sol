// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import { IERC20 }   from 'forge-std/interfaces/IERC20.sol';
import { IERC4626 } from 'forge-std/interfaces/IERC4626.sol';

import { IAToken } from "aave-v3-origin/src/core/contracts/interfaces/IAToken.sol";

import { IMetaMorpho, Id } from "metamorpho/interfaces/IMetaMorpho.sol";
import { MarketParams }    from "morpho-blue/src/interfaces/IMorpho.sol";
import { MarketParamsLib } from "morpho-blue/src/libraries/MarketParamsLib.sol";

import { RateLimitHelpers, RateLimitData } from "spark-alm-controller/src/RateLimitHelpers.sol";

/**
 * @notice Helper functions for Spark Liquidity Layer
 */
library SparkLiquidityLayerHelpers {

    // This is the same on all chains
    address private constant MORPHO = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;

    bytes32 private constant LIMIT_4626_DEPOSIT   = keccak256("LIMIT_4626_DEPOSIT");
    bytes32 private constant LIMIT_4626_WITHDRAW  = keccak256("LIMIT_4626_WITHDRAW");
    bytes32 private constant LIMIT_AAVE_DEPOSIT   = keccak256("LIMIT_AAVE_DEPOSIT");
    bytes32 private constant LIMIT_AAVE_WITHDRAW  = keccak256("LIMIT_AAVE_WITHDRAW");
    bytes32 private constant LIMIT_USDS_MINT      = keccak256("LIMIT_USDS_MINT");
    bytes32 private constant LIMIT_USDS_TO_USDC   = keccak256("LIMIT_USDS_TO_USDC");
    bytes32 private constant LIMIT_USDC_TO_CCTP   = keccak256("LIMIT_USDC_TO_CCTP");
    bytes32 private constant LIMIT_USDC_TO_DOMAIN = keccak256("LIMIT_USDC_TO_DOMAIN");
    bytes32 private constant LIMIT_PSM_DEPOSIT    = keccak256("LIMIT_PSM_DEPOSIT");
    bytes32 private constant LIMIT_PSM_WITHDRAW   = keccak256("LIMIT_PSM_WITHDRAW");

    /**
     * @notice Activate the bare minimum for Spark Liquidity Layer
     * @dev Sets PSM and CCTP rate limits.
     */
    function activateSparkLiquidityLayer(
        address rateLimits,
        address usdc,
        address usds,
        address susds,
        RateLimitData memory usdcDeposit,
        RateLimitData memory usdcWithdraw,
        RateLimitData memory cctpEthereumDeposit
    ) internal {
        // PSM USDC
        RateLimitHelpers.setRateLimitData(
            RateLimitHelpers.makeAssetKey(
                LIMIT_PSM_DEPOSIT,
                usdc
            ),
            rateLimits,
            usdcDeposit,
            "psmUsdcDepositLimit",
            6
        );
        RateLimitHelpers.setRateLimitData(
            RateLimitHelpers.makeAssetKey(
                LIMIT_PSM_WITHDRAW,
                usdc
            ),
            rateLimits,
            usdcWithdraw,
            "psmUsdcWithdrawLimit",
            6
        );

        // PSM USDS
        RateLimitHelpers.setRateLimitData(
            RateLimitHelpers.makeAssetKey(
                LIMIT_PSM_DEPOSIT,
                usds
            ),
            rateLimits,
            RateLimitHelpers.unlimitedRateLimit(),
            "psmUsdsDepositLimit",
            18
        );
        RateLimitHelpers.setRateLimitData(
            RateLimitHelpers.makeAssetKey(
                LIMIT_PSM_WITHDRAW,
                usds
            ),
            rateLimits,
            RateLimitHelpers.unlimitedRateLimit(),
            "psmUsdsWithdrawLimit",
            18
        );

        // PSM sUSDS
        RateLimitHelpers.setRateLimitData(
            RateLimitHelpers.makeAssetKey(
                LIMIT_PSM_DEPOSIT,
                susds
            ),
            rateLimits,
            RateLimitHelpers.unlimitedRateLimit(),
            "psmSusdsDepositLimit",
            18
        );
        RateLimitHelpers.setRateLimitData(
            RateLimitHelpers.makeAssetKey(
                LIMIT_PSM_WITHDRAW,
                susds
            ),
            rateLimits,
            RateLimitHelpers.unlimitedRateLimit(),
            "psmSusdsWithdrawLimit",
            18
        );

        // CCTP
        RateLimitHelpers.setRateLimitData(
            LIMIT_USDC_TO_CCTP,
            rateLimits,
            RateLimitHelpers.unlimitedRateLimit(),
            "usdcToCctpLimit",
            6
        );
        RateLimitHelpers.setRateLimitData(
            RateLimitHelpers.makeDomainKey(
                LIMIT_USDC_TO_DOMAIN,
                0  // Ethereum domain id (https://developers.circle.com/stablecoins/evm-smart-contracts)
            ),
            rateLimits,
            cctpEthereumDeposit,
            "usdcToCctpEthereumLimit",
            6
        );
    }

    /**
     * @notice Onboard an Aave token
     * @dev This will set the deposit to the given numbers with
     *      the withdraw limit set to unlimited.
     */
    function onboardAaveToken(
        address rateLimits,
        address token,
        uint256 depositMax,
        uint256 depositSlope
    ) internal {
        IERC20 underlying = IERC20(IAToken(token).UNDERLYING_ASSET_ADDRESS());

        RateLimitHelpers.setRateLimitData(
            RateLimitHelpers.makeAssetKey(
                LIMIT_AAVE_DEPOSIT,
                token
            ),
            rateLimits,
            RateLimitData({
                maxAmount : depositMax,
                slope     : depositSlope
            }),
            "atokenDepositLimit",
            underlying.decimals()
        );
        RateLimitHelpers.setRateLimitData(
            RateLimitHelpers.makeAssetKey(
                LIMIT_AAVE_WITHDRAW,
                token
            ),
            rateLimits,
            RateLimitHelpers.unlimitedRateLimit(),
            "atokenWithdrawLimit",
            underlying.decimals()
        );
    }

    /**
     * @notice Onboard an ERC4626 vault
     * @dev This will set the deposit to the given numbers with
     *      the withdraw limit set to unlimited.
     */
    function onboardERC4626Vault(
        address rateLimits,
        address vault,
        uint256 depositMax,
        uint256 depositSlope
    ) internal {
        IERC20 asset = IERC20(IERC4626(vault).asset());

        RateLimitHelpers.setRateLimitData(
            RateLimitHelpers.makeAssetKey(
                LIMIT_4626_DEPOSIT,
                vault
            ),
            rateLimits,
            RateLimitData({
                maxAmount : depositMax,
                slope     : depositSlope
            }),
            "vaultDepositLimit",
            asset.decimals()
        );
        RateLimitHelpers.setRateLimitData(
            RateLimitHelpers.makeAssetKey(
                LIMIT_4626_WITHDRAW,
                vault
            ),
            rateLimits,
            RateLimitHelpers.unlimitedRateLimit(),
            "vaultWithdrawLimit",
            asset.decimals()
        );
    }

    function morphoIdleMarket(
        address asset
    ) internal pure returns (MarketParams memory) {
        return MarketParams({
            loanToken:       asset,
            collateralToken: address(0),
            oracle:          address(0),
            irm:             address(0),
            lltv:            0
        });
    }

    /**
     * @notice Activate a Morpho Vault
     * @dev This will do the following:
     *      - Add the relayer as an allocator
     *      - Add the idle market for the underlying asset with unlimited size
     *      - Set the supply queue to the idle market
     */
    function activateMorphoVault(
        address vault,
        address relayer
    ) internal {
        IERC20 asset = IERC20(IERC4626(vault).asset());
        MarketParams memory idleMarket = morphoIdleMarket(address(asset));
        
        IMetaMorpho(vault).setIsAllocator(
            relayer,
            true
        );
        IMetaMorpho(vault).submitCap(
            idleMarket,
            type(uint184).max
        );
        IMetaMorpho(vault).acceptCap(
            idleMarket
        );
        Id[] memory supplyQueue = new Id[](1);
        supplyQueue[0] = MarketParamsLib.id(idleMarket);
        IMetaMorpho(vault).setSupplyQueue(supplyQueue);
    }

    function setUSDSMintRateLimit(
        address rateLimits,
        uint256 maxAmount,
        uint256 slope
    ) internal {
        RateLimitHelpers.setRateLimitData(
            LIMIT_USDS_MINT,
            rateLimits,
            RateLimitData({
                maxAmount : maxAmount,
                slope     : slope
            }),
            "USDS mint limit",
            18
        );
    }

    function setUSDSToUSDCRateLimit(
        address rateLimits,
        uint256 maxUsdcAmount,
        uint256 slope
    ) internal {
        RateLimitHelpers.setRateLimitData(
            LIMIT_USDS_TO_USDC,
            rateLimits,
            RateLimitData({
                maxAmount : maxUsdcAmount,
                slope     : slope
            }),
            "Swap USDS to USDC limit",
            6
        );
    }

    function setUSDCToCCTPRateLimit(
        address rateLimits,
        uint256 maxUsdcAmount,
        uint256 slope
    ) internal {
        RateLimitHelpers.setRateLimitData(
            LIMIT_USDC_TO_CCTP,
            rateLimits,
            RateLimitData({
                maxAmount : maxUsdcAmount,
                slope     : slope
            }),
            "Send USDC to CCTP general limit",
            6
        );
    }

    function setUSDCToDomainRateLimit(
        address rateLimits,
        uint32  destinationDomain,
        uint256 maxUsdcAmount,
        uint256 slope
    ) internal {
        RateLimitHelpers.setRateLimitData(
            RateLimitHelpers.makeDomainKey(LIMIT_USDC_TO_DOMAIN, destinationDomain),
            rateLimits,
            RateLimitData({
                maxAmount : maxUsdcAmount,
                slope     : slope
            }),
            "Send USDC via CCTP to a specific domain limit",
            6
        );
    }
}
