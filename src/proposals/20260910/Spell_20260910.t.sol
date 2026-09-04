// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { console2 } from "forge-std/console2.sol";

import { IERC20 }         from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata } from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { Ethereum }  from "spark-address-registry/Ethereum.sol";
import { Gnosis }    from "spark-address-registry/Gnosis.sol";
import { SparkLend } from "spark-address-registry/SparkLend.sol";

import { MarketParams } from "morpho-blue/src/interfaces/IMorpho.sol";

import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";

import {
    IPoolAddressesProvider,
    RateTargetKinkInterestRateStrategy
} from "sparklend-advanced/src/RateTargetKinkInterestRateStrategy.sol";

import { DataTypes }            from "sparklend-v1-core/protocol/libraries/types/DataTypes.sol";
import { IAToken }              from "sparklend-v1-core/interfaces/IAToken.sol";
import { IPool }                from "sparklend-v1-core/interfaces/IPool.sol";
import { IPoolConfigurator }    from "sparklend-v1-core/interfaces/IPoolConfigurator.sol";
import { ReserveConfiguration } from "sparklend-v1-core/protocol/libraries/configuration/ReserveConfiguration.sol";

import { ChainIdUtils } from "src/libraries/ChainIdUtils.sol";
import { DealUtils }    from "src/libraries/DealUtils.sol";

import { SparklendTests }           from "src/test-harness/SparklendTests.sol";
import { SparkLiquidityLayerTests } from "src/test-harness/SparkLiquidityLayerTests.sol";
import { SpellRunner }              from "src/test-harness/SpellRunner.sol";
import { SpellTests }               from "src/test-harness/SpellTests.sol";

import { 
    IMorphoVaultV2Like,
    IMorphoMarketV1AdapterV2FactoryLike,
    ITreasuryControllerLike
} from "src/interfaces/Interfaces.sol";

interface IMorphoVaultV2ConfigLike {

    function absoluteCap(bytes32 id) external view returns (uint256);

    function forceDeallocatePenalty(address adapter) external view returns (uint256);

    function relativeCap(bytes32 id) external view returns (uint256);

    function setSendAssetsGate(address newSendAssetsGate) external;

    function setPerformanceFee(uint256 newPerformanceFee) external;

    function setManagementFee(uint256 newManagementFee) external;

    function setPerformanceFeeRecipient(address newPerformanceFeeRecipient) external;

    function setManagementFeeRecipient(address newManagementFeeRecipient) external;

}

interface IMorphoMarketV1AdapterLike {

    function abdicate(bytes4 selector) external;

    function abdicated(bytes4 selector) external view returns (bool);

    function asset() external view returns (address);

    function burnShares(bytes32 marketId) external;

    function increaseTimelock(bytes4 selector, uint256 newDuration) external;

    function morpho() external view returns (address);

    function parentVault() external view returns (address);

    function setSkimRecipient(address newSkimRecipient) external;

    function skimRecipient() external view returns (address);

    function timelock(bytes4 selector) external view returns (uint256);

}

interface IVaultV2FactoryLike {

    function isVaultV2(address account) external view returns (bool);

}

interface ISafeLike {

    function getThreshold() external view returns (uint256);

    function isOwner(address owner) external view returns (bool);

}

