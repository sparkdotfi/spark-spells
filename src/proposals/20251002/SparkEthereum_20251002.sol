// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IERC20 } from 'forge-std/interfaces/IERC20.sol';

import { IMetaMorpho, MarketParams } from 'metamorpho/interfaces/IMetaMorpho.sol';

import { Ethereum } from 'spark-address-registry/Ethereum.sol';

import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";
import { IRateLimits }       from "spark-alm-controller/src/interfaces/IRateLimits.sol";

import { ICapAutomator } from "sparklend-cap-automator/interfaces/ICapAutomator.sol";

import { SparkPayloadEthereum, SLLHelpers } from "src/SparkPayloadEthereum.sol";

interface INetworkRegistry {
    function registerNetwork() external;
}

interface INetworkRestakeDelegator {
    function setMaxNetworkLimit(uint96 identifier, uint256 amount) external;
    function setNetworkLimit(bytes32 subnetwork, uint256 amount) external;
    function setOperatorNetworkShares(bytes32 subnetwork, address operator, uint256 shares) external;
    function setHook(address hook) external;
    function OPERATOR_VAULT_OPT_IN_SERVICE() external view returns (address);
    function OPERATOR_NETWORK_OPT_IN_SERVICE() external view returns (address);
    function OPERATOR_NETWORK_SHARES_SET_ROLE() external view returns (bytes32);
    function grantRole(bytes32 role, address account) external;
}

interface IOperatorRegistry {
    function registerOperator() external;
}

interface IOptInService {
    function optIn(address where) external;
}

interface ISparkVaultV2 {
    function asset() external view returns (address);
    function grantRole(bytes32 role, address account) external;
    function setDepositCap(uint256 newCap) external;
    function SETTER_ROLE() external view returns (bytes32);
    function setVsrBounds(uint256 minVsr_, uint256 maxVsr_) external;
    function TAKER_ROLE() external view returns (bytes32);
}

interface IVetoSlasher {
    function setResolver(uint96 identifier, address resolver, bytes calldata hints) external;
}

