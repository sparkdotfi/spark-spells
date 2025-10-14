// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;

import { IAToken } from "aave-v3-origin/src/core/contracts/interfaces/IAToken.sol";

import { IERC20 }   from "forge-std/interfaces/IERC20.sol";
import { IERC4626 } from "forge-std/interfaces/IERC4626.sol";

import { IMetaMorpho } from "metamorpho/interfaces/IMetaMorpho.sol";

import { MarketParams, Id } from "morpho-blue/src/interfaces/IMorpho.sol";
import { MarketParamsLib }  from "morpho-blue/src/libraries/MarketParamsLib.sol";

import { Arbitrum } from "spark-address-registry/Arbitrum.sol";
import { Base }     from "spark-address-registry/Base.sol";
import { Ethereum } from "spark-address-registry/Ethereum.sol";
import { Optimism } from "spark-address-registry/Optimism.sol";
import { Unichain } from "spark-address-registry/Unichain.sol";

import { ControllerInstance }    from "spark-alm-controller/deploy/ControllerInstance.sol";
import { MainnetControllerInit } from "spark-alm-controller/deploy/MainnetControllerInit.sol";
import { ForeignControllerInit } from "spark-alm-controller/deploy/ForeignControllerInit.sol";
import { IRateLimits }           from "spark-alm-controller/src/interfaces/IRateLimits.sol";
import { MainnetController }     from "spark-alm-controller/src/MainnetController.sol";
import { RateLimitHelpers }      from "spark-alm-controller/src/RateLimitHelpers.sol";

import { CCTPForwarder } from "xchain-helpers/forwarders/CCTPForwarder.sol";

/**
 * @notice Helper functions for Spark Liquidity Layer
 */
