// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { VmSafe } from "forge-std/Vm.sol";

import { IERC20, SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20Metadata }    from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { Arbitrum }  from "spark-address-registry/Arbitrum.sol";
import { Avalanche } from "spark-address-registry/Avalanche.sol";
import { Base }      from "spark-address-registry/Base.sol";
import { Ethereum }  from "spark-address-registry/Ethereum.sol";
import { Optimism }  from "spark-address-registry/Optimism.sol";
import { Unichain }  from "spark-address-registry/Unichain.sol";
import { SparkLend } from "spark-address-registry/SparkLend.sol";

import { ILayerZero, MessagingFee, SendParam } from "spark-alm-controller/src/interfaces/ILayerZero.sol";

import { ForeignController } from "spark-alm-controller/src/ForeignController.sol";
import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";
import { UniswapV4Lib }      from "spark-alm-controller/src/libraries/UniswapV4Lib.sol";

import { Currency } from "spark-alm-controller/lib/uniswap-v4-core/src/types/Currency.sol";
import { PoolKey }  from "spark-alm-controller/lib/uniswap-v4-core/src/types/PoolKey.sol";

import { ICapAutomator } from "sparklend-cap-automator/interfaces/ICapAutomator.sol";

import { IPool }               from "sparklend-v1-core/interfaces/IPool.sol";
import { IScaledBalanceToken } from "sparklend-v1-core/interfaces/IScaledBalanceToken.sol";

import { DataTypes }            from "sparklend-v1-core/protocol/libraries/types/DataTypes.sol";
import { ReserveConfiguration } from "sparklend-v1-core/protocol/libraries/configuration/ReserveConfiguration.sol";
import { WadRayMath }           from "sparklend-v1-core/protocol/libraries/math/WadRayMath.sol";

import { ChainIdUtils } from "src/libraries/ChainIdUtils.sol";

import { SparklendTests }                                from "src/test-harness/SparklendTests.sol";
import { SparkLiquidityLayerTests, ILZEndpointExtended } from "src/test-harness/SparkLiquidityLayerTests.sol";
import { SpellTests }                                    from "src/test-harness/SpellTests.sol";

import { IExecutor } from "spark-gov-relay/src/interfaces/IExecutor.sol";

import { OptionsBuilder } from "lib/xchain-helpers/lib/devtools/packages/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

import { Domain, DomainHelpers } from "xchain-helpers/testing/Domain.sol";
import { RecordedLogs }          from "xchain-helpers/testing/utils/RecordedLogs.sol";
import { OptimismBridgeTesting } from "xchain-helpers/testing/bridges/OptimismBridgeTesting.sol";

import { Bridge, BridgeType } from "xchain-helpers/testing/Bridge.sol";
import { LZBridgeTesting }    from "xchain-helpers/testing/bridges/LZBridgeTesting.sol";

import {
    IALMProxyFreezableLike,
    IMorphoVaultLike,
    IPositionManagerLike,
    ISparkVaultV2Like,
    IERC20Like
} from "../../interfaces/Interfaces.sol";

contract SparkEthereum_20260702_SLLTests is SparkLiquidityLayerTests {

    constructor() {
        _spellId   = 20260716;
        _blockDate = 1783235025;  // Jul-5-2026 7:03:45 AM +UTC
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Ethereum()].payload    = 0xcc7529473B850103524905D3914470898aDe8747;
    }

    function test_ETHEREUM_sll_deactivateOldMorphoUsdtVault() external onChain(ChainIdUtils.Ethereum()) {
        SparkLiquidityLayerContext memory ctx = _getSparkLiquidityLayerContext();

        MainnetController controller = MainnetController(ctx.controller);

        bytes32 depositKey  = RateLimitHelpers.makeAddressKey(controller.LIMIT_4626_DEPOSIT(),  Ethereum.MORPHO_VAULT_V2_USDT);
        bytes32 withdrawKey = RateLimitHelpers.makeAddressKey(controller.LIMIT_4626_WITHDRAW(), Ethereum.MORPHO_VAULT_V2_USDT);

        _assertRateLimit(depositKey,  100_000_000e6,     1_000_000_000e6 / uint256(1 days));
        _assertRateLimit(withdrawKey, type(uint256).max, 0);

        _executeAllPayloadsAndBridges();

        _assertRateLimit(depositKey,  0, 0);
        _assertRateLimit(withdrawKey, 0, 0);
    }

}

