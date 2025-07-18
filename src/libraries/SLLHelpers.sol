// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import { IAToken } from "aave-v3-origin/src/core/contracts/interfaces/IAToken.sol";

import { IERC20 }   from 'forge-std/interfaces/IERC20.sol';
import { IERC4626 } from 'forge-std/interfaces/IERC4626.sol';

import { IMetaMorpho } from "metamorpho/interfaces/IMetaMorpho.sol";

import { MarketParams, Id } from "morpho-blue/src/interfaces/IMorpho.sol";
import { MarketParamsLib }  from "morpho-blue/src/libraries/MarketParamsLib.sol";

import { Arbitrum } from 'spark-address-registry/Arbitrum.sol';
import { Base }     from 'spark-address-registry/Base.sol';
import { Ethereum } from 'spark-address-registry/Ethereum.sol';

import { ControllerInstance }              from "spark-alm-controller/deploy/ControllerInstance.sol";
import { MainnetControllerInit }           from "spark-alm-controller/deploy/MainnetControllerInit.sol";
import { ForeignControllerInit }           from "spark-alm-controller/deploy/ForeignControllerInit.sol";
import { MainnetController }               from "spark-alm-controller/src/MainnetController.sol";
import { ForeignController }               from "spark-alm-controller/src/ForeignController.sol";
import { RateLimitHelpers, RateLimitData } from "spark-alm-controller/src/RateLimitHelpers.sol";

import { CCTPForwarder }from "xchain-helpers/forwarders/CCTPForwarder.sol";

/**
 * @notice Helper functions for Spark Liquidity Layer
 */
library SLLHelpers {

    // This is the same on all chains
    address private constant MORPHO = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;

    // This is the same on all chains
    address private constant ALM_RELAYER_BACKUP = 0x8Cc0Cb0cfB6B7e548cfd395B833c05C346534795;

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
    bytes32 private constant LIMIT_CURVE_DEPOSIT  = keccak256("LIMIT_CURVE_DEPOSIT");
    bytes32 private constant LIMIT_CURVE_SWAP     = keccak256("LIMIT_CURVE_SWAP");
    bytes32 private constant LIMIT_CURVE_WITHDRAW = keccak256("LIMIT_CURVE_WITHDRAW");

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

    /**
     * @notice Onboard a Curve pool
     */
    function onboardCurvePool(
        address controller,
        address rateLimits,
        address pool,
        uint256 maxSlippage,
        uint256 swapMax,
        uint256 swapSlope,
        uint256 depositMax,
        uint256 depositSlope,
        uint256 withdrawMax,
        uint256 withdrawSlope
    ) internal {
        MainnetController(controller).setMaxSlippage(pool, maxSlippage);
        if (swapMax != 0) {
            RateLimitHelpers.setRateLimitData(
                RateLimitHelpers.makeAssetKey(
                    LIMIT_CURVE_SWAP,
                    pool
                ),
                rateLimits,
                RateLimitData({
                    maxAmount : swapMax,
                    slope     : swapSlope
                }),
                "poolSwapLimit",
                18
            );
        }
        if (depositMax != 0) {
            RateLimitHelpers.setRateLimitData(
                RateLimitHelpers.makeAssetKey(
                    LIMIT_CURVE_DEPOSIT,
                    pool
                ),
                rateLimits,
                RateLimitData({
                    maxAmount : depositMax,
                    slope     : depositSlope
                }),
                "poolDepositLimit",
                18
            );
        }
        if (withdrawMax != 0) {
            RateLimitHelpers.setRateLimitData(
                RateLimitHelpers.makeAssetKey(
                    LIMIT_CURVE_WITHDRAW,
                    pool
                ),
                rateLimits,
                RateLimitData({
                    maxAmount : withdrawMax,
                    slope     : withdrawSlope
                }),
                "poolWithdrawLimit",
                18
            );
        }
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

    function addrToBytes32(address addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(addr)));
    }

    function upgradeMainnetController(address oldController, address newController) internal {
        MainnetControllerInit.MintRecipient[] memory mintRecipients = new MainnetControllerInit.MintRecipient[](2);
        mintRecipients[0] = MainnetControllerInit.MintRecipient({
            domain        : CCTPForwarder.DOMAIN_ID_CIRCLE_BASE,
            mintRecipient : addrToBytes32(Base.ALM_PROXY)
        });
        mintRecipients[1] = MainnetControllerInit.MintRecipient({
            domain        : CCTPForwarder.DOMAIN_ID_CIRCLE_ARBITRUM_ONE,
            mintRecipient : addrToBytes32(Arbitrum.ALM_PROXY)
        });

        MainnetControllerInit.upgradeController({
            controllerInst: ControllerInstance({
                almProxy   : Ethereum.ALM_PROXY,
                controller : newController,
                rateLimits : Ethereum.ALM_RATE_LIMITS
            }),
            configAddresses: MainnetControllerInit.ConfigAddressParams({
                freezer       : Ethereum.ALM_FREEZER,
                relayer       : Ethereum.ALM_RELAYER,
                oldController : oldController
            }),
            checkAddresses: MainnetControllerInit.CheckAddressParams({
                admin      : Ethereum.SPARK_PROXY,
                proxy      : Ethereum.ALM_PROXY,
                rateLimits : Ethereum.ALM_RATE_LIMITS,
                vault      : Ethereum.ALLOCATOR_VAULT,
                psm        : Ethereum.PSM,
                daiUsds    : Ethereum.DAI_USDS,
                cctp       : Ethereum.CCTP_TOKEN_MESSENGER
            }),
            mintRecipients: mintRecipients
        });
        MainnetController(newController).grantRole(MainnetController(newController).RELAYER(), ALM_RELAYER_BACKUP);
    }

    function upgradeForeignController(
        ControllerInstance memory controllerInst,
        ForeignControllerInit.ConfigAddressParams memory configAddresses,
        ForeignControllerInit.CheckAddressParams memory checkAddresses
    ) internal {
        ForeignControllerInit.MintRecipient[] memory mintRecipients = new ForeignControllerInit.MintRecipient[](1);
        mintRecipients[0] = ForeignControllerInit.MintRecipient({
            domain        : CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM,
            mintRecipient : addrToBytes32(Ethereum.ALM_PROXY)
        });

        ForeignControllerInit.upgradeController({
            controllerInst: controllerInst,
            configAddresses: configAddresses,
            checkAddresses: checkAddresses,
            mintRecipients: mintRecipients
        });
        ForeignController(controllerInst.controller).grantRole(ForeignController(controllerInst.controller).RELAYER(), ALM_RELAYER_BACKUP);
    }

}