library SLLHelpers {

    struct RateLimitData {
        uint256 maxAmount;
        uint256 slope;
    }

    // This is the same on all chains
    address internal constant MORPHO = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;

    bytes32 internal constant LIMIT_4626_DEPOSIT   = keccak256("LIMIT_4626_DEPOSIT");
    bytes32 internal constant LIMIT_4626_WITHDRAW  = keccak256("LIMIT_4626_WITHDRAW");
    bytes32 internal constant LIMIT_AAVE_DEPOSIT   = keccak256("LIMIT_AAVE_DEPOSIT");
    bytes32 internal constant LIMIT_AAVE_WITHDRAW  = keccak256("LIMIT_AAVE_WITHDRAW");
    bytes32 internal constant LIMIT_USDS_MINT      = keccak256("LIMIT_USDS_MINT");
    bytes32 internal constant LIMIT_USDS_TO_USDC   = keccak256("LIMIT_USDS_TO_USDC");
    bytes32 internal constant LIMIT_USDC_TO_CCTP   = keccak256("LIMIT_USDC_TO_CCTP");
    bytes32 internal constant LIMIT_USDC_TO_DOMAIN = keccak256("LIMIT_USDC_TO_DOMAIN");
    bytes32 internal constant LIMIT_PSM_DEPOSIT    = keccak256("LIMIT_PSM_DEPOSIT");
    bytes32 internal constant LIMIT_PSM_WITHDRAW   = keccak256("LIMIT_PSM_WITHDRAW");
    bytes32 internal constant LIMIT_CURVE_DEPOSIT  = keccak256("LIMIT_CURVE_DEPOSIT");
    bytes32 internal constant LIMIT_CURVE_SWAP     = keccak256("LIMIT_CURVE_SWAP");
    bytes32 internal constant LIMIT_CURVE_WITHDRAW = keccak256("LIMIT_CURVE_WITHDRAW");

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
        setRateLimitData(
            RateLimitHelpers.makeAssetKey(
                LIMIT_PSM_DEPOSIT,
                usdc
            ),
            rateLimits,
            usdcDeposit.maxAmount,
            usdcDeposit.slope,
            6
        );

        setRateLimitData(
            RateLimitHelpers.makeAssetKey(
                LIMIT_PSM_WITHDRAW,
                usdc
            ),
            rateLimits,
            usdcWithdraw.maxAmount,
            usdcWithdraw.slope,
            6
        );

        // PSM USDS
        IRateLimits(rateLimits).setUnlimitedRateLimitData(
            RateLimitHelpers.makeAssetKey(
                LIMIT_PSM_DEPOSIT,
                usds
            )
        );

        IRateLimits(rateLimits).setUnlimitedRateLimitData(
            RateLimitHelpers.makeAssetKey(
                LIMIT_PSM_WITHDRAW,
                usds
            )
        );

        // PSM sUSDS
        IRateLimits(rateLimits).setUnlimitedRateLimitData(
            RateLimitHelpers.makeAssetKey(
                LIMIT_PSM_DEPOSIT,
                susds
            )
        );

        IRateLimits(rateLimits).setUnlimitedRateLimitData(
            RateLimitHelpers.makeAssetKey(
                LIMIT_PSM_WITHDRAW,
                susds
            )
        );

        // CCTP
        IRateLimits(rateLimits).setUnlimitedRateLimitData(
            LIMIT_USDC_TO_CCTP
        );

        setRateLimitData(
            RateLimitHelpers.makeDomainKey(
                LIMIT_USDC_TO_DOMAIN,
                0  // Ethereum domain id (https://developers.circle.com/stablecoins/evm-smart-contracts)
            ),
            rateLimits,
            cctpEthereumDeposit.maxAmount,
            cctpEthereumDeposit.slope,
            6
        );
    }

    /**
     * @notice Configure an Aave token
     * @dev This will set the deposit to the given numbers with
     *      the withdraw limit set to unlimited.
     */
    function configureAaveToken(
        address rateLimits,
        address token,
        uint256 depositMax,
        uint256 depositSlope
    ) internal {
        IERC20 underlying = IERC20(IAToken(token).UNDERLYING_ASSET_ADDRESS());

        setRateLimitData(
            RateLimitHelpers.makeAssetKey(
                LIMIT_AAVE_DEPOSIT,
                token
            ),
            rateLimits,
            depositMax,
            depositSlope,
            underlying.decimals()
        );

        IRateLimits(rateLimits).setUnlimitedRateLimitData(
            RateLimitHelpers.makeAssetKey(
                LIMIT_AAVE_WITHDRAW,
                token
            )
        );
    }

    /**
     * @notice Configure an ERC4626 vault
     * @dev This will set the deposit to the given numbers with
     *      the withdraw limit set to unlimited.
     */
    function configureERC4626Vault(
        address rateLimits,
        address vault,
        uint256 depositMax,
        uint256 depositSlope
    ) internal {
        IERC20 asset = IERC20(IERC4626(vault).asset());

        setRateLimitData(
            RateLimitHelpers.makeAssetKey(
                LIMIT_4626_DEPOSIT,
                vault
            ),
            rateLimits,
            depositMax,
            depositSlope,
            asset.decimals()
        );

        IRateLimits(rateLimits).setUnlimitedRateLimitData(
            RateLimitHelpers.makeAssetKey(
                LIMIT_4626_WITHDRAW,
                vault
            )
        );
    }

    /**
     * @notice Onboard a Curve pool
     */
    function configureCurvePool(
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
            setRateLimitData(
                RateLimitHelpers.makeAssetKey(
                    LIMIT_CURVE_SWAP,
                    pool
                ),
                rateLimits,
                swapMax,
                swapSlope,
                18
            );
        }

        if (depositMax != 0) {
            setRateLimitData(
                RateLimitHelpers.makeAssetKey(
                    LIMIT_CURVE_DEPOSIT,
                    pool
                ),
                rateLimits,
                depositMax,
                depositSlope,
                18
            );
        }

        if (withdrawMax != 0) {
            setRateLimitData(
                RateLimitHelpers.makeAssetKey(
                    LIMIT_CURVE_WITHDRAW,
                    pool
                ),
                rateLimits,
                withdrawMax,
                withdrawSlope,
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
        setRateLimitData(
            LIMIT_USDS_MINT,
            rateLimits,
            maxAmount,
            slope,
            18
        );
    }

    function setUSDSToUSDCRateLimit(
        address rateLimits,
        uint256 maxUsdcAmount,
        uint256 slope
    ) internal {
        setRateLimitData(
            LIMIT_USDS_TO_USDC,
            rateLimits,
            maxUsdcAmount,
            slope,
            6
        );
    }

    function setUSDCToCCTPRateLimit(
        address rateLimits,
        uint256 maxUsdcAmount,
        uint256 slope
    ) internal {
        setRateLimitData(
            LIMIT_USDC_TO_CCTP,
            rateLimits,
            maxUsdcAmount,
            slope,
            6
        );
    }

    function setUSDCToDomainRateLimit(
        address rateLimits,
        uint32  destinationDomain,
        uint256 maxUsdcAmount,
        uint256 slope
    ) internal {
        setRateLimitData(
            RateLimitHelpers.makeDomainKey(LIMIT_USDC_TO_DOMAIN, destinationDomain),
            rateLimits,
            maxUsdcAmount,
            slope,
            6
        );
    }

    function addrToBytes32(address addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(addr)));
    }

    function upgradeMainnetController(address oldController, address newController) internal {
        MainnetControllerInit.MintRecipient[] memory mintRecipients = new MainnetControllerInit.MintRecipient[](4);

        mintRecipients[0] = MainnetControllerInit.MintRecipient({
            domain        : CCTPForwarder.DOMAIN_ID_CIRCLE_BASE,
            mintRecipient : addrToBytes32(Base.ALM_PROXY)
        });

        mintRecipients[1] = MainnetControllerInit.MintRecipient({
            domain        : CCTPForwarder.DOMAIN_ID_CIRCLE_ARBITRUM_ONE,
            mintRecipient : addrToBytes32(Arbitrum.ALM_PROXY)
        });

        mintRecipients[2] = MainnetControllerInit.MintRecipient({
            domain        : CCTPForwarder.DOMAIN_ID_CIRCLE_OPTIMISM,
            mintRecipient : addrToBytes32(Optimism.ALM_PROXY)
        });

        mintRecipients[3] = MainnetControllerInit.MintRecipient({
            domain        : CCTPForwarder.DOMAIN_ID_CIRCLE_UNICHAIN,
            mintRecipient : addrToBytes32(Unichain.ALM_PROXY)
        });

        MainnetControllerInit.LayerZeroRecipient[] memory layerZeroRecipients = new MainnetControllerInit.LayerZeroRecipient[](0);

        MainnetControllerInit.MaxSlippageParams[] memory maxSlippageParams = new MainnetControllerInit.MaxSlippageParams[](3);

        maxSlippageParams[0] = MainnetControllerInit.MaxSlippageParams({
            pool        : Ethereum.CURVE_SUSDSUSDT,
            maxSlippage : MainnetController(Ethereum.ALM_CONTROLLER).maxSlippages(Ethereum.CURVE_SUSDSUSDT)
        });

        maxSlippageParams[1] = MainnetControllerInit.MaxSlippageParams({
            pool        : Ethereum.CURVE_PYUSDUSDC,
            maxSlippage : MainnetController(Ethereum.ALM_CONTROLLER).maxSlippages(Ethereum.CURVE_PYUSDUSDC)
        });

        maxSlippageParams[2] = MainnetControllerInit.MaxSlippageParams({
            pool        : Ethereum.CURVE_USDCUSDT,
            maxSlippage : MainnetController(Ethereum.ALM_CONTROLLER).maxSlippages(Ethereum.CURVE_USDCUSDT)
        });

        address[] memory relayers = new address[](2);
        relayers[0] = Ethereum.ALM_RELAYER;
        relayers[1] = Ethereum.ALM_RELAYER2;

        MainnetControllerInit.upgradeController({
            controllerInst: ControllerInstance({
                almProxy   : Ethereum.ALM_PROXY,
                controller : newController,
                rateLimits : Ethereum.ALM_RATE_LIMITS
            }),
            configAddresses: MainnetControllerInit.ConfigAddressParams({
                freezer       : Ethereum.ALM_FREEZER,
                relayers      : relayers,
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
            mintRecipients:      mintRecipients,
            layerZeroRecipients: layerZeroRecipients,
            maxSlippageParams:   maxSlippageParams
        });
    }

    function upgradeForeignController(
        ControllerInstance memory controllerInst,
        ForeignControllerInit.ConfigAddressParams memory configAddresses,
        ForeignControllerInit.CheckAddressParams memory checkAddresses,
        bool checkPsm
    ) internal {
        ForeignControllerInit.MintRecipient[] memory mintRecipients = new ForeignControllerInit.MintRecipient[](1);

        mintRecipients[0] = ForeignControllerInit.MintRecipient({
            domain        : CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM,
            mintRecipient : addrToBytes32(Ethereum.ALM_PROXY)
        });

        ForeignControllerInit.LayerZeroRecipient[] memory layerZeroRecipients = new ForeignControllerInit.LayerZeroRecipient[](0);

        ForeignControllerInit.upgradeController({
            controllerInst:      controllerInst,
            configAddresses:     configAddresses,
            checkAddresses:      checkAddresses,
            mintRecipients:      mintRecipients,
            layerZeroRecipients: layerZeroRecipients,
            checkPsm:            checkPsm
        });
    }

    function setRateLimitData(
        bytes32 key,
        address rateLimits,
        uint256 maxAmount,
        uint256 slope,
        uint256 decimals
    )
        internal
    {
        // Handle setting an unlimited rate limit
        if (maxAmount == type(uint256).max) {
            require(slope == 0, "InvalidUnlimitedRateLimitSlope");
        } else {
            uint256 upperBound = 1e12 * (10 ** decimals);
            uint256 lowerBound = 10 ** decimals;

            require(maxAmount <= upperBound && maxAmount >= lowerBound,             "InvalidMaxAmountPrecision");
            require(slope <= upperBound / 1 hours && slope >= lowerBound / 1 hours, "InvalidSlopePrecision");
            require(slope != 0,                                                     "InvalidSlopePrecision");
        }

        IRateLimits(rateLimits).setRateLimitData(key, maxAmount, slope);
    }

}
