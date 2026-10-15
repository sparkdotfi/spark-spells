// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { VmSafe } from "forge-std/Vm.sol";

import { IERC20 }         from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { IAccessControl } from "openzeppelin-contracts/contracts/access/IAccessControl.sol";

import { Arbitrum } from "spark-address-registry/Arbitrum.sol";
import { Ethereum } from "spark-address-registry/Ethereum.sol";

import { IALMProxy } from "spark-alm-controller/src/interfaces/IALMProxy.sol";

import { ChainIdUtils } from "src/libraries/ChainIdUtils.sol";

import { DomainHelpers } from "lib/xchain-helpers/src/testing/Domain.sol";
import { RecordedLogs }  from "lib/xchain-helpers/src/testing/utils/RecordedLogs.sol";

import { SparklendTests }           from "src/test-harness/SparklendTests.sol";
import { SparkLiquidityLayerTests } from "src/test-harness/SparkLiquidityLayerTests.sol";
import { SpellTests }               from "src/test-harness/SpellTests.sol";

contract SparkEthereum_20261022_SLLTests is SparkLiquidityLayerTests {

    using DomainHelpers for *;

    uint256 internal constant ARBITRUM_SUSDS_AMOUNT = 100_000_000e18;

    constructor() {
        _spellId   = 20261022;
        _blockDate = 1792049646;  // Oct-15-2026 07:34:06 AM UTC
    }

    function setUp() public override {
        super.setUp();
    }

    function test_ARBITRUM_sll_bridgeSusdsToArbitrum() external onChain(ChainIdUtils.ArbitrumOne()) {
        uint256 arbSusdsAlmProxyBalanceBefore = IERC20(Arbitrum.SUSDS).balanceOf(Arbitrum.ALM_PROXY);
        uint256 arbSusdsTotalSupplyBefore     = IERC20(Arbitrum.SUSDS).totalSupply();

        assertEq(arbSusdsAlmProxyBalanceBefore, 0.637040980963212345e18);
        assertEq(arbSusdsTotalSupplyBefore,     326_995_432.173787510251504877e18);

        chainData[ChainIdUtils.Ethereum()].domain.selectFork();

        IALMProxy almProxy = IALMProxy(Ethereum.ALM_PROXY);

        uint256 ethSusdsAlmProxyBalanceBefore = IERC20(Ethereum.SUSDS).balanceOf(Ethereum.ALM_PROXY);
        uint256 ethSusdsEscrowBalanceBefore   = IERC20(Ethereum.SUSDS).balanceOf(Ethereum.ARBITRUM_ESCROW);
        uint256 ethSusdsTotalSupplyBefore     = IERC20(Ethereum.SUSDS).totalSupply();

        assertEq(ethSusdsAlmProxyBalanceBefore, 936_233_716.796138913901679160e18);
        assertEq(ethSusdsEscrowBalanceBefore,   326_995_432.173787510251504877e18);
        assertEq(ethSusdsTotalSupplyBefore,     4_439_226_069.068350122865940504e18);

        assertEq(IERC20(Ethereum.SUSDS).balanceOf(Ethereum.SPARK_PROXY), 0);

        assertEq(IERC20(Ethereum.SUSDS).allowance(Ethereum.SPARK_PROXY, Ethereum.ARBITRUM_TOKEN_BRIDGE), 0);

        assertEq(IAccessControl(Ethereum.ALM_PROXY).hasRole(almProxy.CONTROLLER(), Ethereum.SPARK_PROXY), false);

        _executeAllPayloadsAndBridges();

        chainData[ChainIdUtils.ArbitrumOne()].domain.selectFork();

        // Arbitrum sUSDS is minted to the Arbitrum ALM Proxy once the retryable ticket redeems.
        assertEq(IERC20(Arbitrum.SUSDS).balanceOf(Arbitrum.ALM_PROXY), arbSusdsAlmProxyBalanceBefore + ARBITRUM_SUSDS_AMOUNT);
        assertEq(IERC20(Arbitrum.SUSDS).totalSupply(),                 arbSusdsTotalSupplyBefore     + ARBITRUM_SUSDS_AMOUNT);

        chainData[ChainIdUtils.Ethereum()].domain.selectFork();

        // Ethereum sUSDS leaves the ALM Proxy and is locked in the escrow, no sUSDS is minted.
        assertEq(IERC20(Ethereum.SUSDS).balanceOf(Ethereum.ALM_PROXY),       ethSusdsAlmProxyBalanceBefore - ARBITRUM_SUSDS_AMOUNT);
        assertEq(IERC20(Ethereum.SUSDS).balanceOf(Ethereum.ARBITRUM_ESCROW), ethSusdsEscrowBalanceBefore   + ARBITRUM_SUSDS_AMOUNT);
        assertEq(IERC20(Ethereum.SUSDS).totalSupply(),                       ethSusdsTotalSupplyBefore);

        assertEq(IERC20(Ethereum.SUSDS).balanceOf(Ethereum.SPARK_PROXY), 0);

        assertEq(IERC20(Ethereum.SUSDS).allowance(Ethereum.SPARK_PROXY, Ethereum.ARBITRUM_TOKEN_BRIDGE), 0);

        assertEq(IAccessControl(Ethereum.ALM_PROXY).hasRole(almProxy.CONTROLLER(), Ethereum.SPARK_PROXY), false);
    }

    function test_ARBITRUM_sll_bridgeSusdsToArbitrum_retryableTicketRefunds() external onChain(ChainIdUtils.ArbitrumOne()) {
        _executeAllPayloadsAndBridges();

        // The Inbox emits InboxMessageDelivered(uint256 indexed messageNum, bytes data) with the retryable ticket
        // fields packed as: to, l2CallValue, msg.value, maxSubmissionCost, excessFeeRefundAddress,
        // callValueRefundAddress, gasLimit, maxFeePerGas, data.length, data
        VmSafe.Log[] memory logs = RecordedLogs.getLogs();

        uint256 ticketCount;
        bytes memory ticket;
        for (uint256 i = 0; i < logs.length; ++i) {
            if (logs[i].emitter != Ethereum.ARBITRUM_INBOX) continue;
            if (logs[i].topics[0] != keccak256("InboxMessageDelivered(uint256,bytes)")) continue;
            ticketCount++;
            ticket = abi.decode(logs[i].data, (bytes));
        }

        assertEq(ticketCount, 1);

        (
            address to,
            uint256 l2CallValue,
            ,
            ,
            address excessFeeRefundAddress,
            ,
            uint256 gasLimit,
            uint256 maxFeePerGas,
        ) = abi.decode(ticket, (address, uint256, uint256, uint256, address, address, uint256, uint256, uint256));

        assertEq(to,           Arbitrum.TOKEN_BRIDGE);
        assertEq(l2CallValue,  0);
        assertEq(gasLimit,     1_000_000);
        assertEq(maxFeePerGas, 50e9);

        // Arbitrum.SPARK_EXECUTOR has no code on Ethereum, so the Inbox does not alias it and the excess gas
        // refund is credited to the Arbitrum Executor itself, which can spend it in an Arbitrum spell.
        chainData[ChainIdUtils.Ethereum()].domain.selectFork();

        assertEq(Arbitrum.SPARK_EXECUTOR.code.length, 0);

        assertEq(excessFeeRefundAddress, Arbitrum.SPARK_EXECUTOR);
    }

}

