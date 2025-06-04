// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.10;

import { IERC4626 } from "forge-std/interfaces/IERC4626.sol";
import { IERC20 }   from "forge-std/interfaces/IERC20.sol";

import { IMetaMorpho } from 'metamorpho/interfaces/IMetaMorpho.sol';

import { Base }     from 'spark-address-registry/Base.sol';
import { Ethereum } from 'spark-address-registry/Ethereum.sol';
import { Optimism } from 'spark-address-registry/Optimism.sol';
import { Unichain } from 'spark-address-registry/Unichain.sol';

import { ForeignController }     from 'spark-alm-controller/src/ForeignController.sol';
import { IRateLimits }           from 'spark-alm-controller/src/interfaces/IRateLimits.sol';
import { IALMProxy }             from 'spark-alm-controller/src/interfaces/IALMProxy.sol';
import { MainnetController }     from 'spark-alm-controller/src/MainnetController.sol';
import { RateLimitHelpers }      from 'spark-alm-controller/src/RateLimitHelpers.sol';

import { SLLHelpers } from '../../SparkPayloadEthereum.sol';

import { IPSM3 } from 'spark-psm/src/interfaces/IPSM3.sol';

import { ChainIdUtils } from 'src/libraries/ChainId.sol';

import { InterestStrategyValues, ReserveConfig }                   from '../../test-harness/ProtocolV3TestBase.sol';
import { ICustomIRM, IRateSource, ITargetBaseIRM, ITargetKinkIRM } from '../../test-harness/SparkEthereumTests.sol';
import { SparkLendContext }                                        from '../../test-harness/SparklendTests.sol';
import { SparkTestBase }                                           from '../../test-harness/SparkTestBase.sol';

import { MarketParams } from 'metamorpho/interfaces/IMetaMorpho.sol';

interface IMorpho {
    function fee() external view returns (uint256);
    function feeRecipient() external view returns (address);
}

