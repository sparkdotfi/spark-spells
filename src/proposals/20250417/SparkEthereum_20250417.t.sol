// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.10;

import 'src/test-harness/SparkTestBase.sol';

import { MarketParams } from 'metamorpho/interfaces/IMetaMorpho.sol';

import { Ethereum } from 'spark-address-registry/Ethereum.sol';

import { RateLimitData }     from 'spark-alm-controller/src/RateLimitHelpers.sol';

import { ChainIdUtils }  from 'src/libraries/ChainId.sol';

import { ReserveConfig } from '../../test-harness/ProtocolV3TestBase.sol';

contract SparkEthereum_20250417Test is SparkTestBase {

    address internal constant ETHEREUM_OLD_ALM_CONTROLLER = Ethereum.ALM_CONTROLLER;
    address internal constant ETHEREUM_NEW_ALM_CONTROLLER = 0xF8Dff673b555a225e149218C5005FC88f4a13870;

    address internal constant CURVE_SUSDSUSDT = 0x00836Fe54625BE242BcFA286207795405ca4fD10;
    address internal constant CURVE_USDCUSDT  = 0x4f493B7dE8aAC7d55F71853688b1F7C8F0243C85;

    address internal constant PT_SUSDE_31JUL2025_PRICE_FEED = 0x78804d5290F250A8066145D16A99bd3ea920b732;
    address internal constant PT_SUSDE_31JUL2025            = 0x3b3fB9C57858EF816833dC91565EFcd85D96f634;

    address internal constant ARBITRUM_FLUID_SUSDS = 0x3459fcc94390C3372c0F7B4cD3F8795F0E5aFE96;

    constructor() {
        id = '20250417';
    }

    function setUp() public {
        setupDomains("2025-04-11T11:11:00Z");

        deployPayloads();

        setControllerUpgrade(
            ChainIdUtils.Ethereum(),
            ETHEREUM_OLD_ALM_CONTROLLER,
            ETHEREUM_NEW_ALM_CONTROLLER
        );

        chainData[ChainIdUtils.ArbitrumOne()].payload = 0xab465726A358c004C22bB8136d43716e1936AFa6;
        chainData[ChainIdUtils.Ethereum()].payload    = 0xA8FF99Ac98Fc0C3322F639a9591257518514455c;
    }

    function test_ETHEREUM_ControllerUpgrade() public onChain(ChainIdUtils.Ethereum()) {
        _testControllerUpgrade({
            oldController: ETHEREUM_OLD_ALM_CONTROLLER,
            newController: ETHEREUM_NEW_ALM_CONTROLLER
        });
    }

    function test_ETHEREUM_sparklend_DAIOnboarding() public onChain(ChainIdUtils.Ethereum()) {
        _testAaveOnboarding({
            aToken:                Ethereum.DAI_ATOKEN,
            expectedDepositAmount: 25_000_000e18,
            depositMax:            100_000_000e18,
            depositSlope:          50_000_000e18 / uint256(1 days)
        });
    }

    function test_ETHEREUM_curve_SUSDSUSDTOnboarding() public onChain(ChainIdUtils.Ethereum()) {
        _testCurveOnboarding({
            pool:                        CURVE_SUSDSUSDT,
            expectedDepositAmountToken0: 2_000_000e18,
            expectedSwapAmountToken0:    1_000_000e18,
            maxSlippage:                 0.9985e18,
            swapLimit:                   RateLimitData(5_000_000e18,  20_000_000e18 / uint256(1 days)),
            depositLimit:                RateLimitData(5_000_000e18,  20_000_000e18 / uint256(1 days)),
            withdrawLimit:               RateLimitData(25_000_000e18, 100_000_000e18 / uint256(1 days))
        });
    }

    function test_ETHEREUM_curve_USDCUSDTOnboarding() public onChain(ChainIdUtils.Ethereum()) {
        _testCurveOnboarding({
            pool:                        CURVE_USDCUSDT,
            expectedDepositAmountToken0: 0,
            expectedSwapAmountToken0:    50_000e6,
            maxSlippage:                 0.9985e18,
            swapLimit:                   RateLimitData(5_000_000e18, 20_000_000e18 / uint256(1 days)),
            depositLimit:                RateLimitData(0, 0),
            withdrawLimit:               RateLimitData(0, 0)
        });
    }

    function test_ETHEREUM_CBBTCChanges() public onChain(ChainIdUtils.Ethereum()) {
        _testIRMChanges({
            asset:      Ethereum.CBBTC,
            oldOptimal: 0.6e27,
            oldBase:    0,
            oldSlope1:  0.04e27,
            oldSlope2:  3e27,
            newOptimal: 0.8e27,
            newBase:    0,
            newSlope1:  0.01e27,
            newSlope2:  3e27
        });
    }

    function test_ETHEREUM_TBTCChanges() public onChain(ChainIdUtils.Ethereum()) {
        _testIRMChanges({
            asset:      Ethereum.TBTC,
            oldOptimal: 0.6e27,
            oldBase:    0,
            oldSlope1:  0.04e27,
            oldSlope2:  3e27,
            newOptimal: 0.8e27,
            newBase:    0,
            newSlope1:  0.01e27,
            newSlope2:  3e27
        });
    }

    function test_ETHEREUM_WBTCChanges() public onChain(ChainIdUtils.Ethereum()) {
        loadPoolContext(_getPoolAddressesProviderRegistry().getAddressesProvidersList()[0]);

        ReserveConfig[] memory allConfigsBefore = createConfigurationSnapshot('', pool);
        ReserveConfig memory config = _findReserveConfigBySymbol(allConfigsBefore, 'WBTC');

        assertEq(config.liquidationThreshold, 50_00);

        executeAllPayloadsAndBridges();

        ReserveConfig[] memory allConfigsAfter = createConfigurationSnapshot('', pool);
        
        config.liquidationThreshold = 45_00;

        _validateReserveConfig(config, allConfigsAfter);
    }

    function test_ETHEREUM_SUSDSChanges() public onChain(ChainIdUtils.Ethereum()) {
        loadPoolContext(_getPoolAddressesProviderRegistry().getAddressesProvidersList()[0]);

        ReserveConfig[] memory allConfigsBefore = createConfigurationSnapshot('', pool);
        ReserveConfig memory config = _findReserveConfigBySymbol(allConfigsBefore, 'sUSDS');

        assertEq(config.eModeCategory, 0);

        executeAllPayloadsAndBridges();

        ReserveConfig[] memory allConfigsAfter = createConfigurationSnapshot('', pool);
        
        config.eModeCategory = 2;

        _validateReserveConfig(config, allConfigsAfter);
    }

    function test_ETHEREUM_morpho_PTSUSDE31JUL2025Onboarding() public onChain(ChainIdUtils.Ethereum()) {
        _testMorphoCapUpdate({
            vault: Ethereum.MORPHO_VAULT_DAI_1,
            config: MarketParams({
                loanToken:       Ethereum.DAI,
                collateralToken: PT_SUSDE_31JUL2025,
                oracle:          PT_SUSDE_31JUL2025_PRICE_FEED,
                irm:             Ethereum.MORPHO_DEFAULT_IRM,
                lltv:            0.915e18
            }),
            currentCap: 0,
            newCap:     400_000_000e18
        });
        _testMorphoPendlePTOracleConfig({
            pt:           PT_SUSDE_31JUL2025,
            oracle:       PT_SUSDE_31JUL2025_PRICE_FEED,
            discount:     0.2e18,
            currentPrice: 0.939981424403855911e36
        });
    }

    function test_ARBITRUM_FluidSUSDSOnboarding() public onChain(ChainIdUtils.ArbitrumOne()) {
        _testERC4626Onboarding({
            vault:                 ARBITRUM_FLUID_SUSDS,
            expectedDepositAmount: 5_000_000e18,
            depositMax:            10_000_000e18,
            depositSlope:          5_000_000e18 / uint256(1 days)
        });
    }

}
