// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { AllocatorBuffer } from 'dss-allocator/src/AllocatorBuffer.sol';
import { AllocatorVault }  from 'dss-allocator/src/AllocatorVault.sol';

import { IERC20 }   from 'forge-std/interfaces/IERC20.sol';
import { IERC4626 } from 'forge-std/interfaces/IERC4626.sol';

import { Ethereum } from 'spark-address-registry/Ethereum.sol';
import { Optimism } from 'spark-address-registry/Optimism.sol';
import { Unichain } from 'spark-address-registry/Unichain.sol';

import { MainnetController }               from "spark-alm-controller/src/MainnetController.sol";
import { RateLimitHelpers, RateLimitData } from "spark-alm-controller/src/RateLimitHelpers.sol";

import { ISparkLendFreezerMom } from 'sparklend-freezer/interfaces/ISparkLendFreezerMom.sol';

import { SparkPayloadEthereum, IEngine, EngineFlags } from "../../SparkPayloadEthereum.sol";

import { IMetaMorpho, MarketParams } from 'metamorpho/interfaces/IMetaMorpho.sol';

import { CCTPForwarder } from 'xchain-helpers/forwarders/CCTPForwarder.sol';

interface IOptimismTokenBridge {
    function bridgeERC20To(
        address _localToken,
        address _remoteToken,
        address _to,
        uint256 _amount,
        uint32 _minGasLimit,
        bytes calldata _extraData
    ) external;
}

/**
 * @title  May 29, 2025 Spark Ethereum Proposal
 * @notice Spark Liquidity Layer:
 *         - Onboard Optimism, Unichain
 *         - Mint 100m USDS into Optimism and Unichain
 *         - Mint 100m sUSDS into Optimism and Unichain
 *         - Increase USDe Mint and Staking Rate Limits
 *         SparkLend:
 *         - Update USDS IRM
 *         - Update DAI IRM
 *         - Reduce WBTC Liquidation Threshold
 *         Spark DAI Vault:
 *         - Onboard PT-SUSDS-14Aug2025
 * @author Phoenix Labs
 * Forum:  https://forum.sky.money/t/may-29-2025-proposed-changes-to-spark-for-upcoming-spell/26372/2
 *         https://forum.sky.money/t/may-29-2025-proposed-changes-to-spark-for-upcoming-spell-2/26440
 * Vote:   TODO
 */