contract SparkEthereum_20260702_SparklendTests is SparklendTests {

    constructor() {
        _spellId   = 20260716;
        _blockDate = 1783235025;  // Jul-5-2026 7:03:45 AM +UTC
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Ethereum()].payload    = 0xcc7529473B850103524905D3914470898aDe8747;
    }

}

contract SparkEthereum_20260702_SpellTests is SpellTests {

    address internal constant ANCHORAGE_FEES_RECIPIENT = 0x2002020202020202020202020202020202020202;  // TODO: change
    address internal constant INCENTIVES_RECIPIENT     = 0x2002020202020202020202020202020202020202;  // TODO: change
    address internal constant PAXOS_USDG_DEPOSIT       = 0xf752cF318dfF2C01575c98741AA52e7a34d873Fd;
    address internal constant USDT_OFT                 = 0x6C96dE32CEa08842dcc4058c14d3aaAD7Fa41dee;
    address internal constant XLAYER_ALM_PROXY         = 0x0000000000000000000000000000000000000064;  // TODO: change

    uint256 internal constant ANCHORAGE_FEES_AMOUNT         = 500_000e18;
    uint256 internal constant ASSET_FOUNDATION_GRANT_AMOUNT = 155_000e18;
    uint256 internal constant FOUNDATION_GRANT_AMOUNT       = 1_100_000e18;
    uint256 internal constant INCENTIVES_AMOUNT             = 2_000_000e18;
    uint256 internal constant SPK_BUYBACKS_AMOUNT           = 64_231e18;

    constructor() {
        _spellId   = 20260716;
        _blockDate = 1783235025;  // Jul-5-2026 7:03:45 AM +UTC
    }

    function setUp() public override {
        super.setUp();

        // chainData[ChainIdUtils.Ethereum()].payload    = 0xcc7529473B850103524905D3914470898aDe8747;
    }

    function test_ETHEREUM_sparkTreasury_transfers() external onChain(ChainIdUtils.Ethereum()) {
        IERC20 usds = IERC20(Ethereum.USDS);

        uint256 sparkProxyBalanceBefore             = usds.balanceOf(Ethereum.SPARK_PROXY);
        uint256 foundationBalanceBefore             = usds.balanceOf(Ethereum.SPARK_FOUNDATION_MULTISIG);
        uint256 assetFoundationBalanceBefore        = usds.balanceOf(Ethereum.SPARK_ASSET_FOUNDATION_MULTISIG);
        uint256 almOpsBalanceBefore                 = usds.balanceOf(Ethereum.ALM_OPS_MULTISIG);
        uint256 incentivesRecipientBalanceBefore    = usds.balanceOf(INCENTIVES_RECIPIENT);
        uint256 anchorageFeesRecipientBalanceBefore = usds.balanceOf(ANCHORAGE_FEES_RECIPIENT);

        assertEq(sparkProxyBalanceBefore,             36_899_113.913977620254401020e18);
        assertEq(foundationBalanceBefore,             1_100_000.0095e18);
        assertEq(assetFoundationBalanceBefore,        167_000e18);
        assertEq(almOpsBalanceBefore,                 0);
        assertEq(incentivesRecipientBalanceBefore,    0);
        assertEq(anchorageFeesRecipientBalanceBefore, 0);

        _executeAllPayloadsAndBridges();

        assertEq(usds.balanceOf(Ethereum.SPARK_PROXY),                     sparkProxyBalanceBefore - FOUNDATION_GRANT_AMOUNT - ASSET_FOUNDATION_GRANT_AMOUNT - SPK_BUYBACKS_AMOUNT - INCENTIVES_AMOUNT - ANCHORAGE_FEES_AMOUNT);
        assertEq(usds.balanceOf(Ethereum.SPARK_FOUNDATION_MULTISIG),       foundationBalanceBefore + FOUNDATION_GRANT_AMOUNT);
        assertEq(usds.balanceOf(Ethereum.SPARK_ASSET_FOUNDATION_MULTISIG), assetFoundationBalanceBefore + ASSET_FOUNDATION_GRANT_AMOUNT);
        assertEq(usds.balanceOf(Ethereum.ALM_OPS_MULTISIG),                almOpsBalanceBefore + SPK_BUYBACKS_AMOUNT);
        assertEq(usds.balanceOf(INCENTIVES_RECIPIENT),                     incentivesRecipientBalanceBefore + INCENTIVES_AMOUNT);
        assertEq(usds.balanceOf(ANCHORAGE_FEES_RECIPIENT),                 anchorageFeesRecipientBalanceBefore + ANCHORAGE_FEES_AMOUNT);
    }

}