contract SparkEthereum_20261022_SparklendTests is SparklendTests {

    address internal constant OLD_WETH_IRM = 0xDFB6206FfC5BA5B48D2852370ee6A1bf6887476a;
    address internal constant NEW_WETH_IRM = 0xD5114e1E780f13eD82fB36440Dc4d381D7743C81;

    address internal constant OLD_PYUSD_IRM            = 0xDF7dedCfd522B1ee8da2c8526f642745800c8035;
    address internal constant OLD_RLUSD_USDG_IRM       = 0x473fDf9713C9a02A9a9c17173a57d120493F3C6B;
    address internal constant NEW_PYUSD_RLUSD_USDG_IRM = 0x5EB8926757E75D06d3014633FF1705Cab8dB0a17;

    constructor() {
        _spellId   = 20261022;
        _blockDate = 1792049646;  // Oct-15-2026 07:34:06 AM UTC
    }

    function setUp() public override {
        super.setUp();
    }

    function test_ETHEREUM_sparkLend_wethIrmUpdate() external onChain(ChainIdUtils.Ethereum()) {
        RateTargetKinkIRMParams memory oldParams = RateTargetKinkIRMParams({
            irm                      : OLD_WETH_IRM,
            baseRate                 : 0,
            variableRateSlope1Spread : -0.001e27,
            variableRateSlope2       : 0.75e27,
            optimalUsageRatio        : 0.90e27
        });
        RateTargetKinkIRMParams memory newParams = RateTargetKinkIRMParams({
            irm                      : NEW_WETH_IRM,
            baseRate                 : 0,
            variableRateSlope1Spread : -0.001e27,
            variableRateSlope2       : 0.30e27,
            optimalUsageRatio        : 0.90e27
        });
        _testRateTargetKinkIRMUpdate("WETH", oldParams, newParams);
    }

    function test_ETHEREUM_sparkLend_pyusdIrmUpdate() external onChain(ChainIdUtils.Ethereum()) {
        RateTargetBaseIRMParams memory oldParams = RateTargetBaseIRMParams({
            irm                : OLD_PYUSD_IRM,
            baseRateSpread     : 0,
            variableRateSlope1 : 0.02e27,
            variableRateSlope2 : 0.15e27,
            optimalUsageRatio  : 0.95e27
        });
        RateTargetBaseIRMParams memory newParams = RateTargetBaseIRMParams({
            irm                : NEW_PYUSD_RLUSD_USDG_IRM,
            baseRateSpread     : 0.002e27,
            variableRateSlope1 : 0.002e27,
            variableRateSlope2 : 0.15e27,
            optimalUsageRatio  : 0.80e27
        });
        _testRateTargetBaseIRMUpdate("PYUSD", oldParams, newParams);
    }

    function test_ETHEREUM_sparkLend_rlusdIrmUpdate() external onChain(ChainIdUtils.Ethereum()) {
        RateTargetBaseIRMParams memory oldParams = RateTargetBaseIRMParams({
            irm                : OLD_RLUSD_USDG_IRM,
            baseRateSpread     : 0,
            variableRateSlope1 : 0.003e27,
            variableRateSlope2 : 0.15e27,
            optimalUsageRatio  : 0.95e27
        });
        RateTargetBaseIRMParams memory newParams = RateTargetBaseIRMParams({
            irm                : NEW_PYUSD_RLUSD_USDG_IRM,
            baseRateSpread     : 0.002e27,
            variableRateSlope1 : 0.002e27,
            variableRateSlope2 : 0.15e27,
            optimalUsageRatio  : 0.80e27
        });
        _testRateTargetBaseIRMUpdate("RLUSD", oldParams, newParams);
    }

    function test_ETHEREUM_sparkLend_usdgIrmUpdate() external onChain(ChainIdUtils.Ethereum()) {
        RateTargetBaseIRMParams memory oldParams = RateTargetBaseIRMParams({
            irm                : OLD_RLUSD_USDG_IRM,
            baseRateSpread     : 0,
            variableRateSlope1 : 0.003e27,
            variableRateSlope2 : 0.15e27,
            optimalUsageRatio  : 0.95e27
        });
        RateTargetBaseIRMParams memory newParams = RateTargetBaseIRMParams({
            irm                : NEW_PYUSD_RLUSD_USDG_IRM,
            baseRateSpread     : 0.002e27,
            variableRateSlope1 : 0.002e27,
            variableRateSlope2 : 0.15e27,
            optimalUsageRatio  : 0.80e27
        });
        _testRateTargetBaseIRMUpdate("USDG", oldParams, newParams);
    }

}

