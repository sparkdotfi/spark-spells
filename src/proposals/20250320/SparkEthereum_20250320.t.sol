// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.10;

import 'src/test-harness/SparkTestBase.sol';

import { IERC20 } from 'forge-std/interfaces/IERC20.sol';

import { DataTypes } from "sparklend-v1-core/contracts/protocol/libraries/types/DataTypes.sol";

import { Arbitrum } from 'spark-address-registry/Arbitrum.sol';
import { Base }     from 'spark-address-registry/Base.sol';
import { Ethereum } from 'spark-address-registry/Ethereum.sol';

import { MarketParams } from 'metamorpho/interfaces/IMetaMorpho.sol';

import { ForeignController } from 'spark-alm-controller/src/ForeignController.sol';
import { RateLimitHelpers }  from 'spark-alm-controller/src/RateLimitHelpers.sol';
import { IRateLimits }       from 'spark-alm-controller/src/interfaces/IRateLimits.sol';

import { ReserveConfig } from "src/test-harness/ProtocolV3TestBase.sol";
import { ChainIdUtils }  from 'src/libraries/ChainId.sol';

contract SparkEthereum_20250320Test is SparkTestBase {

    address internal constant AGGOR_BTCUSD_ORACLE = 0x4219aA1A99f3fe90C2ACB97fCbc1204f6485B537;
    address internal constant CBBTC_USDC_ORACLE   = 0x663BECd10daE6C4A3Dcd89F1d76c1174199639B9;

    address internal constant EZETH_ORACLE = 0x52E85eB49e07dF74c8A9466D2164b4C4cA60014A;
    address internal constant RSETH_ORACLE = 0x70942D6b580741CF50A7906f4100063EE037b8eb;

    address internal constant PT_EUSDE_29MAY2025            = 0x50D2C7992b802Eef16c04FeADAB310f31866a545;
    address internal constant PT_EUSDE_29MAY2025_PRICE_FEED = 0x39a695Eb6d0C01F6977521E5E79EA8bc232b506a;
    address internal constant PT_USDE_31JUL2025             = 0x917459337CaAC939D41d7493B3999f571D20D667;
    address internal constant PT_USDE_31JUL2025_PRICE_FEED  = 0xFCaE69BEF9B6c96D89D58664d8aeA84BddCe2E5c;

    address internal constant DAI_IRM_OLD  = 0xd957978711F705358dbE34B37D381a76E1555E28;
    address internal constant DAI_IRM_NEW  = 0x5a7E7a32331189a794ac33Fec76C0A1dD3dDCF9c;
    address internal constant USDS_IRM_OLD = 0x2DB2f1eE78b4e0ad5AaF44969E2E8f563437f34C;
    address internal constant USDS_IRM_NEW = 0xD94BA511284d2c56F59a687C3338441d33304E07;

    constructor() {
        id = '20250320';
    }

    function setUp() public {
        // March 17, 2025
        setupDomains({
            mainnetForkBlock:     22066432,
            baseForkBlock:        27711491,
            gnosisForkBlock:      38037888,  // Not used
            arbitrumOneForkBlock: 316623039
        });
        
        chainSpellMetadata[ChainIdUtils.Ethereum()].payload    = 0x1e865856d8F97FB34FBb0EDbF63f53E29a676aB6;
        chainSpellMetadata[ChainIdUtils.Base()].payload        = 0x356f19Cb575CF40c7ff33A5117F9a9264C23f6e8;
        chainSpellMetadata[ChainIdUtils.ArbitrumOne()].payload = 0x1d54A093b8FDdFcc6fBB411d9Af31D96e034B3D5;
    }

    function test_ETHEREUM_sparkLend_emodeUpdate() public onChain(ChainIdUtils.Ethereum()) {
        loadPoolContext(_getPoolAddressesProviderRegistry().getAddressesProvidersList()[0]);

        DataTypes.EModeCategory memory eModeBefore = pool.getEModeCategoryData(3);

        assertEq(eModeBefore.ltv,                  0);
        assertEq(eModeBefore.liquidationThreshold, 0);
        assertEq(eModeBefore.liquidationBonus,     0);
        assertEq(eModeBefore.priceSource,          address(0));
        assertEq(eModeBefore.label,                '');

        executeAllPayloadsAndBridges();

        DataTypes.EModeCategory memory eModeAfter = pool.getEModeCategoryData(3);

        assertEq(eModeAfter.ltv,                  85_00);
        assertEq(eModeAfter.liquidationThreshold, 90_00);
        assertEq(eModeAfter.liquidationBonus,     102_00);
        assertEq(eModeAfter.priceSource,          address(0));
        assertEq(eModeAfter.label,                'BTC');
    }

    function test_ETHEREUM_sparkLend_collateralOnboarding() public onChain(ChainIdUtils.Ethereum()) {
        SparkLendAssetOnboardingParams memory lbtcParams = SparkLendAssetOnboardingParams({
            // General
            symbol:            'LBTC',
            tokenAddress:      Ethereum.LBTC,
            oracleAddress:     AGGOR_BTCUSD_ORACLE,
            collateralEnabled: true,
            // IRM Params
            optimalUsageRatio:      0.45e27,
            baseVariableBorrowRate: 0.05e27,
            variableRateSlope1:     0.15e27,
            variableRateSlope2:     3e27,
            // Borrowing configuration
            borrowEnabled:          false,
            stableBorrowEnabled:    false,
            isolationBorrowEnabled: false,
            siloedBorrowEnabled:    false,
            flashloanEnabled:       false,
            // Reserve configuration
            ltv:                  65_00,
            liquidationThreshold: 70_00,
            liquidationBonus:     108_00,
            reserveFactor:        15_00,
            // Supply caps
            supplyCap:    250,
            supplyCapMax: 2500,
            supplyCapGap: 250,
            supplyCapTtl: 12 hours,
            // Borrow caps
            borrowCap:    0,
            borrowCapMax: 0,
            borrowCapGap: 0,
            borrowCapTtl: 0,
            // Isolation  and emode configurations
            isolationMode:            false,
            isolationModeDebtCeiling: 0,
            liquidationProtocolFee:   10_00,
            emodeCategory:            3
        });

        SparkLendAssetOnboardingParams memory tbtcParams = SparkLendAssetOnboardingParams({
            // General
            symbol:           'tBTC',
            tokenAddress:      Ethereum.TBTC,
            oracleAddress:     AGGOR_BTCUSD_ORACLE,
            collateralEnabled: true,
            // IRM Params
            optimalUsageRatio:      0.60e27,
            baseVariableBorrowRate: 0,
            variableRateSlope1:     0.04e27,
            variableRateSlope2:     3e27,
            // Borrowing configuration
            borrowEnabled:          true,
            stableBorrowEnabled:    false,
            isolationBorrowEnabled: false,
            siloedBorrowEnabled:    false,
            flashloanEnabled:       true,
            // Reserve configuration
            ltv:                  65_00,
            liquidationThreshold: 70_00,
            liquidationBonus:     108_00,
            reserveFactor:        20_00,
            // Supply caps
            supplyCap:    125,
            supplyCapMax: 500,
            supplyCapGap: 125,
            supplyCapTtl: 12 hours,
            // Borrow caps
            borrowCap:    25,
            borrowCapMax: 250,
            borrowCapGap: 25,
            borrowCapTtl: 12 hours,
            // Isolation  and emode configurations
            isolationMode:            false,
            isolationModeDebtCeiling: 0,
            liquidationProtocolFee:   10_00,
            emodeCategory:            0
        });

        SparkLendAssetOnboardingParams memory ezethParams = SparkLendAssetOnboardingParams({
            // General
            symbol:           'ezETH',
            tokenAddress:      Ethereum.EZETH,
            oracleAddress:     EZETH_ORACLE,
            collateralEnabled: true,
            // IRM Params
            optimalUsageRatio:      0.45e27,
            baseVariableBorrowRate: 0.05e27,
            variableRateSlope1:     0.15e27,
            variableRateSlope2:     3e27,
            // Borrowing configuration
            borrowEnabled:          false,
            stableBorrowEnabled:    false,
            isolationBorrowEnabled: false,
            siloedBorrowEnabled:    false,
            flashloanEnabled:       false,
            // Reserve configuration
            ltv:                  72_00,
            liquidationThreshold: 73_00,
            liquidationBonus:     110_00,
            reserveFactor:        15_00,
            // Supply caps
            supplyCap:    2_000,
            supplyCapMax: 20_000,
            supplyCapGap: 2_000,
            supplyCapTtl: 12 hours,
            // Borrow caps
            borrowCap:    0,
            borrowCapMax: 0,
            borrowCapGap: 0,
            borrowCapTtl: 0,
            // Isolation  and emode configurations
            isolationMode:            false,
            isolationModeDebtCeiling: 0,
            liquidationProtocolFee:   10_00,
            emodeCategory:            0
        });

        SparkLendAssetOnboardingParams memory rsethParams = SparkLendAssetOnboardingParams({
            // General
            symbol:           'rsETH',
            tokenAddress:      Ethereum.RSETH,
            oracleAddress:     RSETH_ORACLE,
            collateralEnabled: true,
            // IRM Params
            optimalUsageRatio:      0.45e27,
            baseVariableBorrowRate: 0.05e27,
            variableRateSlope1:     0.15e27,
            variableRateSlope2:     3e27,
            // Borrowing configuration
            borrowEnabled:          false,
            stableBorrowEnabled:    false,
            isolationBorrowEnabled: false,
            siloedBorrowEnabled:    false,
            flashloanEnabled:       false,
            // Reserve configuration
            ltv:                  72_00,
            liquidationThreshold: 73_00,
            liquidationBonus:     110_00,
            reserveFactor:        15_00,
            // Supply caps
            supplyCap:    2_000,
            supplyCapMax: 20_000,
            supplyCapGap: 2_000,
            supplyCapTtl: 12 hours,
            // Borrow caps
            borrowCap:    0,
            borrowCapMax: 0,
            borrowCapGap: 0,
            borrowCapTtl: 0,
            // Isolation  and emode configurations
            isolationMode:            false,
            isolationModeDebtCeiling: 0,
            liquidationProtocolFee:   10_00,
            emodeCategory:            0
        });

        SparkLendAssetOnboardingParams[] memory newAssets = new SparkLendAssetOnboardingParams[](4);
        newAssets[0] = lbtcParams;
        newAssets[1] = tbtcParams;
        newAssets[2] = ezethParams;
        newAssets[3] = rsethParams;

        _testAssetOnboardings(newAssets);
    }

    function test_ETHEREUM_sparkLend_cbBtcEmode() public onChain(ChainIdUtils.Ethereum()) {
        loadPoolContext(_getPoolAddressesProviderRegistry().getAddressesProvidersList()[0]);

        ReserveConfig[] memory allConfigsBefore = createConfigurationSnapshot('', pool);
        ReserveConfig   memory cbBtcConfig      = _findReserveConfigBySymbol(allConfigsBefore, 'cbBTC');

        assertEq(cbBtcConfig.eModeCategory, 0);

        executeAllPayloadsAndBridges();

        ReserveConfig[] memory allConfigsAfter = createConfigurationSnapshot('', pool);
        cbBtcConfig.eModeCategory = 3;

        _validateReserveConfig(cbBtcConfig, allConfigsAfter);
    }

    function test_ETHEREUM_sparkLend_daiIRMUpdate() public onChain(ChainIdUtils.Ethereum()) {
        loadPoolContext(_getPoolAddressesProviderRegistry().getAddressesProvidersList()[0]);

        _testRateTargetBaseIRMUpdate({
            symbol:      'DAI',
            oldIRM:      DAI_IRM_OLD,
            newIRM:      DAI_IRM_NEW,
            oldSpread:   0.0025e27,
            newSpread:   0.005e27,
            oldBaseRate: 0.065474799224266183398928000e27,
            newBaseRate: 0.067974799224266183398928000e27
        });
    }

    function test_ETHEREUM_sparkLend_usdsIRMUpdate() public onChain(ChainIdUtils.Ethereum()) {
        loadPoolContext(_getPoolAddressesProviderRegistry().getAddressesProvidersList()[0]);

        _testRateTargetBaseIRMUpdate({
            symbol:      'USDS',
            oldIRM:      USDS_IRM_OLD,
            newIRM:      USDS_IRM_NEW,
            oldSpread:   0.0025e27,
            newSpread:   0.005e27,
            oldBaseRate: 0.065474799224266183398928000e27,
            newBaseRate: 0.067974799224266183398928000e27
        });
    }

    function test_ETHEREUM_morpho_PTEUSDE29MAY2025Onboarding() public onChain(ChainIdUtils.Ethereum()) {
        _testMorphoCapUpdate({
            vault: Ethereum.MORPHO_VAULT_DAI_1,
            config: MarketParams({
                loanToken:       Ethereum.DAI,
                collateralToken: PT_EUSDE_29MAY2025,
                oracle:          PT_EUSDE_29MAY2025_PRICE_FEED,
                irm:             Ethereum.MORPHO_DEFAULT_IRM,
                lltv:            0.915e18
            }),
            currentCap: 0,
            newCap:     300_000_000e18
        });
        _testMorphoPendlePTOracleConfig({
            pt:           PT_EUSDE_29MAY2025,
            oracle:       PT_EUSDE_29MAY2025_PRICE_FEED,
            discount:     0.2e18,
            currentPrice: 0.960818791222729579e36
        });
    }

    function test_ETHEREUM_morpho_PTUSDE31JUL2025Onboarding() public onChain(ChainIdUtils.Ethereum()) {
        _testMorphoCapUpdate({
            vault: Ethereum.MORPHO_VAULT_DAI_1,
            config: MarketParams({
                loanToken:       Ethereum.DAI,
                collateralToken: PT_USDE_31JUL2025,
                oracle:          PT_USDE_31JUL2025_PRICE_FEED,
                irm:             Ethereum.MORPHO_DEFAULT_IRM,
                lltv:            0.915e18
            }),
            currentCap: 0,
            newCap:     200_000_000e18
        });
        _testMorphoPendlePTOracleConfig({
            pt:           PT_USDE_31JUL2025,
            oracle:       PT_USDE_31JUL2025_PRICE_FEED,
            discount:     0.2e18,
            currentPrice: 0.9262982432775241e36
        });
    }

    function test_BASE_morpho_CBBTCSupplyCap() public onChain(ChainIdUtils.Base()) {
        _testMorphoCapUpdate({
            vault: Base.MORPHO_VAULT_SUSDC,
            config: MarketParams({
                loanToken:       Base.USDC,
                collateralToken: Base.CBBTC,
                oracle:          CBBTC_USDC_ORACLE,
                irm:             Base.MORPHO_DEFAULT_IRM,
                lltv:            0.86e18
            }),
            currentCap: 100_000_000e6,
            newCap:     500_000_000e6
        });
    }

    function test_ARBITRUM_AaveOnboardingIntegration() public onChain(ChainIdUtils.ArbitrumOne()) {
        executeAllPayloadsAndBridges();

        ForeignController controller = ForeignController(Arbitrum.ALM_CONTROLLER);
        
        IERC20 usdc  = IERC20(Arbitrum.USDC);
        IERC20 ausdc = IERC20(Arbitrum.ATOKEN_USDC);

        // Use a realistic numbers to check the rate limits
        uint256 usdcAmount = 5_000_000e6;

        deal(Arbitrum.USDC, Arbitrum.ALM_PROXY, usdcAmount);

        assertEq(usdc.balanceOf(Arbitrum.ALM_PROXY),  usdcAmount);
        assertEq(ausdc.balanceOf(Arbitrum.ALM_PROXY), 0);

        vm.startPrank(Arbitrum.ALM_RELAYER);

        controller.depositAave(Arbitrum.ATOKEN_USDC, usdcAmount);

        assertEq(usdc.balanceOf(Arbitrum.ALM_PROXY),  0);
        assertEq(ausdc.balanceOf(Arbitrum.ALM_PROXY), usdcAmount);

        controller.withdrawAave(Arbitrum.ATOKEN_USDC, usdcAmount);

        assertEq(usdc.balanceOf(Arbitrum.ALM_PROXY),  usdcAmount);
        assertEq(ausdc.balanceOf(Arbitrum.ALM_PROXY), 0);
    }

    function test_ARBITRUM_AaveRateLimits() public onChain(ChainIdUtils.ArbitrumOne()) {
        ForeignController controller = ForeignController(Arbitrum.ALM_CONTROLLER);
        IRateLimits rateLimits       = IRateLimits(Arbitrum.ALM_RATE_LIMITS);
        
        IERC20 usdc  = IERC20(Arbitrum.USDC);
        IERC20 ausdc = IERC20(Arbitrum.ATOKEN_USDC);

        bytes32 usdcDepositKey = RateLimitHelpers.makeAssetKey(
            controller.LIMIT_AAVE_DEPOSIT(),
            address(ausdc)
        );
        bytes32 usdcWithdrawKey = RateLimitHelpers.makeAssetKey(
            controller.LIMIT_AAVE_WITHDRAW(),
            address(ausdc)
        );

        assertEq(rateLimits.getCurrentRateLimit(usdcDepositKey), 0);
        assertEq(rateLimits.getCurrentRateLimit(usdcDepositKey), 0);

        executeAllPayloadsAndBridges();

        deal(Arbitrum.USDC, Arbitrum.ALM_PROXY, 30_000_000e6);

        vm.startPrank(Arbitrum.ALM_RELAYER);

        // USDC

        assertEq(rateLimits.getCurrentRateLimit(usdcDepositKey), 30_000_000e6);
        assertEq(usdc.balanceOf(Arbitrum.ALM_PROXY),             30_000_000e6);
        assertEq(ausdc.balanceOf(Arbitrum.ALM_PROXY),            0);

        controller.depositAave(address(ausdc), 30_000_000e6);

        assertEq(rateLimits.getCurrentRateLimit(usdcDepositKey), 0);
        assertEq(usdc.balanceOf(Arbitrum.ALM_PROXY),             0);

        assertApproxEqAbs(ausdc.balanceOf(Arbitrum.ALM_PROXY), 30_000_000e6, 1);

        assertEq(rateLimits.getCurrentRateLimit(usdcWithdrawKey), type(uint256).max);

        // Confirm proper recharge rate
        skip(1 hours);

        assertEq(rateLimits.getCurrentRateLimit(usdcDepositKey), 15_000_000e6 / uint256(1 days) * 1 hours);

        // All limits should be reset in 2 days + 1 (rounding)
        skip(47 hours + 1);

        assertEq(rateLimits.getCurrentRateLimit(usdcDepositKey), 30_000_000e6);
    }

}