contract SparkEthereum_20260910_SLLTests is SparkLiquidityLayerTests {

    address internal constant SAFE_SIGNER_1               = 0xAB5710211458FC8d7E0Be628202F47DdbD3F38Eb;  // Soter Labs owned multisig
    address internal constant SAFE_SIGNER_2               = 0x9e396dE3312D373b87F9BD8763fb48184b42aac0;  // Sentora owned, 1:1 safe, MPC controlled
    address internal constant SENTORA_RLUSD_VAULT_ADAPTER = 0x743C8eb5dE31E41dEF9048DA268EBd036567cd4e;
    address internal constant SENTORA_SPARK_CURATOR       = 0xff070333654aaE76A0A77465E4F0fd101C57c03F;  // 2/2 multisig, Soter and Sentora
    address internal constant SENTORA_ALLOCATOR           = 0xC4Ba4e822C420452fe2BAB93211208D3CcBd79D3;  // Automated EOA address owned by Sentora
    address internal constant SENTORA_SENTINEL            = 0x9e396dE3312D373b87F9BD8763fb48184b42aac0;  // Sentora owned, 1:1 safe, MPC controlled, same as signer on SENTORA_SPARK_CURATOR
    address internal constant SENTORA_FEE_RECIPIENT       = 0xbE6b7dCa8D5FCE23B07E0Da9b01d466b95b3EDF3;  // Sentora owned address
    address internal constant VAULT_SENTINEL              = 0xb5bFd4883256089Dc58D962b80ab7068e71E7c80;  // Soter Labs owned multisig
    address internal constant WBTC_RLUSD_ORACLE           = 0xF58725eb213161E9054C97F970DC80b2d0327E8d;

    uint256 internal constant USDG_BALANCES_SLOT_INDEX = 1;

    constructor() {
        _spellId   = 20260910;
        _blockDate = 1788318977;  // 2026-09-02T03:16:17Z
    }

    function setUp() public override {
        super.setUp();
    }

    function deal(address token, address to, uint256 amount) internal override {
        if (token == Ethereum.USDG) {
            vm.store(Ethereum.USDG, keccak256(abi.encode(to, USDG_BALANCES_SLOT_INDEX)), bytes32(amount));
            return;
        }
        super.deal(token, to, amount);
    }

    /**********************************************************************************************/
    /*** Ethereum - Offboard Unused Integrations                                                ***/
    /**********************************************************************************************/

    function test_ETHEREUM_sll_deactivateMorphoV1DaiVault() external onChain(ChainIdUtils.Ethereum()) {
        MainnetController controller = MainnetController(_getSparkLiquidityLayerContext().controller);

        bytes32 depositKey  = RateLimitHelpers.makeAddressKey(controller.LIMIT_4626_DEPOSIT(),  Ethereum.MORPHO_VAULT_DAI_1);
        bytes32 withdrawKey = RateLimitHelpers.makeAddressKey(controller.LIMIT_4626_WITHDRAW(), Ethereum.MORPHO_VAULT_DAI_1);

        _assertRateLimit(depositKey, 200_000_000e18, 100_000_000e18 / uint256(1 days));
        _assertUnlimitedRateLimit(withdrawKey);

        _executeAllPayloadsAndBridges();

        _assertRateLimit(depositKey,  0, 0);
        _assertRateLimit(withdrawKey, 0, 0);
    }

    function test_ETHEREUM_sll_deactivateMorphoV1UsdsVault() external onChain(ChainIdUtils.Ethereum()) {
        MainnetController controller = MainnetController(_getSparkLiquidityLayerContext().controller);

        bytes32 depositKey  = RateLimitHelpers.makeAddressKey(controller.LIMIT_4626_DEPOSIT(),  Ethereum.MORPHO_VAULT_USDS);
        bytes32 withdrawKey = RateLimitHelpers.makeAddressKey(controller.LIMIT_4626_WITHDRAW(), Ethereum.MORPHO_VAULT_USDS);

        _assertRateLimit(depositKey, 200_000_000e18, 100_000_000e18 / uint256(1 days));
        _assertUnlimitedRateLimit(withdrawKey);

        _executeAllPayloadsAndBridges();

        _assertRateLimit(depositKey,  0, 0);
        _assertRateLimit(withdrawKey, 0, 0);
    }

    function test_ETHEREUM_sll_deactivateAaveCoreUsde() external onChain(ChainIdUtils.Ethereum()) {
        MainnetController controller = MainnetController(_getSparkLiquidityLayerContext().controller);

        bytes32 depositKey  = RateLimitHelpers.makeAddressKey(controller.LIMIT_AAVE_DEPOSIT(),  Ethereum.ATOKEN_CORE_USDE);
        bytes32 withdrawKey = RateLimitHelpers.makeAddressKey(controller.LIMIT_AAVE_WITHDRAW(), Ethereum.ATOKEN_CORE_USDE);

        _assertRateLimit(depositKey, 250_000_000e18, 100_000_000e18 / uint256(1 days));
        _assertUnlimitedRateLimit(withdrawKey);

        _executeAllPayloadsAndBridges();

        _assertRateLimit(depositKey,  0, 0);
        _assertRateLimit(withdrawKey, 0, 0);
    }

    function test_ETHEREUM_sll_deactivateEthena() external onChain(ChainIdUtils.Ethereum()) {
        MainnetController controller = MainnetController(_getSparkLiquidityLayerContext().controller);

        // The three Ethena limits are global keys, not wrapped with a venue address.
        bytes32 mintKey     = controller.LIMIT_USDE_MINT();
        bytes32 burnKey     = controller.LIMIT_USDE_BURN();
        bytes32 cooldownKey = controller.LIMIT_SUSDE_COOLDOWN();

        bytes32 susdeDepositKey  = RateLimitHelpers.makeAddressKey(controller.LIMIT_4626_DEPOSIT(),  Ethereum.SUSDE);
        bytes32 susdeWithdrawKey = RateLimitHelpers.makeAddressKey(controller.LIMIT_4626_WITHDRAW(), Ethereum.SUSDE);

        _assertRateLimit(mintKey, 250_000_000e6,  100_000_000e6 / uint256(1 days));
        _assertRateLimit(burnKey, 500_000_000e18, 200_000_000e18 / uint256(1 days));
        _assertUnlimitedRateLimit(cooldownKey);

        _assertRateLimit(susdeDepositKey, 250_000_000e18, 100_000_000e18 / uint256(1 days));

        _assertRateLimit(susdeWithdrawKey, 0, 0);

        _executeAllPayloadsAndBridges();

        _assertRateLimit(mintKey,          0, 0);
        _assertRateLimit(burnKey,          0, 0);
        _assertRateLimit(cooldownKey,      0, 0);
        _assertRateLimit(susdeDepositKey,  0, 0);
        _assertRateLimit(susdeWithdrawKey, 0, 0);
    }

    function test_ETHEREUM_sll_deactivateMapleSyrupUsdt() external onChain(ChainIdUtils.Ethereum()) {
        MainnetController controller = MainnetController(_getSparkLiquidityLayerContext().controller);

        bytes32 depositKey  = RateLimitHelpers.makeAddressKey(controller.LIMIT_4626_DEPOSIT(),  Ethereum.SYRUP_USDT);
        bytes32 withdrawKey = RateLimitHelpers.makeAddressKey(controller.LIMIT_4626_WITHDRAW(), Ethereum.SYRUP_USDT);
        bytes32 redeemKey   = RateLimitHelpers.makeAddressKey(controller.LIMIT_MAPLE_REDEEM(),  Ethereum.SYRUP_USDT);

        _assertRateLimit(depositKey, 50_000_000e6, 100_000_000e6 / uint256(1 days));
        _assertUnlimitedRateLimit(withdrawKey);
        _assertUnlimitedRateLimit(redeemKey);

        _executeAllPayloadsAndBridges();

        _assertRateLimit(depositKey,  0, 0);
        _assertRateLimit(withdrawKey, 0, 0);
        _assertRateLimit(redeemKey,   0, 0);
    }

    function test_ETHEREUM_sll_deactivateMapleSyrupUsdc() external onChain(ChainIdUtils.Ethereum()) {
        MainnetController controller = MainnetController(_getSparkLiquidityLayerContext().controller);

        bytes32 depositKey  = RateLimitHelpers.makeAddressKey(controller.LIMIT_4626_DEPOSIT(),  Ethereum.SYRUP_USDC);
        bytes32 withdrawKey = RateLimitHelpers.makeAddressKey(controller.LIMIT_4626_WITHDRAW(), Ethereum.SYRUP_USDC);
        bytes32 redeemKey   = RateLimitHelpers.makeAddressKey(controller.LIMIT_MAPLE_REDEEM(),  Ethereum.SYRUP_USDC);

        _assertRateLimit(depositKey, 100_000_000e6, 20_000_000e6 / uint256(1 days));
        _assertUnlimitedRateLimit(withdrawKey);
        _assertUnlimitedRateLimit(redeemKey);

        _executeAllPayloadsAndBridges();

        _assertRateLimit(depositKey,  0, 0);
        _assertRateLimit(withdrawKey, 0, 0);
        _assertRateLimit(redeemKey,   0, 0);
    }

    function test_ETHEREUM_sll_deactivateCurvePyusdUsds() external onChain(ChainIdUtils.Ethereum()) {
        MainnetController controller = MainnetController(_getSparkLiquidityLayerContext().controller);

        bytes32 depositKey  = RateLimitHelpers.makeAddressKey(controller.LIMIT_CURVE_DEPOSIT(),  Ethereum.CURVE_PYUSDUSDS);
        bytes32 withdrawKey = RateLimitHelpers.makeAddressKey(controller.LIMIT_CURVE_WITHDRAW(), Ethereum.CURVE_PYUSDUSDS);
        bytes32 swapKey     = RateLimitHelpers.makeAddressKey(controller.LIMIT_CURVE_SWAP(),     Ethereum.CURVE_PYUSDUSDS);

        _assertRateLimit(depositKey,  5_000_000e18, 50_000_000e18 / uint256(1 days));
        _assertRateLimit(withdrawKey, 5_000_000e18, 100_000_000e18 / uint256(1 days));
        _assertRateLimit(swapKey,     5_000_000e18, 50_000_000e18 / uint256(1 days));

        _executeAllPayloadsAndBridges();

        _assertRateLimit(depositKey,  0, 0);
        _assertRateLimit(withdrawKey, 0, 0);
        _assertRateLimit(swapKey,     0, 0);
    }

    function test_ETHEREUM_sll_deactivateCurvePyusdUsdc() external onChain(ChainIdUtils.Ethereum()) {
        MainnetController controller = MainnetController(_getSparkLiquidityLayerContext().controller);

        bytes32 depositKey  = RateLimitHelpers.makeAddressKey(controller.LIMIT_CURVE_DEPOSIT(),  Ethereum.CURVE_PYUSDUSDC);
        bytes32 withdrawKey = RateLimitHelpers.makeAddressKey(controller.LIMIT_CURVE_WITHDRAW(), Ethereum.CURVE_PYUSDUSDC);
        bytes32 swapKey     = RateLimitHelpers.makeAddressKey(controller.LIMIT_CURVE_SWAP(),     Ethereum.CURVE_PYUSDUSDC);

        // The deposit and withdraw limits were never configured; only the swap leg is zeroed.
        _assertRateLimit(depositKey,  0,            0);
        _assertRateLimit(withdrawKey, 0,            0);
        _assertRateLimit(swapKey,     5_000_000e18, 100_000_000e18 / uint256(1 days));

        _executeAllPayloadsAndBridges();

        _assertRateLimit(depositKey,  0, 0);
        _assertRateLimit(withdrawKey, 0, 0);
        _assertRateLimit(swapKey,     0, 0);
    }

    function test_ETHEREUM_sll_deactivateCurveSusdsUsdt() external onChain(ChainIdUtils.Ethereum()) {
        MainnetController controller = MainnetController(_getSparkLiquidityLayerContext().controller);

        bytes32 depositKey  = RateLimitHelpers.makeAddressKey(controller.LIMIT_CURVE_DEPOSIT(),  Ethereum.CURVE_SUSDSUSDT);
        bytes32 withdrawKey = RateLimitHelpers.makeAddressKey(controller.LIMIT_CURVE_WITHDRAW(), Ethereum.CURVE_SUSDSUSDT);
        bytes32 swapKey     = RateLimitHelpers.makeAddressKey(controller.LIMIT_CURVE_SWAP(),     Ethereum.CURVE_SUSDSUSDT);

        _assertRateLimit(depositKey,  5_000_000e18,  20_000_000e18 / uint256(1 days));
        _assertRateLimit(withdrawKey, 25_000_000e18, 100_000_000e18 / uint256(1 days));
        _assertRateLimit(swapKey,     10_000_000e18, 200_000_000e18 / uint256(1 days));

        _executeAllPayloadsAndBridges();

        _assertRateLimit(depositKey,  0, 0);
        _assertRateLimit(withdrawKey, 0, 0);
        _assertRateLimit(swapKey,     0, 0);
    }

    function test_ETHEREUM_sll_deactivateCurveUsdcUsdt() external onChain(ChainIdUtils.Ethereum()) {
        MainnetController controller = MainnetController(_getSparkLiquidityLayerContext().controller);

        bytes32 depositKey  = RateLimitHelpers.makeAddressKey(controller.LIMIT_CURVE_DEPOSIT(),  Ethereum.CURVE_USDCUSDT);
        bytes32 withdrawKey = RateLimitHelpers.makeAddressKey(controller.LIMIT_CURVE_WITHDRAW(), Ethereum.CURVE_USDCUSDT);
        bytes32 swapKey     = RateLimitHelpers.makeAddressKey(controller.LIMIT_CURVE_SWAP(),     Ethereum.CURVE_USDCUSDT);

        // The deposit and withdraw limits were zeroed on 2025-04-21; only the swap leg is zeroed.
        _assertRateLimit(depositKey,  0,            0);
        _assertRateLimit(withdrawKey, 0,            0);
        _assertRateLimit(swapKey,     5_000_000e18, 20_000_000e18 / uint256(1 days));

        _executeAllPayloadsAndBridges();

        _assertRateLimit(depositKey,  0, 0);
        _assertRateLimit(withdrawKey, 0, 0);
        _assertRateLimit(swapKey,     0, 0);
    }

    function test_ETHEREUM_sll_deactivateCurveWeethWethng() external onChain(ChainIdUtils.Ethereum()) {
        MainnetController controller = MainnetController(_getSparkLiquidityLayerContext().controller);

        bytes32 depositKey  = RateLimitHelpers.makeAddressKey(controller.LIMIT_CURVE_DEPOSIT(),  Ethereum.CURVE_WEETHWETHNG);
        bytes32 withdrawKey = RateLimitHelpers.makeAddressKey(controller.LIMIT_CURVE_WITHDRAW(), Ethereum.CURVE_WEETHWETHNG);
        bytes32 swapKey     = RateLimitHelpers.makeAddressKey(controller.LIMIT_CURVE_SWAP(),     Ethereum.CURVE_WEETHWETHNG);

        // The deposit and withdraw limits were never configured; only the swap leg is zeroed.
        _assertRateLimit(depositKey,  0,        0);
        _assertRateLimit(withdrawKey, 0,        0);
        _assertRateLimit(swapKey,     1_000e18, 50_000e18 / uint256(1 days));

        _executeAllPayloadsAndBridges();

        _assertRateLimit(depositKey,  0, 0);
        _assertRateLimit(withdrawKey, 0, 0);
        _assertRateLimit(swapKey,     0, 0);
    }

    function test_ETHEREUM_sll_deactivateSuperstate() external onChain(ChainIdUtils.Ethereum()) {
        MainnetController controller = MainnetController(_getSparkLiquidityLayerContext().controller);

        bytes32 transferKey = controller.LIMIT_ASSET_TRANSFER();

        bytes32 ustbSubscribeKey = controller.LIMIT_SUPERSTATE_SUBSCRIBE();
        bytes32 ustbRedeemKey    = RateLimitHelpers.makeAddressAddressKey(transferKey, Ethereum.USTB, Ethereum.USTB);
        // Orphaned storage entry: the v1.10.0 controller does not declare LIMIT_SUPERSTATE_REDEEM.
        bytes32 legacyRedeemKey  = keccak256("LIMIT_SUPERSTATE_REDEEM");
        bytes32 usccSubscribeKey = RateLimitHelpers.makeAddressAddressKey(transferKey, Ethereum.USDC, Ethereum.USCC_DEPOSIT);
        bytes32 usccRedeemKey    = RateLimitHelpers.makeAddressAddressKey(transferKey, Ethereum.USCC, Ethereum.USCC);

        _assertRateLimit(ustbSubscribeKey, 300_000_000e6, 100_000_000e6 / uint256(1 days));

        _assertUnlimitedRateLimit(ustbRedeemKey);
        _assertUnlimitedRateLimit(legacyRedeemKey);

        _assertRateLimit(usccSubscribeKey, 100_000_000e6, 50_000_000e6 / uint256(1 days));
        _assertUnlimitedRateLimit(usccRedeemKey);

        _executeAllPayloadsAndBridges();

        _assertRateLimit(ustbSubscribeKey, 0, 0);
        _assertRateLimit(ustbRedeemKey,    0, 0);
        _assertRateLimit(legacyRedeemKey,  0, 0);
        _assertRateLimit(usccSubscribeKey, 0, 0);
        _assertRateLimit(usccRedeemKey,    0, 0);
    }

    function test_ETHEREUM_sll_deactivateB2C2() external onChain(ChainIdUtils.Ethereum()) {
        MainnetController controller = MainnetController(_getSparkLiquidityLayerContext().controller);

        bytes32 transferKey = controller.LIMIT_ASSET_TRANSFER();

        bytes32 usdcKey  = RateLimitHelpers.makeAddressAddressKey(transferKey, Ethereum.USDC,  Ethereum.B2C2_DEPOSIT_ADDRESS);
        bytes32 usdtKey  = RateLimitHelpers.makeAddressAddressKey(transferKey, Ethereum.USDT,  Ethereum.B2C2_DEPOSIT_ADDRESS);
        bytes32 pyusdKey = RateLimitHelpers.makeAddressAddressKey(transferKey, Ethereum.PYUSD, Ethereum.B2C2_DEPOSIT_ADDRESS);

        _assertRateLimit(usdcKey,  1_000_000e6, 20_000_000e6 / uint256(1 days));
        _assertRateLimit(usdtKey,  1_000_000e6, 20_000_000e6 / uint256(1 days));
        _assertRateLimit(pyusdKey, 1_000_000e6, 20_000_000e6 / uint256(1 days));

        _executeAllPayloadsAndBridges();

        _assertRateLimit(usdcKey,  0, 0);
        _assertRateLimit(usdtKey,  0, 0);
        _assertRateLimit(pyusdKey, 0, 0);
    }

    function test_ETHEREUM_sll_deactivateAnchorageUsdtUsat() external onChain(ChainIdUtils.Ethereum()) {
        MainnetController controller = MainnetController(_getSparkLiquidityLayerContext().controller);

        bytes32 transferKey = controller.LIMIT_ASSET_TRANSFER();

        bytes32 usdtKey = RateLimitHelpers.makeAddressAddressKey(transferKey, Ethereum.USDT, Ethereum.ANCHORAGE_USAT_USDT_DEPOSIT);
        bytes32 usatKey = RateLimitHelpers.makeAddressAddressKey(transferKey, Ethereum.USAT, Ethereum.ANCHORAGE_USAT_USDT_DEPOSIT);
        bytes32 usdcKey = RateLimitHelpers.makeAddressAddressKey(transferKey, Ethereum.USDC, Ethereum.ANCHORAGE_USAT_USDT_DEPOSIT);

        _assertRateLimit(usdtKey, 50_000_000e6, 250_000_000e6 / uint256(1 days));
        _assertRateLimit(usatKey, 50_000_000e6, 250_000_000e6 / uint256(1 days));
        _assertRateLimit(usdcKey, 50_000_000e6, 250_000_000e6 / uint256(1 days));

        _executeAllPayloadsAndBridges();

        _assertRateLimit(usdtKey, 0, 0);
        _assertRateLimit(usatKey, 0, 0);

        // The actively used Anchorage USDC leg shares the same destination address and stays
        // untouched.
        _assertRateLimit(usdcKey, 50_000_000e6, 250_000_000e6 / uint256(1 days));
    }

    /**********************************************************************************************/
    /*** Ethereum - Onboard Sentora RLUSD Morpho Vaults V2                                      ***/
    /**********************************************************************************************/

    function test_ETHEREUM_sll_onboardSentoraRlusdVault() external onChain(ChainIdUtils.Ethereum()) {
        _testERC4626Onboarding({
            vault                 : SENTORA_RLUSD_VAULT,
            expectedDepositAmount : 1_000_000e18,
            depositMax            : 10_000_000e18,
            depositSlope          : 100_000_000e18 / uint256(1 days),
            maxSlippage           : 0
        });

        assertEq(MainnetController(Ethereum.ALM_CONTROLLER).maxExchangeRates(SENTORA_RLUSD_VAULT), 3e36);
    }

    function test_ETHEREUM_morphoVaultV2Config() external onChain(ChainIdUtils.Ethereum()) {
        IMorphoVaultV2Like       vault = IMorphoVaultV2Like(SENTORA_RLUSD_VAULT);
        IMorphoVaultV2ConfigLike caps  = IMorphoVaultV2ConfigLike(SENTORA_RLUSD_VAULT);

        assertEq(IVaultV2FactoryLike(Ethereum.MORPHO_VAULT_V2_FACTORY).isVaultV2(address(vault)), true);

        assertEq(vault.name(),   "Sentora x Spark RLUSD");
        assertEq(vault.symbol(), "sxsRLUSD");
        assertEq(vault.asset(),  Ethereum.RLUSD);
        assertEq(vault.owner(),  Ethereum.SPARK_PROXY);

        // Curator is the 2-of-2 Safe.
        assertEq(vault.curator(), SENTORA_SPARK_CURATOR);

        assertEq(ISafeLike(SENTORA_SPARK_CURATOR).getThreshold(), 2);

        assertEq(ISafeLike(SENTORA_SPARK_CURATOR).isOwner(SAFE_SIGNER_1), true);
        assertEq(ISafeLike(SENTORA_SPARK_CURATOR).isOwner(SAFE_SIGNER_2), true);

        assertEq(vault.isSentinel(Ethereum.MORPHO_GUARDIAN_MULTISIG), true);
        assertEq(vault.isSentinel(VAULT_SENTINEL),                    true);
        assertEq(vault.isSentinel(SENTORA_SENTINEL),                  true);

        assertEq(vault.isAllocator(SENTORA_ALLOCATOR),             true);
        assertEq(vault.isAllocator(SENTORA_SENTINEL),              true);
        assertEq(vault.isAllocator(Ethereum.ALM_PROXY),            false);
        assertEq(vault.isAllocator(Ethereum.ALM_RELAYER_MULTISIG), false);
        assertEq(vault.isAllocator(Ethereum.SPARK_PROXY),          false);
        assertEq(vault.isAllocator(SENTORA_SPARK_CURATOR),         false);

        // setAdapterRegistry and the three critical gate setters are permanently abdicated;
        // setSendAssetsGate is not abdicated but sits behind the 7-day timelock.
        assertEq(vault.abdicated(IMorphoVaultV2Like.setAdapterRegistry.selector),      true);
        assertEq(vault.abdicated(IMorphoVaultV2Like.setReceiveSharesGate.selector),    true);
        assertEq(vault.abdicated(IMorphoVaultV2Like.setSendSharesGate.selector),       true);
        assertEq(vault.abdicated(IMorphoVaultV2Like.setReceiveAssetsGate.selector),    true);
        assertEq(vault.abdicated(IMorphoVaultV2ConfigLike.setSendAssetsGate.selector), false);

        // Per-selector timelocks
        assertEq(vault.timelock(IMorphoVaultV2Like.increaseAbsoluteCap.selector),              7 days);
        assertEq(vault.timelock(IMorphoVaultV2Like.increaseRelativeCap.selector),              7 days);
        assertEq(vault.timelock(IMorphoVaultV2Like.abdicate.selector),                         7 days);
        assertEq(vault.timelock(IMorphoVaultV2Like.addAdapter.selector),                       7 days);
        assertEq(vault.timelock(IMorphoVaultV2Like.removeAdapter.selector),                    7 days);
        assertEq(vault.timelock(IMorphoVaultV2Like.increaseTimelock.selector),                 7 days);
        assertEq(vault.timelock(IMorphoVaultV2Like.setForceDeallocatePenalty.selector),        7 days);
        assertEq(vault.timelock(IMorphoVaultV2ConfigLike.setSendAssetsGate.selector),          7 days);
        assertEq(vault.timelock(IMorphoVaultV2Like.setIsAllocator.selector),                   3 days);
        assertEq(vault.timelock(IMorphoVaultV2ConfigLike.setPerformanceFee.selector),          3 days);
        assertEq(vault.timelock(IMorphoVaultV2ConfigLike.setManagementFee.selector),           3 days);
        assertEq(vault.timelock(IMorphoVaultV2ConfigLike.setPerformanceFeeRecipient.selector), 3 days);
        assertEq(vault.timelock(IMorphoVaultV2ConfigLike.setManagementFeeRecipient.selector),  3 days);

        assertEq(vault.adapterRegistry(), Ethereum.MORPHO_VAULT_V2_ADAPTER_REGISTRY);

        assertEq(vault.adaptersLength(), 1);
        assertEq(vault.adapters(0),      SENTORA_RLUSD_VAULT_ADAPTER);

        assertEq(vault.isAdapter(SENTORA_RLUSD_VAULT_ADAPTER), true);

        assertEq(vault.liquidityAdapter(), SENTORA_RLUSD_VAULT_ADAPTER);

        // Check adapter and liquidity adapter are from factory
        IMorphoMarketV1AdapterV2FactoryLike adapterFactory = IMorphoMarketV1AdapterV2FactoryLike(Ethereum.MORPHO_MARKET_V1_ADAPTER_V2_FACTORY);

        assertEq(adapterFactory.isMorphoMarketV1AdapterV2(vault.adapters(0)),        true);
        assertEq(adapterFactory.isMorphoMarketV1AdapterV2(vault.liquidityAdapter()), true);

        // Force-deallocating through the adapter carries no penalty, so the sentinel exit
        // path costs depositors nothing.
        assertEq(caps.forceDeallocatePenalty(SENTORA_RLUSD_VAULT_ADAPTER), 0);

        // Fees and rate cap.
        assertEq(vault.performanceFee(),          0.1e18);
        assertEq(vault.performanceFeeRecipient(), SENTORA_FEE_RECIPIENT);
        assertEq(vault.managementFee(),           0);
        assertEq(vault.managementFeeRecipient(),  SENTORA_FEE_RECIPIENT);

        assertEq(vault.maxRate(), 2e18 / uint256(365 days));  // 200% APR cap

        bytes32 adapterId    = keccak256(abi.encode("this", SENTORA_RLUSD_VAULT_ADAPTER));
        bytes32 collateralId = keccak256(abi.encode("collateralToken", Ethereum.WBTC));
        bytes32 marketId     = keccak256(abi.encode(
            "this/marketParams",
            SENTORA_RLUSD_VAULT_ADAPTER,
            MarketParams({
                loanToken:       Ethereum.RLUSD,
                collateralToken: Ethereum.WBTC,
                oracle:          WBTC_RLUSD_ORACLE,
                irm:             Ethereum.MORPHO_DEFAULT_IRM,
                lltv:            0.86e18
            })
        ));

        assertEq(caps.absoluteCap(adapterId),    type(uint128).max);
        assertEq(caps.relativeCap(adapterId),    1e18);
        assertEq(caps.absoluteCap(collateralId), type(uint128).max);
        assertEq(caps.relativeCap(collateralId), 1e18);
        assertEq(caps.absoluteCap(marketId),     250_000_000e18);
        assertEq(caps.relativeCap(marketId),     1e18);

        // Dead-deposit seed.
        assertEq(IERC20(address(vault)).balanceOf(address(0xdead)), 1e9);

        assertGe(vault.totalAssets(), 1e9);
    }

    function test_ETHEREUM_morphoVaultV2AdapterConfig() external onChain(ChainIdUtils.Ethereum()) {
        IMorphoMarketV1AdapterLike adapter = IMorphoMarketV1AdapterLike(SENTORA_RLUSD_VAULT_ADAPTER);

        assertEq(adapter.parentVault(), SENTORA_RLUSD_VAULT);
        assertEq(adapter.morpho(),      Ethereum.MORPHO);
        assertEq(adapter.asset(),       Ethereum.RLUSD);

        assertEq(adapter.skimRecipient(), address(0));

        assertEq(adapter.abdicated(IMorphoMarketV1AdapterLike.abdicate.selector),         false);
        assertEq(adapter.abdicated(IMorphoMarketV1AdapterLike.burnShares.selector),       false);
        assertEq(adapter.abdicated(IMorphoMarketV1AdapterLike.increaseTimelock.selector), false);
        assertEq(adapter.abdicated(IMorphoMarketV1AdapterLike.setSkimRecipient.selector), false);

        // Per-selector timelocks. burnShares is set to 7 days, above the 3-day minimum.
        assertEq(adapter.timelock(IMorphoMarketV1AdapterLike.abdicate.selector),         7 days);
        assertEq(adapter.timelock(IMorphoMarketV1AdapterLike.burnShares.selector),       7 days);
        assertEq(adapter.timelock(IMorphoMarketV1AdapterLike.increaseTimelock.selector), 7 days);
        assertEq(adapter.timelock(IMorphoMarketV1AdapterLike.setSkimRecipient.selector), 3 days);
    }

}