contract SparkEthereum_20261022_SpellTests is SpellTests {

    uint256 internal constant SPARK_FOUNDATION_GRANT_AMOUNT       = 865_000e18;
    uint256 internal constant SPARK_ASSET_FOUNDATION_GRANT_AMOUNT = 45_000e18;

    uint256 internal constant USDS_SPK_BUYBACK_AMOUNT = 341_970e18;

    constructor() {
        _spellId   = 20261022;
        _blockDate = 1792049646;  // Oct-15-2026 07:34:06 AM UTC
    }

    function setUp() public override {
        super.setUp();
    }

    function test_ETHEREUM_sparkTreasury() external onChain(ChainIdUtils.Ethereum()) {
        IERC20 usds = IERC20(Ethereum.USDS);

        uint256 sparkProxyBalanceBefore      = usds.balanceOf(Ethereum.SPARK_PROXY);
        uint256 foundationBalanceBefore      = usds.balanceOf(Ethereum.SPARK_FOUNDATION_MULTISIG);
        uint256 assetFoundationBalanceBefore = usds.balanceOf(Ethereum.SPARK_ASSET_FOUNDATION_MULTISIG);
        uint256 almOpsBalanceBefore          = usds.balanceOf(Ethereum.ALM_OPS_MULTISIG);

        assertEq(sparkProxyBalanceBefore,      50_247_064.205806286854722044e18);
        assertEq(foundationBalanceBefore,      2_932_220.8122e18);
        assertEq(assetFoundationBalanceBefore, 200_000e18);
        assertEq(almOpsBalanceBefore,          648_323.342558330054342171e18);

        _executeAllPayloadsAndBridges();

        assertEq(usds.balanceOf(Ethereum.SPARK_PROXY),                     sparkProxyBalanceBefore - SPARK_FOUNDATION_GRANT_AMOUNT - SPARK_ASSET_FOUNDATION_GRANT_AMOUNT - USDS_SPK_BUYBACK_AMOUNT);
        assertEq(usds.balanceOf(Ethereum.SPARK_FOUNDATION_MULTISIG),       foundationBalanceBefore + SPARK_FOUNDATION_GRANT_AMOUNT);
        assertEq(usds.balanceOf(Ethereum.SPARK_ASSET_FOUNDATION_MULTISIG), assetFoundationBalanceBefore + SPARK_ASSET_FOUNDATION_GRANT_AMOUNT);
        assertEq(usds.balanceOf(Ethereum.ALM_OPS_MULTISIG),                almOpsBalanceBefore + USDS_SPK_BUYBACK_AMOUNT);
    }

}