contract SparkEthereum_20250529 is SparkPayloadEthereum {

    address internal constant DAI_USDS_IRM                  = 0xE15718d48E2C56b65aAB61f1607A5c096e9204f1;  // DAI  and USDS use the same params, same IRM
    
    address internal constant PT_SUSDS_14AUG2025            = 0xFfEc096c087C13Cc268497B89A613cACE4DF9A48;
    address internal constant PT_SUSDS_14AUG2025_PRICE_FEED = 0xD7c8498fF648CBB9E79d6470cf7F639e696D27A5;

    uint256 internal constant SUSDS_BRIDGE_AMOUNT  = 100_000_000e18;
    uint256 internal constant SUSDS_DEPOSIT_AMOUNT = 200_000_000e18;
    uint256 internal constant USDS_BRIDGE_AMOUNT   = 100_000_000e18;
    uint256 internal constant USDS_MINT_AMOUNT     = 400_000_000e18;

    constructor() {
        PAYLOAD_BASE     = 0x08AbA599Bd82e4De7b78516077cDF1CB24788CC1;
        PAYLOAD_OPTIMISM = 0x08AbA599Bd82e4De7b78516077cDF1CB24788CC1;
        PAYLOAD_UNICHAIN = 0xbF5a7CfaF47fd1Ad75c9C613b1d4C196eE1b4EeF;
    }

    function _postExecute() internal override {
        LISTING_ENGINE.POOL_CONFIGURATOR().setReserveInterestRateStrategyAddress(Ethereum.DAI,  DAI_USDS_IRM);
        LISTING_ENGINE.POOL_CONFIGURATOR().setReserveInterestRateStrategyAddress(Ethereum.USDS, DAI_USDS_IRM);

        RateLimitHelpers.setRateLimitData(
            MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_USDS_MINT(),
            Ethereum.ALM_RATE_LIMITS,
            RateLimitData({
                maxAmount : 500_000_000e18,
                slope     : 500_000_000e18 / uint256(1 days)
            }),
            "usdsMintLimit",
            18
        );
        RateLimitHelpers.setRateLimitData(
            MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_USDS_TO_USDC(),
            Ethereum.ALM_RATE_LIMITS,
            RateLimitData({
                maxAmount : 500_000_000e6,
                slope     : 300_000_000e6 / uint256(1 days)
            }),
            "swapUSDSToUSDCLimit",
            6
        );
        RateLimitHelpers.setRateLimitData(
            MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_USDE_MINT(),
            Ethereum.ALM_RATE_LIMITS,
            RateLimitData({
                maxAmount : 250_000_000e6,
                slope     : 100_000_000e6 / uint256(1 days)
            }),
            "ethenaMintLimit",
            6
        );
        RateLimitHelpers.setRateLimitData(
            MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_USDE_BURN(),
            Ethereum.ALM_RATE_LIMITS,
            RateLimitData({
                maxAmount : 500_000_000e18,
                slope     : 200_000_000e18 / uint256(1 days)
            }),
            "ethenaBurnLimit",
            18
        );
        RateLimitHelpers.setRateLimitData(
            RateLimitHelpers.makeAssetKey(
                MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_4626_DEPOSIT(),
                Ethereum.SUSDE
            ),
            Ethereum.ALM_RATE_LIMITS,
            RateLimitData({
                maxAmount : 250_000_000e18,
                slope     : 100_000_000e18 / uint256(1 days)
            }),
            "susdeDepositLimit",
            18
        );
        RateLimitHelpers.setRateLimitData(
            MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_SUSDE_COOLDOWN(),
            Ethereum.ALM_RATE_LIMITS,
            RateLimitHelpers.unlimitedRateLimit(),
            "susdeCooldownLimit",
            18
        );
        RateLimitHelpers.setRateLimitData(
            RateLimitHelpers.makeAssetKey(
                MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_4626_WITHDRAW(),
                Ethereum.SUSDE
            ),
            Ethereum.ALM_RATE_LIMITS,
            RateLimitHelpers.unlimitedRateLimit(),
            "susdeWithdrawLimit",
            18
        );

        // --- Set up Optimism ---
        RateLimitHelpers.setRateLimitData(
            RateLimitHelpers.makeDomainKey(
                MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_USDC_TO_DOMAIN(),
                CCTPForwarder.DOMAIN_ID_CIRCLE_OPTIMISM
            ),
            Ethereum.ALM_RATE_LIMITS,
            RateLimitData({
                maxAmount : 50_000_000e6,
                slope     : 25_000_000e6 / uint256(1 days)
            }),
            "usdcToCctpOptimismLimit",
            6
        );
        MainnetController(Ethereum.ALM_CONTROLLER).setMintRecipient(
            CCTPForwarder.DOMAIN_ID_CIRCLE_OPTIMISM,
            bytes32(uint256(uint160(Optimism.ALM_PROXY)))
        );

        // --- Set up Unichain ---
        RateLimitHelpers.setRateLimitData(
            RateLimitHelpers.makeDomainKey(
                MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_USDC_TO_DOMAIN(),
                CCTPForwarder.DOMAIN_ID_CIRCLE_UNICHAIN
            ),
            Ethereum.ALM_RATE_LIMITS,
            RateLimitData({
                maxAmount : 50_000_000e6,
                slope     : 25_000_000e6 / uint256(1 days)
            }),
            "usdcToCctpUnichainLimit",
            6
        );
        MainnetController(Ethereum.ALM_CONTROLLER).setMintRecipient(
            CCTPForwarder.DOMAIN_ID_CIRCLE_UNICHAIN,
            bytes32(uint256(uint160(Unichain.ALM_PROXY)))
        );

        // --- Send USDS and sUSDS to Optimism and Unichain ---
        
        // Mint USDS and sUSDS
        AllocatorVault(Ethereum.ALLOCATOR_VAULT).draw(USDS_MINT_AMOUNT);
        AllocatorBuffer(Ethereum.ALLOCATOR_BUFFER).approve(Ethereum.USDS, address(this), USDS_MINT_AMOUNT);
        IERC20(Ethereum.USDS).transferFrom(Ethereum.ALLOCATOR_BUFFER, address(this), USDS_MINT_AMOUNT);
        IERC20(Ethereum.USDS).approve(Ethereum.SUSDS, SUSDS_DEPOSIT_AMOUNT);
        uint256 susdsShares = IERC4626(Ethereum.SUSDS).deposit(SUSDS_DEPOSIT_AMOUNT, address(this));

        // Bridge to Optimism
        IERC20(Ethereum.USDS).approve(Ethereum.OPTIMISM_TOKEN_BRIDGE, USDS_BRIDGE_AMOUNT);
        IOptimismTokenBridge(Ethereum.OPTIMISM_TOKEN_BRIDGE).bridgeERC20To(Ethereum.USDS, Optimism.USDS, Optimism.ALM_PROXY, USDS_BRIDGE_AMOUNT, 1_000_000, "");

        uint256 susdsSharesOptimism = IERC4626(Ethereum.SUSDS).convertToShares(SUSDS_BRIDGE_AMOUNT);
        IERC20(Ethereum.SUSDS).approve(Ethereum.OPTIMISM_TOKEN_BRIDGE, susdsSharesOptimism);
        IOptimismTokenBridge(Ethereum.OPTIMISM_TOKEN_BRIDGE).bridgeERC20To(Ethereum.SUSDS, Optimism.SUSDS, Optimism.ALM_PROXY, susdsSharesOptimism, 1_000_000, "");

        // Bridge to Optimism
        IERC20(Ethereum.USDS).approve(Ethereum.UNICHAIN_TOKEN_BRIDGE, USDS_BRIDGE_AMOUNT);
        IOptimismTokenBridge(Ethereum.UNICHAIN_TOKEN_BRIDGE).bridgeERC20To(Ethereum.USDS, Unichain.USDS, Unichain.ALM_PROXY, USDS_BRIDGE_AMOUNT, 1_000_000, "");

        uint256 susdsSharesUnichain = susdsShares - susdsSharesOptimism;
        IERC20(Ethereum.SUSDS).approve(Ethereum.UNICHAIN_TOKEN_BRIDGE, susdsSharesUnichain);
        IOptimismTokenBridge(Ethereum.UNICHAIN_TOKEN_BRIDGE).bridgeERC20To(Ethereum.SUSDS, Unichain.SUSDS, Unichain.ALM_PROXY, susdsSharesUnichain, 1_000_000, "");
    
        // Onboard PT-USDS-14Aug2025
        IMetaMorpho(Ethereum.MORPHO_VAULT_DAI_1).submitCap(
            MarketParams({
                loanToken:       Ethereum.DAI,
                collateralToken: PT_SUSDS_14AUG2025,
                oracle:          PT_SUSDS_14AUG2025_PRICE_FEED,
                irm:             Ethereum.MORPHO_DEFAULT_IRM,
                lltv:            0.965e18
            }),
            500_000_000e18
        );
    }

    function collateralsUpdates() public pure override returns (IEngine.CollateralUpdate[] memory) {
        IEngine.CollateralUpdate[] memory update = new IEngine.CollateralUpdate[](1);

        update[0] = IEngine.CollateralUpdate({
            asset          : Ethereum.WBTC,
            ltv            : EngineFlags.KEEP_CURRENT,
            liqThreshold   : 40_00,
            liqBonus       : EngineFlags.KEEP_CURRENT,
            debtCeiling    : EngineFlags.KEEP_CURRENT,
            liqProtocolFee : EngineFlags.KEEP_CURRENT,
            eModeCategory  : EngineFlags.KEEP_CURRENT
        });

        return update;
    }

}