contract SparkEthereum_20260910_SparklendTests is SparklendTests {

    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;

    address internal constant GNOSIS_USER = 0x9b8eaBBCBE8D6b33037E85A515679D118039861e;

    address internal constant OLD_USDT_IRM = 0x4E494988E68e6Fc52309BE4937869e27F0C304AC;
    address internal constant NEW_USDT_IRM = 0x4FA65B096681bD6FeecF78e5D83096bf4A5762A0;

    constructor() {
        _spellId   = 20260910;
        _blockDate = 1788318977;  // 2026-09-02T03:16:17Z
    }

    function setUp() public override {
        super.setUp();
    }

    function test_ETHEREUM_sparkLend_deprecateLbtcCollateral() external onChain(ChainIdUtils.Ethereum()) {
        SparkLendContext memory ctx = _getSparkLendContext();

        ReserveConfig[] memory allConfigsBefore = _createConfigurationSnapshot('', ctx.pool);

        ReserveConfig memory lbtcConfigBefore = _findReserveConfigBySymbol(allConfigsBefore, 'LBTC');

        assertEq(lbtcConfigBefore.ltv,                    74_00);
        assertEq(lbtcConfigBefore.liquidationThreshold,   75_00);
        assertEq(lbtcConfigBefore.liquidationBonus,       108_00);
        assertEq(lbtcConfigBefore.liquidationProtocolFee, 10_00);
        assertEq(lbtcConfigBefore.eModeCategory,          0);
        assertEq(lbtcConfigBefore.isFrozen,               false);

        _executeAllPayloadsAndBridges();

        ReserveConfig[] memory allConfigsAfter = _createConfigurationSnapshot('', ctx.pool);

        ReserveConfig memory lbtcConfigAfter = lbtcConfigBefore;

        lbtcConfigAfter.ltv = 0;

        _validateReserveConfig(lbtcConfigAfter, allConfigsAfter);
    }

    function test_ETHEREUM_sparkLend_lbtcDeprecationDoesNotReduceHealthFactor() external onChain(ChainIdUtils.Ethereum()) {
        SparkLendContext memory ctx = _getSparkLendContext();

        ReserveConfig[] memory allConfigs = _createConfigurationSnapshot('', ctx.pool);

        ReserveConfig memory lbtcConfig = _findReserveConfigBySymbol(allConfigs, 'LBTC');
        ReserveConfig memory usdcConfig = _findReserveConfigBySymbol(allConfigs, 'USDC');

        address user       = makeAddr("lbtcCollateralBorrower");
        address liquidator = makeAddr("lbtcLiquidator");

        // Set up a live LBTC-collateralised borrow position before execution.
        _supply(lbtcConfig, ctx.pool, user, 1e8);
        _borrow(usdcConfig, ctx.pool, user, 10_000e6, false);

        ( , , uint256 availableBorrowsBefore, uint256 thresholdBefore, uint256 ltvBefore, uint256 healthFactorBefore )
            = ctx.pool.getUserAccountData(user);

        assertEq(ltvBefore,       74_00);
        assertEq(thresholdBefore, 75_00);

        assertGt(availableBorrowsBefore, 0);
        assertGt(healthFactorBefore,     1e18);

        _executeAllPayloadsAndBridges();

        ( , , uint256 availableBorrowsAfter, uint256 thresholdAfter, uint256 ltvAfter, uint256 healthFactorAfter )
            = ctx.pool.getUserAccountData(user);

        // The health factor is a function of the liquidation threshold only, never of the LTV, and
        // the spell leaves the LBTC liquidation threshold at 75%. The user's collateral flag is
        // also untouched, so LBTC keeps contributing its full threshold-weighted value and the
        // existing position is exactly as safe as it was before execution.
        assertEq(thresholdAfter,    thresholdBefore);
        assertEq(healthFactorAfter, healthFactorBefore);

        // The position is still above water, so a fully funded liquidator cannot touch it.
        deal(usdcConfig.underlying, liquidator, 10_000e6);

        vm.startPrank(liquidator);
        IERC20(usdcConfig.underlying).approve(address(ctx.pool), type(uint256).max);
        vm.expectRevert(bytes("45"));  // HEALTH_FACTOR_NOT_BELOW_THRESHOLD
        ctx.pool.liquidationCall(lbtcConfig.underlying, usdcConfig.underlying, user, type(uint256).max, false);
        vm.stopPrank();

        // Only borrowing power is removed: LBTC no longer contributes any LTV, so the position
        // cannot be levered further.
        assertEq(ltvAfter,              0);
        assertEq(availableBorrowsAfter, 0);

        vm.prank(user);
        vm.expectRevert(bytes("57"));  // LTV_VALIDATION_FAILED
        ctx.pool.borrow(usdcConfig.underlying, 1, 2, 0, user);
    }

    function test_ETHEREUM_sparkLend_usdtIrmUpdate() external onChain(ChainIdUtils.Ethereum()) {
        RateTargetKinkIRMParams memory oldParams = RateTargetKinkIRMParams({
            irm                      : OLD_USDT_IRM,
            baseRate                 : 0,
            variableRateSlope1Spread : 0.005e27,
            variableRateSlope2       : 0.15e27,
            optimalUsageRatio        : 0.95e27
        });
        RateTargetKinkIRMParams memory newParams = RateTargetKinkIRMParams({
            irm                      : NEW_USDT_IRM,
            baseRate                 : 0,
            variableRateSlope1Spread : 0.001e27,
            variableRateSlope2       : 0.15e27,
            optimalUsageRatio        : 0.95e27
        });
        _testRateTargetKinkIRMUpdate("USDT", oldParams, newParams);
    }

    function test_GNOSIS_sparkLend_completeDeprecation() external onChain(ChainIdUtils.Gnosis()) {
        IPool pool = IPool(Gnosis.POOL);

        address[5] memory collateralReserves = [Gnosis.WXDAI,    Gnosis.WETH, Gnosis.WSTETH, Gnosis.GNO, Gnosis.SXDAI];
        uint256[5] memory ltvsBefore         = [uint256(0),      70_00,       65_00,         40_00,      70_00];
        uint256[5] memory thresholdsBefore   = [uint256(75_00),  75_00,       72_50,         50_00,      75_00];
        uint256[5] memory bonuses            = [uint256(105_00), 105_00,      108_00,        112_00,     106_00];

        for (uint256 i; i < 5; ++i) {
            DataTypes.ReserveConfigurationMap memory config = pool.getConfiguration(collateralReserves[i]);

            assertEq(config.getLtv(),                    ltvsBefore[i]);
            assertEq(config.getLiquidationThreshold(),   thresholdsBefore[i]);
            assertEq(config.getLiquidationBonus(),       bonuses[i]);
            assertEq(config.getLiquidationProtocolFee(), 10_00);
        }

        assertEq(pool.getConfiguration(Gnosis.WETH).getEModeCategory(),   1);
        assertEq(pool.getConfiguration(Gnosis.WSTETH).getEModeCategory(), 1);

        DataTypes.EModeCategory memory categoryBefore = pool.getEModeCategoryData(1);

        assertEq(categoryBefore.ltv,                  85_00);
        assertEq(categoryBefore.liquidationThreshold, 90_00);
        assertEq(categoryBefore.liquidationBonus,     103_00);

        address[4] memory stablecoinReserves = [Gnosis.USDC, Gnosis.USDT, Gnosis.EURE, Gnosis.USDCE];

        for (uint256 i; i < 4; ++i) {
            DataTypes.ReserveConfigurationMap memory config = pool.getConfiguration(stablecoinReserves[i]);

            assertEq(config.getLtv(),                    0);
            assertEq(config.getLiquidationThreshold(),   0);
            assertEq(config.getLiquidationBonus(),       0);
            assertEq(config.getLiquidationProtocolFee(), 0);
            assertEq(config.getEModeCategory(),          0);
        }

        _executeAllPayloadsAndBridges();

        // 0.01% is raw 1, since PERCENTAGE_FACTOR == 1e4. Bonuses are restated unchanged and
        // the liquidation protocol fee falls to zero.
        for (uint256 i; i < 5; ++i) {
            DataTypes.ReserveConfigurationMap memory config = pool.getConfiguration(collateralReserves[i]);

            assertEq(config.getLtv(),                    0);
            assertEq(config.getLiquidationThreshold(),   1);
            assertEq(config.getLiquidationBonus(),       bonuses[i]);
            assertEq(config.getLiquidationProtocolFee(), 0);
            assertEq(config.getEModeCategory(),          0);
        }

        assertEq(pool.getConfiguration(Gnosis.WETH).getEModeCategory(),   0);
        assertEq(pool.getConfiguration(Gnosis.WSTETH).getEModeCategory(), 0);

        DataTypes.EModeCategory memory categoryAfter = pool.getEModeCategoryData(1);

        assertEq(categoryAfter.ltv,                  85_00);
        assertEq(categoryAfter.liquidationThreshold, 90_00);
        assertEq(categoryAfter.liquidationBonus,     103_00);

        // The four stablecoin reserves are untouched.
        for (uint256 i; i < 4; ++i) {
            DataTypes.ReserveConfigurationMap memory config = pool.getConfiguration(stablecoinReserves[i]);

            assertEq(config.getLtv(),                    0);
            assertEq(config.getLiquidationThreshold(),   0);
            assertEq(config.getLiquidationBonus(),       0);
            assertEq(config.getLiquidationProtocolFee(), 0);
            assertEq(config.getEModeCategory(),          0);
        }
    }

    function test_GNOSIS_sparkLend_existingBorrowerLiquidation() external onChain(ChainIdUtils.Gnosis()) {
        IPool pool = IPool(Gnosis.POOL);

        address liquidator = makeAddr("liquidator");

        ( , , , , , uint256 healthFactorBefore ) = pool.getUserAccountData(GNOSIS_USER);

        assertEq(healthFactorBefore, 1.908347488618869521e18);

        _executeAllPayloadsAndBridges();

        ( , , , , , uint256 healthFactorAfter ) = pool.getUserAccountData(GNOSIS_USER);

        assertEq(healthFactorAfter, 0.000263147750686966e18);

        deal(Gnosis.USDT, liquidator, 20_000e6);
        deal(Gnosis.USDC, liquidator, 5_000e6);

        vm.startPrank(liquidator);

        IERC20(Gnosis.USDT).approve(address(pool), type(uint256).max);
        IERC20(Gnosis.USDC).approve(address(pool), type(uint256).max);

        assertEq(IERC20(Gnosis.WSTETH).balanceOf(liquidator),           0);
        assertEq(IERC20(Gnosis.USDT_DEBT_TOKEN).balanceOf(GNOSIS_USER), 15_069.309181e6);
        assertEq(IERC20(Gnosis.USDC_DEBT_TOKEN).balanceOf(GNOSIS_USER), 4_098.992721e6);

        pool.liquidationCall(Gnosis.WSTETH, Gnosis.USDT, GNOSIS_USER, type(uint256).max, false);
        pool.liquidationCall(Gnosis.WSTETH, Gnosis.USDC, GNOSIS_USER, type(uint256).max, false);

        assertEq(IERC20(Gnosis.WSTETH).balanceOf(liquidator),           6.893888881583246259e18);
        assertEq(IERC20(Gnosis.USDT_DEBT_TOKEN).balanceOf(GNOSIS_USER), 0);
        assertEq(IERC20(Gnosis.USDC_DEBT_TOKEN).balanceOf(GNOSIS_USER), 0);

        vm.stopPrank();

        ( , , , , , uint256 healthFactorAfterLiquidation ) = pool.getUserAccountData(GNOSIS_USER);

        assertEq(healthFactorAfterLiquidation, type(uint256).max);
    }

    function test_GNOSIS_sparkLend_existingBorrowerWithdrawals() external onChain(ChainIdUtils.Gnosis()) {
        IPool pool = IPool(Gnosis.POOL);

        ( , , , , , uint256 healthFactorBefore ) = pool.getUserAccountData(GNOSIS_USER);

        assertEq(healthFactorBefore, 1.908347488618869521e18);

        _executeAllPayloadsAndBridges();

        ( , , , , , uint256 healthFactorAfter ) = pool.getUserAccountData(GNOSIS_USER);

        assertEq(healthFactorAfter, 0.000263147750686966e18);

        vm.startPrank(GNOSIS_USER);

        vm.expectRevert(bytes("35"));  // HEALTH_FACTOR_LOWER_THAN_LIQUIDATION_THRESHOLD
        pool.withdraw(Gnosis.WETH, type(uint256).max, GNOSIS_USER);

        vm.expectRevert(bytes("35"));  // HEALTH_FACTOR_LOWER_THAN_LIQUIDATION_THRESHOLD
        pool.withdraw(Gnosis.WSTETH, type(uint256).max, GNOSIS_USER);

        vm.stopPrank();

        // After repaying both debts in full the collateral is freely withdrawable.
        deal(Gnosis.USDT, GNOSIS_USER, 20_000e6);
        deal(Gnosis.USDC, GNOSIS_USER, 5_000e6);

        vm.startPrank(GNOSIS_USER);

        IERC20(Gnosis.USDT).approve(address(pool), type(uint256).max);
        IERC20(Gnosis.USDC).approve(address(pool), type(uint256).max);

        assertEq(IERC20(Gnosis.USDT_DEBT_TOKEN).balanceOf(GNOSIS_USER), 15_069.309181e6);
        assertEq(IERC20(Gnosis.USDC_DEBT_TOKEN).balanceOf(GNOSIS_USER), 4_098.992721e6);

        pool.repay(Gnosis.USDT, type(uint256).max, 2, GNOSIS_USER);
        pool.repay(Gnosis.USDC, type(uint256).max, 2, GNOSIS_USER);

        assertEq(IERC20(Gnosis.USDT_DEBT_TOKEN).balanceOf(GNOSIS_USER), 0);
        assertEq(IERC20(Gnosis.USDC_DEBT_TOKEN).balanceOf(GNOSIS_USER), 0);

        assertEq(IERC20(Gnosis.WETH_ATOKEN).balanceOf(GNOSIS_USER),   0.179319706726383979e18);
        assertEq(IERC20(Gnosis.WSTETH_ATOKEN).balanceOf(GNOSIS_USER), 16.653067060541855467e18);

        pool.withdraw(Gnosis.WETH,   type(uint256).max, GNOSIS_USER);
        pool.withdraw(Gnosis.WSTETH, type(uint256).max, GNOSIS_USER);

        vm.stopPrank();

        assertEq(IERC20(Gnosis.WETH_ATOKEN).balanceOf(GNOSIS_USER),   0);
        assertEq(IERC20(Gnosis.WSTETH_ATOKEN).balanceOf(GNOSIS_USER), 0);
    }

    // Standard deal does not work for EURe and USDC.e on Gnosis; same whale-transfer patch
    // as the January 29, 2026 spell tests.
    function deal(address token, address to, uint256 amount) internal override {
        if (token == Gnosis.EURE || token == Gnosis.USDCE) {
            DealUtils.patchedDeal(token, to, amount);
            return;
        }
        super.deal(token, to, amount);
    }

    function test_GNOSIS_sparkLend_liquidateTop50BorrowersAndWindDown() external onChain(ChainIdUtils.Gnosis()) {
        IPool pool = IPool(Gnosis.POOL);

        // Top 50 borrowers by outstanding debt, from the 2026-09-02 enumeration.
        address[50] memory borrowers = [
            0x2002DbECC8E44386BcBfB96b50058C3cb08c49Bf,
            0x9b8eaBBCBE8D6b33037E85A515679D118039861e,
            0x13F7f63dD3586d855Ad621c74b9aF409c0EB24E6,
            0x59c7ACc0695B57E5BCC36B70c3D3fD0eDbCf8EB6,
            0x1Cc9c8213Bd62bE94b0E6FF7289b063d964c9E14,
            0xB2070e3C09AcE4466fFE821278D3b83Cbd3AbaB8,
            0x4B9bE88dda3c2acc98f64CB80250C7230a6Ac374,
            0xFfdA1eB4E3F85F72E872ec5FE4b59163C963CC8F,
            0x61622f25Bb01aA615Ee75e4DEF9fE74D58699BBb,
            0xB64ecd1B307DfC716A9Cb6Db9f004180Bae03BbB,
            0x0d8e5FBEA504308DA0017Fb10e53dd546d57e50D,
            0x3b40cAde0A3FbaBFb5287fCb38392B9CBCCe90c5,
            0x4fFAD6ac852c0Af0AA301376F4C5Dea3a928b120,
            0x7Cc672080e0f3a1e28C281d352fcE350fD20Dd86,
            0xDc95905331b1B04b89Bfa3144f5a2516Bc0779B5,
            0x1Ddbd5B3FbAF486ACb4d7Eb572f4a829C6D0125a,
            0x0C3cdfdC494e9952667aF5412F2b4bC4A1465f4D,
            0xe540Cb616dd8EF64fEF2ad5c25A6c470f2c5379D,
            0x8241cB5B0c83971E9d5FBf2efa10eCEfD9c8ea82,
            0x4949269deB8f1B7491ca4084cCe7E3C2567EC122,
            0x71eEAEB679B69D0773adB1923566c8390B10917a,
            0x87fC1313880d579039aC48dB8B25428ed5F33C4a,
            0xe21b177703854777Df37Dff5E74591749409AeDb,
            0x02FF537c4e2995d7ce0Be764fEa5B9fa5d782Cf5,
            0xd1236a6A111879d9862f8374BA15344b6B233Fbd,
            0xaC9c065B1A84A486628fd20efc9426E435bA7Cc2,
            0x82359081C428D0dc548202260B82ed4917669ecF,
            0x11B1785D9Ac81480c03210e89F1508c8c115888E,
            0x4EA667850e0B941513ce7EDA991E3fA05189D272,
            0x10316FDe3A7673675365310C2dC8eC8Ac9F8E3B7,
            0xe22F3d5D2C14dc68Be85356359600d74d7bD40DC,
            0xA4E878c857F02F8f1E6ADC23941BEb01D9C85E07,
            0x9AD7c53077a881cAa4f3A3fA52ae014150a6d7F0,
            0xeFc4904b786A3836343A3A504A2A3cb303b77D64,
            0x7B2e78D4dFaABA045A167a70dA285E30E8FcA196,
            0x9d8C50Af9e8908371502110e19299dD548FC5Ea3,
            0x84579a5DFf0316abadF3742095DEb0Dd021596c6,
            0x3eD3667Be3e93c9a43b739Eb6565a9Aaf965f7dd,
            0xcE114e96459F108E33B67d2E12E90C08B63E20fa,
            0xE217D2d3181B6F47379B8785E610E592E6F6d488,
            0x1b48F097Df01Be776A332048641C5906Ac1A5b3f,
            0x88EA8f941fb5067F9286ccfB7d89D112D846780C,
            0xad4abDD43De739504a74B4aE0d9796CC96fE77Ca,
            0x23e51402Ff300c8b70784fCEe0ccEa80968474E4,
            0xa50495fE7fF9Df4076c889DCF762627757D9c9E5,
            0x6C13FC8EF50144A21702415d57ece0A09879fCFb,
            0x203bE56725505eFa49B41887e3a8E1DC47bEDFcA,
            0xFC7E77729b45Fa649EA1C52E30457CF56dC8Bd8F,
            0xE7B2fFb33FF4faeE399D47d1475d43f3695Ee558,
            0x7cf72e72Abf9057FcE5F293e3767c80835414c13
        ];

        address[7] memory debtAssets = [
            Gnosis.WXDAI, Gnosis.USDC, Gnosis.USDCE, Gnosis.USDT, Gnosis.EURE, Gnosis.WETH, Gnosis.WSTETH
        ];

        address[5] memory collateralAssets  = [Gnosis.WSTETH, Gnosis.WETH, Gnosis.GNO, Gnosis.SXDAI, Gnosis.WXDAI];
        address[5] memory collateralATokens = [
            Gnosis.WSTETH_ATOKEN, Gnosis.WETH_ATOKEN, Gnosis.GNO_ATOKEN, Gnosis.SXDAI_ATOKEN, Gnosis.WXDAI_ATOKEN
        ];

        _logGnosisReserveState("before");

        // Treasury aToken positions, in scaled units so interest-index growth does not move
        // them; only mints (e.g. the liquidation protocol fee) or transfers can.
        uint256[5] memory treasuryScaledBefore;

        for (uint256 k; k < collateralATokens.length; ++k) {
            treasuryScaledBefore[k] = IAToken(collateralATokens[k]).scaledBalanceOf(Gnosis.TREASURY);
        }

        assertEq(treasuryScaledBefore[0], 0.318002618101735737e18);   // wstETH
        assertEq(treasuryScaledBefore[1], 0.274570016460437776e18);   // WETH
        assertEq(treasuryScaledBefore[2], 20.793881412583207088e18);  // GNO
        assertEq(treasuryScaledBefore[3], 60.672136466725031742e18);  // sDAI
        assertEq(treasuryScaledBefore[4], 0.656375716919909690e18);   // WXDAI

        _executeAllPayloadsAndBridges();

        // Fund the liquidator with roughly twice each debt asset's total across the fifty
        // positions.
        address liquidator = makeAddr("liquidator");

        deal(Gnosis.WXDAI,  liquidator, 10_000e18);
        deal(Gnosis.USDC,   liquidator, 20_000e6);
        deal(Gnosis.USDCE,  liquidator, 50_000e6);
        deal(Gnosis.USDT,   liquidator, 60_000e6);
        deal(Gnosis.EURE,   liquidator, 10_000e18);
        deal(Gnosis.WETH,   liquidator, 50e18);
        deal(Gnosis.WSTETH, liquidator, 1e18);

        vm.startPrank(liquidator);

        for (uint256 j; j < debtAssets.length; ++j) {
            IERC20(debtAssets[j]).approve(address(pool), type(uint256).max);
        }

        for (uint256 i; i < borrowers.length; ++i) {
            for (uint256 j; j < debtAssets.length; ++j) {
                address variableDebtToken = pool.getReserveData(debtAssets[j]).variableDebtTokenAddress;

                for (uint256 k; k < collateralAssets.length; ++k) {
                    if (IERC20(variableDebtToken).balanceOf(borrowers[i]) == 0) break;

                    // Clearing a large debt leg can lift the health factor back above one:
                    // at the 0.01% threshold that means collateral >= 10,000x the residual
                    // debt, and such dust legs are legitimately no longer liquidatable.
                    ( , , , , , uint256 healthFactor ) = pool.getUserAccountData(borrowers[i]);

                    if (healthFactor >= 1e18) break;

                    // Skip empty or rounding-dust collateral (all five are 18-decimal).
                    if (IERC20(collateralATokens[k]).balanceOf(borrowers[i]) < 1e9) continue;

                    pool.liquidationCall(collateralAssets[k], debtAssets[j], borrowers[i], type(uint256).max, false);
                }
            }
        }

        vm.stopPrank();

        _logGnosisReserveState("after");

        // Every one of the fifty positions is either fully cleared or healthy again (the
        // residual debt is so small relative to collateral that the position is no longer
        // liquidatable).
        for (uint256 i; i < borrowers.length; ++i) {
            ( , uint256 totalDebtBase, , , , uint256 healthFactor ) = pool.getUserAccountData(borrowers[i]);

            if (totalDebtBase != 0) {
                assertGe(healthFactor, 1e18);
                continue;
            }

            assertEq(totalDebtBase, 0);
        }

        // The liquidation protocol fee is zero, so the fifty liquidations mint nothing to
        // the treasury.
        for (uint256 k; k < collateralATokens.length; ++k) {
            assertEq(IAToken(collateralATokens[k]).scaledBalanceOf(Gnosis.TREASURY), treasuryScaledBefore[k]);
        }

        // getReservesList() returns the underlying assets; resolve each reserve's aToken.
        address[] memory assets  = pool.getReservesList();
        address[] memory aTokens = new address[](assets.length);

        for (uint256 i; i < assets.length; i++) {
            aTokens[i] = pool.getReserveData(assets[i]).aTokenAddress;
        }

        // Permissionless: converts every reserve's accruedToTreasury into aTokens held by
        // the treasury (collector).
        pool.mintToTreasury(assets);

        _logGnosisReserveState("after mintToTreasury");

        address withdrawer = makeAddr("withdrawer");

        // Move the treasury's aTokens to the withdrawer. The executor owns the treasury
        // controller, which is the collector's funds admin — this is the call a subsequent
        // spell payload would make.
        vm.startPrank(Gnosis.AMB_EXECUTOR);
        for (uint256 i; i < aTokens.length; i++) {
            uint256 treasuryBalanceBefore   = IERC20(aTokens[i]).balanceOf(Gnosis.TREASURY);
            uint256 withdrawerBalanceBefore = IERC20(aTokens[i]).balanceOf(withdrawer);

            assertEq(withdrawerBalanceBefore, 0);

            ITreasuryControllerLike(Gnosis.TREASURY_CONTROLLER).transfer({
                collector: Gnosis.TREASURY,
                token:     aTokens[i],
                recipient: withdrawer,
                amount:    treasuryBalanceBefore
            });

            uint256 treasuryBalanceAfter   = IERC20(aTokens[i]).balanceOf(Gnosis.TREASURY);
            uint256 withdrawerBalanceAfter = IERC20(aTokens[i]).balanceOf(withdrawer);

            assertEq(treasuryBalanceAfter,   0);
            assertEq(withdrawerBalanceAfter, withdrawerBalanceBefore + treasuryBalanceBefore);

            console2.log("transferred", IERC20Metadata(assets[i]).symbol(), treasuryBalanceBefore);
        }
        vm.stopPrank();

        // Redeem the aTokens for underlying; with all fifty borrowers liquidated, reserve
        // cash covers the full treasury claim in every reserve.
        vm.startPrank(withdrawer);
        for (uint256 i; i < aTokens.length; i++) {
            uint256 aTokenBalanceBefore     = IERC20(aTokens[i]).balanceOf(withdrawer);
            uint256 underlyingBalanceBefore = IERC20(assets[i]).balanceOf(withdrawer);

            console2.log("redeeming", IERC20Metadata(assets[i]).symbol(), IERC20(aTokens[i]).balanceOf(withdrawer));
            pool.withdraw(assets[i], type(uint256).max, withdrawer);

            uint256 aTokenBalanceAfter     = IERC20(aTokens[i]).balanceOf(withdrawer);
            uint256 underlyingBalanceAfter = IERC20(assets[i]).balanceOf(withdrawer);

            assertEq(aTokenBalanceAfter,    0);
            assertEq(underlyingBalanceAfter, underlyingBalanceBefore + aTokenBalanceBefore);
        }
        vm.stopPrank();

        _logGnosisReserveState("after redeem");
    }

    function _logGnosisReserveState(string memory label) internal view {
        IPool pool = IPool(Gnosis.POOL);

        address[] memory reserves = pool.getReservesList();

        console2.log("--- Gnosis protocol state:", label, "---");

        for (uint256 i; i < reserves.length; ++i) {
            DataTypes.ReserveData memory data = pool.getReserveData(reserves[i]);

            address underlying = IAToken(data.aTokenAddress).UNDERLYING_ASSET_ADDRESS();

            console2.log(IERC20Metadata(reserves[i]).symbol());
            console2.log("  reserve cash             :", IERC20(underlying).balanceOf(data.aTokenAddress));
            console2.log("  variable debt totalSupply:", IERC20(data.variableDebtTokenAddress).totalSupply());
            console2.log("  aToken totalSupply       :", IERC20(data.aTokenAddress).totalSupply());
            console2.log("  accruedToTreasury        :", data.accruedToTreasury);
            console2.log("  scaledBalanceOfTreasury  :", IAToken(data.aTokenAddress).scaledBalanceOf(Gnosis.TREASURY));
        }
    }

}

contract SparkEthereum_20260910_SpellTests is SpellTests {

    constructor() {
        _spellId   = 20260910;
        _blockDate = 1788318977;  // 2026-09-02T03:16:17Z
    }

    function setUp() public override {
        super.setUp();
    }

}