/**
 * @title  October 02, 2025 Spark Ethereum Proposal
 * @notice Spark USDS Morpho Vault:
 *         - Increase PT-USDe-27Nov Supply Cap
 *         Spark Savings:
 *         - Launch Savings v2 Vaults for USDC, USDT, and ETH
 *         SparkLend:
 *         - Increase LBTC Supply Cap Automator Parameters
 *         - Reduce Stablecoin Market Reserve Factors
 *         - Claim Accrued Reserves for USDS and DAI
 *         Spark Liquidity Layer:
 *         - Onboard SparkLend ETH
 *         - Onboard B2C2 Penny for OTC Services
 *         - Add transferAsset Rate Limit for SYRUP
 *         Spark Treasury:
 *         - Transfer Share of Ethena Direct Allocation Net Profit to Grove
 *         - Spark Foundation Grant
 *         SPK Staking:
 *         - Configure Symbiotic Instance
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

    address internal constant GROVE_SUBDAO_PROXY = 0x1369f7b2b38c76B6478c0f0E66D94923421891Ba;
    address internal constant PYUSD              = 0x6c3ea9036406852006290770BEdFcAbA0e23A0e8;
    address internal constant SYRUP              = 0x643C4E15d7d62Ad0aBeC4a9BD4b001aA3Ef52d66;

    address internal constant PT_USDE_27NOV2025             = 0x62C6E813b9589C3631Ba0Cdb013acdB8544038B7;
    address internal constant PT_USDE_27NOV2025_PRICE_FEED  = 0x52A34E1D7Cb12c70DaF0e8bdeb91E1d02deEf97d;

    uint256 internal constant AMOUNT_TO_GROVE            = 1_031_866e18;
    uint256 internal constant AMOUNT_TO_SPARK_FOUNDATION = 1_100_000e18;

    // Symbiotic addresses
    address constant NETWORK_DELEGATOR = 0x2C5bF9E8e16716A410644d6b4979d74c1951952d;
    address constant NETWORK_REGISTRY  = 0xC773b1011461e7314CF05f97d95aa8e92C1Fd8aA;
    address constant OPERATOR_REGISTRY = 0xAd817a6Bc954F678451A71363f04150FDD81Af9F;
    address constant RESET_HOOK        = 0xC3B87BbE976f5Bfe4Dc4992ae4e22263Df15ccBE;
    address constant STAKED_SPK_VAULT  = 0xc6132FAF04627c8d05d6E759FAbB331Ef2D8F8fD;
    address constant VETO_SLASHER      = 0x4BaaEB2Bf1DC32a2Fb2DaA4E7140efb2B5f8cAb7;

    function _postExecute() internal override {
        // Increase PT-USDe-27Nov Supply Cap
        IMetaMorpho(Ethereum.MORPHO_VAULT_USDS).submitCap(
            MarketParams({
                loanToken:       Ethereum.USDS,
                collateralToken: PT_USDE_27NOV2025,
                oracle:          PT_USDE_27NOV2025_PRICE_FEED,
                irm:             Ethereum.MORPHO_DEFAULT_IRM,
                lltv:            0.915e18
            }),
            1_000_000_000e18
        );

        // Reduce Stablecoin Market Reserve Factors
        LISTING_ENGINE.POOL_CONFIGURATOR().setReserveFactor(Ethereum.USDC, 1_00);
        LISTING_ENGINE.POOL_CONFIGURATOR().setReserveFactor(Ethereum.USDT, 1_00);

        // Increase LBTC Supply Cap Automator Parameters
        ICapAutomator(Ethereum.CAP_AUTOMATOR).setSupplyCapConfig({
            asset:            Ethereum.LBTC,
            max:              10_000,
            gap:              500,
            increaseCooldown: 12 hours
        });

        // --- Launch Savings v2 Vaults for USDC, USDT, and ETH ---
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

        // Onboard SparkLend ETH
        _configureAaveToken(Ethereum.WETH_SPTOKEN, 50_000e18, 10_000e18 / uint256(1 days));

        // Onboard B2C2 Penny for OTC Services
        SLLHelpers.setRateLimitData(
            RateLimitHelpers.makeAssetDestinationKey(
                MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_ASSET_TRANSFER(),
                Ethereum.USDC,
                address(0xdead) // TODO Destination
            ),
            Ethereum.ALM_RATE_LIMITS,
            1_000_000e6,
            20_000_000e6 / uint256(1 days),
            6
        );

        SLLHelpers.setRateLimitData(
            RateLimitHelpers.makeAssetDestinationKey(
                MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_ASSET_TRANSFER(),
                Ethereum.USDT,
                address(0xdead) // TODO Destination
            ),
            Ethereum.ALM_RATE_LIMITS,
            1_000_000e6,
            20_000_000e6 / uint256(1 days),
            6
        );

        SLLHelpers.setRateLimitData(
            RateLimitHelpers.makeAssetDestinationKey(
                MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_ASSET_TRANSFER(),
                PYUSD,
                address(0xdead) // TODO Destination
            ),
            Ethereum.ALM_RATE_LIMITS,
            1_000_000e6,
            20_000_000e6 / uint256(1 days),
            6
        );

        // Add transferAsset Rate Limit for SYRUP
        SLLHelpers.setRateLimitData(
            RateLimitHelpers.makeAssetDestinationKey(
                MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_ASSET_TRANSFER(),
                SYRUP,
                Ethereum.ALM_OPS_MULTISIG
            ),
            Ethereum.ALM_RATE_LIMITS,
            200_000e18,
            200_000e18 / uint256(1 days),
            18
        );

        // Transfer Share of Ethena Direct Allocation Net Profit to Grove
        IERC20(Ethereum.USDS).transfer(GROVE_SUBDAO_PROXY, AMOUNT_TO_GROVE);

        // Spark Foundation
        IERC20(Ethereum.USDS).transfer(Ethereum.SPARK_FOUNDATION, AMOUNT_TO_SPARK_FOUNDATION);

        // Configure Symbiotic Instance
        _configureSymbiotic();

        // Withdraw USDS and DAI Reserves from SparkLend
        address[] memory aTokens = new address[](2);
        aTokens[0] = Ethereum.DAI_SPTOKEN;
        aTokens[1] = Ethereum.USDS_SPTOKEN;

        _transferFromSparkLendTreasury(aTokens);
    }

    function _configureSymbiotic() internal {
        address NETWORK   = Ethereum.SPARK_PROXY;
        address OWNER     = Ethereum.SPARK_PROXY;
        address OPERATOR  = Ethereum.SPARK_PROXY;

        bytes32 subnetwork = bytes32(uint256(uint160(NETWORK)) << 96 | 0);  // Subnetwork.subnetwork(network, 0)

        IVetoSlasher      slasher          = IVetoSlasher(VETO_SLASHER);
        INetworkRegistry  networkRegistry  = INetworkRegistry(NETWORK_REGISTRY);
        IOperatorRegistry operatorRegistry = IOperatorRegistry(OPERATOR_REGISTRY);
        INetworkRestakeDelegator delegator = INetworkRestakeDelegator(NETWORK_DELEGATOR);

        // --- Step 1: Do configurations as network, DO NOT SET middleware, max network limit, and resolver

        networkRegistry.registerNetwork();
        delegator.setMaxNetworkLimit(0, type(uint256).max);
        slasher.setResolver(0, OWNER, "");

        // --- Step 2: Configure the network and operator to take control of stake as the vault owner

        delegator.setNetworkLimit(subnetwork, type(uint256).max);
        delegator.setOperatorNetworkShares(
            subnetwork,
            OPERATOR,
            1e18  // 100% shares
        );
        delegator.setHook(RESET_HOOK);
        delegator.grantRole(delegator.OPERATOR_NETWORK_SHARES_SET_ROLE(), RESET_HOOK);

        // --- Step 3: Opt in to the vault as the operator

        operatorRegistry.registerOperator();
        IOptInService(delegator.OPERATOR_NETWORK_OPT_IN_SERVICE()).optIn(NETWORK);
        IOptInService(delegator.OPERATOR_VAULT_OPT_IN_SERVICE()).optIn(STAKED_SPK_VAULT);
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
