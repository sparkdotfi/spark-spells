// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import { IERC20 }   from "forge-std/interfaces/IERC20.sol";
import { IERC4626 } from "forge-std/interfaces/IERC4626.sol";

import { ChainId } from 'src/libraries/ChainId.sol';

import { IAToken } from "lib/sparklend-v1-core/contracts/interfaces/IAToken.sol";

import { SparkEthereumTests } from "./SparkEthereumTests.sol";

import { console2 } from "forge-std/console2.sol";

import { Ethereum } from "spark-address-registry/Ethereum.sol";

import { CCTPForwarder } from "xchain-helpers/forwarders/CCTPForwarder.sol";

import { IRateLimits } from "spark-alm-controller/src/interfaces/IRateLimits.sol";
import { RateLimitHelpers } from "spark-alm-controller/src/RateLimitHelpers.sol";
import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";
import { ForeignController } from "spark-alm-controller/src/ForeignController.sol";
import { Base } from "spark-address-registry/Base.sol";

import { EnumerableSet } from "openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";

import { ChainIdUtils } from 'src/libraries/ChainId.sol';

import { VmSafe } from "forge-std/Vm.sol";

interface ICurvePoolLike {
    function coins(uint256) external view returns (address);
}

/// @dev convenience contract meant to be the single point of entry for all
/// spell-specifictest contracts
abstract contract SparkTestBase is SparkEthereumTests {

    using EnumerableSet for EnumerableSet.Bytes32Set;

    // TODO: Put in registry
    address public constant AAVE_CORE_AUSDT    = 0x23878914EFE38d27C4D67Ab83ed1b93A74D4086a;
    address public constant AAVE_ETH_LIDO_USDS = 0x09AA30b182488f769a9824F15E6Ce58591Da4781;
    address public constant AAVE_ETH_USDC      = 0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c;
    address public constant AAVE_ETH_USDS      = 0x32a6268f9Ba3642Dda7892aDd74f1D34469A4259;
    address public constant BUIDL_DEPOSIT      = 0xD1917664bE3FdAea377f6E8D5BF043ab5C3b1312;
    address public constant BUIDL_REDEEM       = 0x8780Dd016171B91E4Df47075dA0a947959C34200;
    address public constant CURVE_PYUSDUSDC    = 0x383E6b4437b59fff47B619CBA855CA29342A8559;
    address public constant MORPHO_TOKEN       = 0x58D97B57BB95320F9a05dC918Aef65434969c2B2;
    address public constant MORPHO_USDC_BC     = 0x56A76b428244a50513ec81e225a293d128fd581D;
    address public constant SPARK_MULTISIG     = 0x2E1b01adABB8D4981863394bEa23a1263CBaeDfC;
    address public constant USDE_ATOKEN        = 0x4F5923Fc5FD4a93352581b38B7cD26943012DECF;
    address public constant USDS_ATOKEN        = 0xC02aB1A5eaA8d1B114EF786D9bde108cD4364359;

    address internal constant NEW_ALM_CONTROLLER_ETHEREUM = 0x577Fa18a498e1775939b668B0224A5e5a1e56fc3;

    // TODO: Finish
    enum Category {
        ERC4626,
        ETHENA_USDE,
        ETHENA_SUSDE,
        AAVE,
        CCTP,
        CCTP_GENERAL,
        BUIDL,
        SUPERSTATE,
        CENTRIFUGE,
        MAPLE,
        TREASURY,
        CORE,
        PSM,
        CURVE_LP,
        CURVE_SWAP,
        SUPERSTATE_OFFCHAIN,
        SUPERSTATE_ONCHAIN,
        REWARDS_TRANSFER
    }

    struct SLLIntegration {
        string   label;
        Category category;
        address  integration;
        bytes32  entryId;
        bytes32  exitId;
    }

    SLLIntegration[] public arbitrumSllIntegrations;
    SLLIntegration[] public baseSllIntegrations;
    SLLIntegration[] public ethereumSllIntegrations;
    SLLIntegration[] public optimismSllIntegrations;
    SLLIntegration[] public unichainSllIntegrations;

    uint256 START_BLOCK = 21029247;

    EnumerableSet.Bytes32Set private _arbitrumRateLimitKeys;
    EnumerableSet.Bytes32Set private _baseRateLimitKeys;
    EnumerableSet.Bytes32Set private _ethereumRateLimitKeys;
    EnumerableSet.Bytes32Set private _optimismRateLimitKeys;
    EnumerableSet.Bytes32Set private _unichainRateLimitKeys;

    MainnetController public mainnetController = MainnetController(Ethereum.ALM_CONTROLLER);

    function test_test() public {
        populateRateLimitKeys();
        loadPreExecutionIntegrations();

        // // For each integration, check that all non-zero keys are present in the rate limit keys, and remove them from the set to ensure completeness
        // for (uint256 i = 0; i < ethereumSllIntegrations.length; ++i) {
        //     require(
        //         ethereumSllIntegrations[i].entryId != bytes32(0) ||
        //         ethereumSllIntegrations[i].exitId  != bytes32(0),
        //         "Empty integration"
        //     );

        //     assertTrue(_ethereumRateLimitKeys.contains(ethereumSllIntegrations[i].entryId) || ethereumSllIntegrations[i].entryId == bytes32(0));
        //     assertTrue(_ethereumRateLimitKeys.contains(ethereumSllIntegrations[i].exitId)  || ethereumSllIntegrations[i].exitId  == bytes32(0));

        //     _ethereumRateLimitKeys.remove(ethereumSllIntegrations[i].entryId);
        //     _ethereumRateLimitKeys.remove(ethereumSllIntegrations[i].exitId);
        // }

        // assertTrue(_ethereumRateLimitKeys.length() == 0, "Rate limit keys not fully covered");

        for (uint256 i = 0; i < ethereumSllIntegrations.length; ++i) {
            _runSLLE2ETests(ethereumSllIntegrations[i]);
        }

        executeAllPayloadsAndBridges();

        chainData[ChainIdUtils.Ethereum()].prevController = Ethereum.ALM_CONTROLLER;
        chainData[ChainIdUtils.Ethereum()].newController  = NEW_ALM_CONTROLLER_ETHEREUM;

        populateRateLimitKeys();

        for (uint256 i = 0; i < ethereumSllIntegrations.length; ++i) {
            _runSLLE2ETests(ethereumSllIntegrations[i]);
        }
    }

    function _runSLLE2ETests(SLLIntegration memory integration) internal {
        console2.log("Running SLL E2E test for", integration.label);

        if (integration.category == Category.AAVE) {
            uint256 decimals = IERC20(IAToken(integration.integration).UNDERLYING_ASSET_ADDRESS()).decimals();
            _testAaveIntegration(E2ETestParams({
                ctx:           _getSparkLiquidityLayerContext(),
                vault:         integration.integration,
                depositAmount: 10_000_000 * 10 ** decimals,
                depositKey:    integration.entryId,
                withdrawKey:   integration.exitId,
                tolerance:     10
            }));
        }

        else if (integration.category == Category.ERC4626) {
            uint256 decimals = IERC20(IERC4626(integration.integration).asset()).decimals();
            _testERC4626Integration(E2ETestParams({
                ctx:           _getSparkLiquidityLayerContext(),
                vault:         integration.integration,
                depositAmount: 10_000_000 * 10 ** decimals,
                depositKey:    integration.entryId,
                withdrawKey:   integration.exitId,
                tolerance:     10
            }));
        }

        else if (integration.category == Category.CCTP_GENERAL) {
            // Must be set
            assertGt(IRateLimits(_getSparkLiquidityLayerContext().rateLimits).getCurrentRateLimit(integration.entryId), 0);
        }

        else if (integration.category == Category.CURVE_LP) {
            address asset0 = ICurvePoolLike(integration.integration).coins(0);
            address asset1 = ICurvePoolLike(integration.integration).coins(1);

            _testCurveLPIntegration(CurveLPE2ETestParams({
                ctx:            _getSparkLiquidityLayerContext(),
                pool:           integration.integration,
                asset0:         asset0,
                asset1:         asset1,
                depositAmount:  1_000_000e18,  // Amount across both assets
                depositKey:     integration.entryId,
                withdrawKey:    integration.exitId,
                tolerance:      10
            }));
        }

        else if (integration.category == Category.CURVE_SWAP) {
            address asset0 = ICurvePoolLike(integration.integration).coins(0);
            address asset1 = ICurvePoolLike(integration.integration).coins(1);

            _testCurveSwapIntegration(CurveSwapE2ETestParams({
                ctx:            _getSparkLiquidityLayerContext(),
                pool:           integration.integration,
                asset0:         asset0,
                asset1:         asset1,
                swapAmount:     1_000_000e18,  // Normalized to 18 decimals
                swapKey:        integration.entryId
            }));
        }

        else if (integration.category == Category.CCTP) {
            // TODO: Figure out domainId mismatch
            // ChainId domainId;

            // if      (integration.integration == address(uint160(CCTPForwarder.DOMAIN_ID_CIRCLE_ARBITRUM_ONE))) domainId = ChainIdUtils.ArbitrumOne();
            // else if (integration.integration == address(uint160(CCTPForwarder.DOMAIN_ID_CIRCLE_BASE)))         domainId = ChainIdUtils.Base();
            // else if (integration.integration == address(uint160(CCTPForwarder.DOMAIN_ID_CIRCLE_OPTIMISM)))     domainId = ChainIdUtils.Optimism();
            // else if (integration.integration == address(uint160(CCTPForwarder.DOMAIN_ID_CIRCLE_UNICHAIN)))     domainId = ChainIdUtils.Unichain();
            // else revert("Invalid domain ID");

            // _testE2ESLLCrossChainForDomain(
            //     domainId,
            //     MainnetController(_getSparkLiquidityLayerContext(ChainIdUtils.Ethereum()).prevController),
            //     ForeignController(_getSparkLiquidityLayerContext(domainId).prevController)
            // );
        }
    }

    function populateRateLimitKeys() public returns (bytes32[] memory uniqueKeys) {
        bytes32[] memory topics = new bytes32[](1);
        topics[0] = IRateLimits.RateLimitDataSet.selector;

        VmSafe.EthGetLogs[] memory allLogs = vm.eth_getLogs(
            START_BLOCK,
            block.number,
            Ethereum.ALM_RATE_LIMITS,
            topics
        );

        // Collect unique keys from topics[1] (`key`)
        for (uint256 i = 0; i < allLogs.length; i++) {
            if (allLogs[i].topics.length > 1) {
                ( uint256 maxAmount,,, )
                    = abi.decode(allLogs[i].data, (uint256,uint256,uint256,uint256));
                if (maxAmount == 0) continue;
                _ethereumRateLimitKeys.add(allLogs[i].topics[1]);
            }
        }

        // Copy to memory (OZ returns a memory array view of the storage vector)
        uniqueKeys = _ethereumRateLimitKeys.values();

        console2.log("Rate limit keys", _ethereumRateLimitKeys.length());
    }

    function loadPreExecutionIntegrations() internal {
        ethereumSllIntegrations.push(_createSLLIntegration("AAVE-CORE_AUSDT",    Category.AAVE, AAVE_CORE_AUSDT));
        ethereumSllIntegrations.push(_createSLLIntegration("AAVE-DAI_SPTOKEN",   Category.AAVE, Ethereum.DAI_SPTOKEN));
        ethereumSllIntegrations.push(_createSLLIntegration("AAVE-ETH_LIDO_USDS", Category.AAVE, AAVE_ETH_LIDO_USDS));
        ethereumSllIntegrations.push(_createSLLIntegration("AAVE-ETH_USDC",      Category.AAVE, AAVE_ETH_USDC));
        ethereumSllIntegrations.push(_createSLLIntegration("AAVE-ETH_USDS",      Category.AAVE, AAVE_ETH_USDS));
        ethereumSllIntegrations.push(_createSLLIntegration("AAVE-PYUSD_SPTOKEN", Category.AAVE, Ethereum.PYUSD_SPTOKEN));
        ethereumSllIntegrations.push(_createSLLIntegration("AAVE-USDC_SPTOKEN",  Category.AAVE, Ethereum.USDC_SPTOKEN)); // SparkLend
        ethereumSllIntegrations.push(_createSLLIntegration("AAVE-USDE_ATOKEN",   Category.AAVE, USDE_ATOKEN));
        ethereumSllIntegrations.push(_createSLLIntegration("AAVE-USDS_SPTOKEN",  Category.AAVE, Ethereum.USDS_SPTOKEN));
        ethereumSllIntegrations.push(_createSLLIntegration("AAVE-USDT_SPTOKEN",  Category.AAVE, Ethereum.USDT_SPTOKEN));

        ethereumSllIntegrations.push(_createSLLIntegration("BUIDL-USDC", Category.BUIDL, Ethereum.USDC, Ethereum.BUIDLI, BUIDL_DEPOSIT, BUIDL_REDEEM));

        ethereumSllIntegrations.push(_createSLLIntegration("CCTP_GENERAL", Category.CCTP_GENERAL, Ethereum.USDC));

        ethereumSllIntegrations.push(_createSLLIntegration("CCTP-ARBITRUM_ONE", Category.CCTP, CCTPForwarder.DOMAIN_ID_CIRCLE_ARBITRUM_ONE));
        ethereumSllIntegrations.push(_createSLLIntegration("CCTP-BASE",         Category.CCTP, CCTPForwarder.DOMAIN_ID_CIRCLE_BASE));
        ethereumSllIntegrations.push(_createSLLIntegration("CCTP-OPTIMISM",     Category.CCTP, CCTPForwarder.DOMAIN_ID_CIRCLE_OPTIMISM));
        ethereumSllIntegrations.push(_createSLLIntegration("CCTP-UNICHAIN",     Category.CCTP, CCTPForwarder.DOMAIN_ID_CIRCLE_UNICHAIN));

        ethereumSllIntegrations.push(_createSLLIntegration("CENTRIFUGE-JTRSY_VAULT", Category.CENTRIFUGE, Ethereum.JTRSY_VAULT));

        ethereumSllIntegrations.push(_createSLLIntegration("CORE-USDS", Category.CORE, Ethereum.USDS));

        ethereumSllIntegrations.push(_createSLLIntegration("CURVE_LP-SUSDSUSDT", Category.CURVE_LP, Ethereum.CURVE_SUSDSUSDT));

        ethereumSllIntegrations.push(_createSLLIntegration("CURVE_SWAP-PYUSDUSDC", Category.CURVE_SWAP, CURVE_PYUSDUSDC));
        ethereumSllIntegrations.push(_createSLLIntegration("CURVE_SWAP-SUSDSUSDT", Category.CURVE_SWAP, Ethereum.CURVE_SUSDSUSDT));
        ethereumSllIntegrations.push(_createSLLIntegration("CURVE_SWAP-USDCUSDT",  Category.CURVE_SWAP, Ethereum.CURVE_USDCUSDT));


        ethereumSllIntegrations.push(_createSLLIntegration("ERC4626-MORPHO_USDC_BC",     Category.ERC4626, MORPHO_USDC_BC));
        ethereumSllIntegrations.push(_createSLLIntegration("ERC4626-MORPHO_VAULT_DAI_1", Category.ERC4626, Ethereum.MORPHO_VAULT_DAI_1));
        ethereumSllIntegrations.push(_createSLLIntegration("ERC4626-MORPHO_VAULT_USDS",  Category.ERC4626, Ethereum.MORPHO_VAULT_USDS));
        ethereumSllIntegrations.push(_createSLLIntegration("ERC4626-SUSDS",              Category.ERC4626, Ethereum.SUSDS));
        // ethereumSllIntegrations.push(_createSLLIntegration("ERC4626-SYRUP_USDC",         Category.ERC4626, Ethereum.SYRUP_USDC));   // TODO: Move to maple test
        // ethereumSllIntegrations.push(_createSLLIntegration("ERC4626-FLUID_SUSDS",        Category.ERC4626, Ethereum.FLUID_SUSDS));  // TODO: Fix FluidLiquidityError

        ethereumSllIntegrations.push(_createSLLIntegration("ETHENA_SUSDE-SUSDE", Category.ETHENA_SUSDE, Ethereum.SUSDE));
        ethereumSllIntegrations.push(_createSLLIntegration("ETHENA_USDE-USDE",   Category.ETHENA_USDE,  Ethereum.USDE));

        ethereumSllIntegrations.push(_createSLLIntegration("MAPLE-SYRUP_USDC", Category.MAPLE, Ethereum.SYRUP_USDC));

        ethereumSllIntegrations.push(_createSLLIntegration("PSM-USDS", Category.PSM, Ethereum.USDS));

        ethereumSllIntegrations.push(_createSLLIntegration("REWARDS_TRANSFER-MORPHO_TOKEN", Category.REWARDS_TRANSFER, MORPHO_TOKEN, address(0), SPARK_MULTISIG, address(0)));

        ethereumSllIntegrations.push(_createSLLIntegration("SUPERSTATE_OFFCHAIN-USTB", Category.SUPERSTATE_OFFCHAIN, address(0), Ethereum.USTB, address(0), Ethereum.USTB));

        ethereumSllIntegrations.push(_createSLLIntegration("SUPERSTATE_ONCHAIN-USTB", Category.SUPERSTATE_ONCHAIN,  Ethereum.USTB));
    }

    function _afterExecution() internal {
        // set all storage using beforeExecution
        // override to add more values, assert
    }

    function _createSLLIntegration(string memory label, Category category, address integration) internal view returns (SLLIntegration memory) {
        bytes32 entryId;
        bytes32 exitId;

        if (category == Category.ERC4626) {
            entryId = RateLimitHelpers.makeAssetKey(mainnetController.LIMIT_4626_DEPOSIT(),  integration);
            exitId  = RateLimitHelpers.makeAssetKey(mainnetController.LIMIT_4626_WITHDRAW(), integration);
        }
        else if (category == Category.ETHENA_USDE) {
            entryId = mainnetController.LIMIT_USDE_MINT();
            exitId  = mainnetController.LIMIT_USDE_BURN();
        }
        else if (category == Category.ETHENA_SUSDE) {
            entryId = RateLimitHelpers.makeAssetKey(mainnetController.LIMIT_4626_DEPOSIT(),  integration);
            exitId  = mainnetController.LIMIT_SUSDE_COOLDOWN();
        }
        else if (category == Category.AAVE) {
            entryId = RateLimitHelpers.makeAssetKey(mainnetController.LIMIT_AAVE_DEPOSIT(),  integration);
            exitId  = RateLimitHelpers.makeAssetKey(mainnetController.LIMIT_AAVE_WITHDRAW(), integration);
        }
        else if (category == Category.MAPLE) {
            entryId = bytes32(0);  // NOTE: Deposit/withdraw are covered by ERC4626 type (TODO: Make extraId?)
            exitId  = RateLimitHelpers.makeAssetKey(mainnetController.LIMIT_MAPLE_REDEEM(), integration);
        }
        else if (category == Category.CORE) {
            entryId = mainnetController.LIMIT_USDS_MINT();
            exitId  = bytes32(0);
        }
        else if (category == Category.CENTRIFUGE) {
            entryId = RateLimitHelpers.makeAssetKey(mainnetController.LIMIT_7540_DEPOSIT(), integration);
            exitId  = RateLimitHelpers.makeAssetKey(mainnetController.LIMIT_7540_REDEEM(),  integration);
        }
        else if (category == Category.PSM) {
            entryId = mainnetController.LIMIT_USDS_TO_USDC();
            exitId  = bytes32(0);
        }
        else if (category == Category.CURVE_LP) {
            entryId = RateLimitHelpers.makeAssetKey(mainnetController.LIMIT_CURVE_DEPOSIT(),  integration);
            exitId  = RateLimitHelpers.makeAssetKey(mainnetController.LIMIT_CURVE_WITHDRAW(), integration);
        }
        else if (category == Category.CURVE_SWAP) {
            entryId = RateLimitHelpers.makeAssetKey(mainnetController.LIMIT_CURVE_SWAP(), integration);
            exitId  = bytes32(0);
        }
        else if (category == Category.SUPERSTATE_ONCHAIN) {
            entryId = mainnetController.LIMIT_SUPERSTATE_SUBSCRIBE();
            exitId  = keccak256("LIMIT_SUPERSTATE_REDEEM");  // Have to use hash because this function was removed
        }
        else if (category == Category.CCTP_GENERAL) {
            entryId = mainnetController.LIMIT_USDC_TO_CCTP();
            exitId  = bytes32(0);
        }

        return SLLIntegration({
            label:       label,
            category:    category,
            integration: integration,
            entryId:     entryId,
            exitId:      exitId
        });
    }

    function _createSLLIntegration(string memory label, Category category, uint32 domain) internal view returns (SLLIntegration memory) {
        bytes32 entryId;
        bytes32 exitId;

        if (category == Category.CCTP) {
            entryId = RateLimitHelpers.makeDomainKey(mainnetController.LIMIT_USDC_TO_DOMAIN(), domain);
            exitId  = bytes32(0);
        }

        return SLLIntegration({
            label:       label,
            category:    category,
            integration: address(uint160(domain)),  // Unique ID
            entryId:     entryId,
            exitId:      exitId
        });
    }

    function _createSLLIntegration(
        string memory label,
        Category category,
        address  assetIn,
        address  assetOut,
        address  depositDestination,
        address  withdrawDestination
    )
        internal view returns (SLLIntegration memory)
    {
        bytes32 entryId;
        bytes32 exitId;

        if (category == Category.BUIDL) {
            entryId = RateLimitHelpers.makeAssetDestinationKey(mainnetController.LIMIT_ASSET_TRANSFER(), assetIn,  depositDestination);
            exitId  = RateLimitHelpers.makeAssetDestinationKey(mainnetController.LIMIT_ASSET_TRANSFER(), assetOut, withdrawDestination);
        }
        else if (category == Category.SUPERSTATE_OFFCHAIN) {
            entryId = bytes32(0);
            exitId  = RateLimitHelpers.makeAssetDestinationKey(mainnetController.LIMIT_ASSET_TRANSFER(), assetOut, withdrawDestination);
        }
        else if (category == Category.REWARDS_TRANSFER) {
            entryId = RateLimitHelpers.makeAssetDestinationKey(mainnetController.LIMIT_ASSET_TRANSFER(), assetIn, depositDestination);
            exitId  = bytes32(0);
        }

        return SLLIntegration({
            label:       label,
            category:    category,
            integration: assetIn,  // TODO: Refactor this for testing, integration + underlying?
            entryId:     entryId,
            exitId:      exitId
        });
    }
}