contract SparkEthereum_20250612Test is SparkTestBase {

    address internal constant PT_EUSDE_29MAY2025            = 0x50D2C7992b802Eef16c04FeADAB310f31866a545;
    address internal constant PT_EUSDE_29MAY2025_PRICE_FEED = 0x39a695Eb6d0C01F6977521E5E79EA8bc232b506a;
    address internal constant PT_SUSDE_29MAY2025            = 0xb7de5dFCb74d25c2f21841fbd6230355C50d9308;
    address internal constant PT_SUSDE_29MAY2025_PRICE_FEED = 0xE84f7e0a890e5e57d0beEa2c8716dDf0c9846B4A;
    address internal constant SYRUP_USDC = 0x80ac24aA929eaF5013f6436cdA2a7ba190f5Cc0b;

    constructor() {
        id = "20250612";
    }

    function setUp() public {
        setupDomains("2025-06-04T13:00:00Z");

        deployPayloads();

        // chainData[ChainIdUtils.Base()].payload     = 0x3a1d3A9B0eD182d7B17aa61393D46a4f4EE0CEA5;
        // chainData[ChainIdUtils.Ethereum()].payload = 0x3968a022D955Bbb7927cc011A48601B65a33F346;
    }

    function test_ETHEREUM_SLL_MorphoSparkDAIOnboarding() public onChain(ChainIdUtils.Ethereum()) {
        MainnetController controller = MainnetController(Ethereum.ALM_CONTROLLER);

        bytes32 depositKey = RateLimitHelpers.makeAssetKey(
            controller.LIMIT_4626_DEPOSIT(),
            Ethereum.MORPHO_VAULT_DAI_1
        );
        bytes32 withdrawKey = RateLimitHelpers.makeAssetKey(
            controller.LIMIT_4626_WITHDRAW(),
            Ethereum.MORPHO_VAULT_DAI_1
        );

        assertEq(IMetaMorpho(Ethereum.MORPHO_VAULT_DAI_1).isAllocator(Ethereum.ALM_RELAYER), false);

        _assertRateLimit(depositKey,  0, 0);
        _assertRateLimit(withdrawKey, 0, 0);

        executeAllPayloadsAndBridges();

        assertEq(IMetaMorpho(Ethereum.MORPHO_VAULT_DAI_1).isAllocator(Ethereum.ALM_RELAYER), true);

        _assertRateLimit(depositKey, 200_000_000e18, uint256(100_000_000e18) / 1 days);
        _assertRateLimit(withdrawKey, type(uint256).max, 0);
    }

    function test_ETHEREUM_SparkLend_ezETHSupplyCap() public onChain(ChainIdUtils.Ethereum()) {
        _assertSupplyCapConfig(Ethereum.EZETH, 20_000, 2_000, 12 hours);
        
        executeAllPayloadsAndBridges();
        
        _assertSupplyCapConfig(Ethereum.EZETH, 40_000, 5_000, 12 hours);
    }

    function test_BASE_Spark_MorphoUSDCVaultFee() public onChain(ChainIdUtils.Base()) {
        assertEq(IMorpho(Base.MORPHO_VAULT_SUSDC).fee(),          0);
        assertEq(IMorpho(Base.MORPHO_VAULT_SUSDC).feeRecipient(), address(0));

        executeAllPayloadsAndBridges();

        assertEq(IMorpho(Base.MORPHO_VAULT_SUSDC).fee(),          0.1e18);
        assertEq(IMorpho(Base.MORPHO_VAULT_SUSDC).feeRecipient(), Base.SPARK_EXECUTOR);
    }

    function test_ETHEREUM_Spark_MorphoDAIVaultFee() public onChain(ChainIdUtils.Ethereum()) {
        assertEq(IMorpho(Ethereum.MORPHO_VAULT_DAI_1).fee(),          0);
        assertEq(IMorpho(Ethereum.MORPHO_VAULT_DAI_1).feeRecipient(), address(0));

        executeAllPayloadsAndBridges();

        assertEq(IMorpho(Ethereum.MORPHO_VAULT_DAI_1).fee(),          0.1e18);
        assertEq(IMorpho(Ethereum.MORPHO_VAULT_DAI_1).feeRecipient(), Ethereum.SPARK_PROXY);
    }

    function test_ETHEREUM_SparkLend_ReserveFactor() public onChain(ChainIdUtils.Ethereum()) {
        SparkLendContext memory ctx = _getSparkLendContext();
        
        ReserveConfig[] memory allConfigsBefore = createConfigurationSnapshot('', ctx.pool);
        
        ReserveConfig memory dai  = _findReserveConfigBySymbol(allConfigsBefore, 'DAI');
        ReserveConfig memory usds = _findReserveConfigBySymbol(allConfigsBefore, 'USDS');
        ReserveConfig memory usdc = _findReserveConfigBySymbol(allConfigsBefore, 'USDC');
        ReserveConfig memory usdt = _findReserveConfigBySymbol(allConfigsBefore, 'USDT');

        assertEq(dai.reserveFactor,  0);
        assertEq(usds.reserveFactor, 0);
        assertEq(usdc.reserveFactor, 5_00);
        assertEq(usdt.reserveFactor, 5_00);

        executeAllPayloadsAndBridges();

        ReserveConfig[] memory allConfigsAfter = createConfigurationSnapshot('', ctx.pool);

        dai.reserveFactor  = 10_00;
        usds.reserveFactor = 10_00;
        usdc.reserveFactor = 10_00;
        usdt.reserveFactor = 10_00;

        _validateReserveConfig(dai,  allConfigsAfter);
        _validateReserveConfig(usds, allConfigsAfter);
        _validateReserveConfig(usdc, allConfigsAfter);
        _validateReserveConfig(usdt, allConfigsAfter);
    }

    function test_ETHEREUM_sllSyrupUSDCDepositLimit() public onChain(ChainIdUtils.Ethereum()) {
        bytes32 susdeDepositKey = RateLimitHelpers.makeAssetKey(MainnetController(Ethereum.ALM_CONTROLLER).LIMIT_4626_DEPOSIT(), SYRUP_USDC);

        _assertRateLimit(susdeDepositKey, 25_000_000e6, 5_000_000e6 / uint256(1 days));

        executeAllPayloadsAndBridges();

        _assertRateLimit(susdeDepositKey, 100_000_000e6, 20_000_000e6 / uint256(1 days));
    }

    function test_ETHEREUM_morpho_PTSUSDE29MAY2025CapDecrease() public onChain(ChainIdUtils.Ethereum()) {
        _testMorphoCapUpdate({
            vault: Ethereum.MORPHO_VAULT_DAI_1,
            config: MarketParams({
                loanToken:       Ethereum.DAI,
                collateralToken: PT_SUSDE_29MAY2025,
                oracle:          PT_SUSDE_29MAY2025_PRICE_FEED,
                irm:             Ethereum.MORPHO_DEFAULT_IRM,
                lltv:            0.915e18
            }),
            currentCap: 400_000_000e18,
            newCap:     0
        });
    }

    function test_ETHEREUM_morpho_PTEUSDE29MAY2025CapDecrease() public onChain(ChainIdUtils.Ethereum()) {
        _testMorphoCapUpdate({
            vault: Ethereum.MORPHO_VAULT_DAI_1,
            config: MarketParams({
                loanToken:       Ethereum.DAI,
                collateralToken: PT_EUSDE_29MAY2025,
                oracle:          PT_EUSDE_29MAY2025_PRICE_FEED,
                irm:             Ethereum.MORPHO_DEFAULT_IRM,
                lltv:            0.915e18
            }),
            currentCap: 300_000_000e18,
            newCap:     0
        });
    }

}
