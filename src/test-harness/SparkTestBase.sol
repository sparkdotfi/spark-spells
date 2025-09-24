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

/// @dev Convenience contract meant to be the single point of entry for all
///      spell-specific test contracts
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
    address public constant CURVE_PYUSDUSDS    = 0xA632D59b9B804a956BfaA9b48Af3A1b74808FC1f;
    address public constant MORPHO_TOKEN       = 0x58D97B57BB95320F9a05dC918Aef65434969c2B2;
    address public constant MORPHO_USDC_BC     = 0x56A76b428244a50513ec81e225a293d128fd581D;
    address public constant SPARK_MULTISIG     = 0x2E1b01adABB8D4981863394bEa23a1263CBaeDfC;
    address public constant USDE_ATOKEN        = 0x4F5923Fc5FD4a93352581b38B7cD26943012DECF;
    address public constant USDS_ATOKEN        = 0xC02aB1A5eaA8d1B114EF786D9bde108cD4364359;
    address public constant USDS_SPK_FARM      = 0x173e314C7635B45322cd8Cb14f44b312e079F3af;

    address internal constant NEW_ALM_CONTROLLER_ETHEREUM = 0x577Fa18a498e1775939b668B0224A5e5a1e56fc3;

    enum Category {
        AAVE,
        BUIDL,
        CCTP_GENERAL,
        CCTP,
        CENTRIFUGE,
        CORE,
        CURVE_LP,
        CURVE_SWAP,
        ERC4626,
        ETHENA,
        FARM,
        MAPLE,
        PSM,
        REWARDS_TRANSFER,
        SUPERSTATE,
        TREASURY
    }

    struct SLLIntegration {
        string   label;
        Category category;
        address  integration;
        bytes32  entryId;
        bytes32  entryId2;
        bytes32  exitId;
        bytes32  exitId2;
        bytes    extraData;
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

    /**********************************************************************************************/
    /*** Tests                                                                                  ***/
    /**********************************************************************************************/

    function test_ETHEREUM_E2E_sparkLiquidityLayer() public {
        _populateRateLimitKeys(false);
        _loadPreExecutionIntegrations();

        _checkRateLimitKeys(ethereumSllIntegrations, _ethereumRateLimitKeys);

        // TODO: Find more robust way to do this, this is a hack to use the old controller in getSparkLiquidityLayerContext()
        delete chainData[ChainIdUtils.Ethereum()].prevController;
        delete chainData[ChainIdUtils.Base()].prevController;

        // _runSLLE2ETests(ethereumSllIntegrations[16]);

        skip(2 days);  // Ensure rate limits are recharged

        for (uint256 i = 0; i < ethereumSllIntegrations.length; ++i) {
            _runSLLE2ETests(ethereumSllIntegrations[i]);
        }

        vm.recordLogs();  // Used for vm.getRecordedLogs() in populateRateLimitKeys() to get new keys

        // TODO: Change back to executeAllPayloadsAndBridges() after dealing with multichain events
        executeMainnetPayload();

        // TODO: Find more robust way to do this, this is a hack to use the new controller in getSparkLiquidityLayerContext()
        chainData[ChainIdUtils.Ethereum()].prevController = Ethereum.ALM_CONTROLLER;
        chainData[ChainIdUtils.Base()].prevController     = Base.ALM_CONTROLLER;

        // Overwrite mainnetController with the new controller for the rest of the tests
        mainnetController = MainnetController(_getSparkLiquidityLayerContext().controller);

        _populateRateLimitKeys(true);
        _loadPostExecutionIntegrations();

        _checkRateLimitKeys(ethereumSllIntegrations, _ethereumRateLimitKeys);

        for (uint256 i = 0; i < ethereumSllIntegrations.length; ++i) {
            _runSLLE2ETests(ethereumSllIntegrations[i]);
        }
    }

    /**********************************************************************************************/
    /*** E2E test helper functions                                                              ***/
    /**********************************************************************************************/

    function _runSLLE2ETests(SLLIntegration memory integration) internal {
        uint256 snapshot = vm.snapshot();

        if (integration.category == Category.AAVE) {
            console2.log("Running SLL E2E test for", integration.label);

            uint256 decimals = IERC20(IAToken(integration.integration).UNDERLYING_ASSET_ADDRESS()).decimals();
            if (integration.integration == USDE_ATOKEN || integration.integration == Ethereum.USDT_SPTOKEN) return; // TODO: Hack to get around supply cap issues
            _testAaveIntegration(E2ETestParams({
                ctx:           _getSparkLiquidityLayerContext(),
                vault:         integration.integration,
                depositAmount: 1 * 10 ** decimals,  // Lower to avoid supply cap issues (TODO: Fix)
                depositKey:    integration.entryId,
                withdrawKey:   integration.exitId,
                tolerance:     10
            }));
        }

        else if (integration.category == Category.ERC4626) {
            console2.log("Running SLL E2E test for", integration.label);

            // TODO: Remove this, these integrations are broken
            if (integration.integration == Ethereum.FLUID_SUSDS) return;

            uint256 decimals = IERC20(IERC4626(integration.integration).asset()).decimals();
            _testERC4626Integration(E2ETestParams({
                ctx:           _getSparkLiquidityLayerContext(),
                vault:         integration.integration,
                depositAmount: 1 * 10 ** decimals,  // Lower to avoid supply cap issues  (TODO: Fix)
                depositKey:    integration.entryId,
                withdrawKey:   integration.exitId,
                tolerance:     10
            }));
        }

        else if (integration.category == Category.CCTP_GENERAL) {
            console2.log("Running SLL E2E test for", integration.label);

            // Must be set to infinite
            assertEq(IRateLimits(_getSparkLiquidityLayerContext().rateLimits).getCurrentRateLimit(integration.entryId), type(uint256).max);
        }

        else if (integration.category == Category.CURVE_LP) {
            console2.log("Running SLL E2E test for", integration.label);

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
            console2.log("Running SLL E2E test for", integration.label);

            address asset0 = ICurvePoolLike(integration.integration).coins(0);
            address asset1 = ICurvePoolLike(integration.integration).coins(1);

            _testCurveSwapIntegration(CurveSwapE2ETestParams({
                ctx:            _getSparkLiquidityLayerContext(),
                pool:           integration.integration,
                asset0:         asset0,
                asset1:         asset1,
                swapAmount:     1e18,  // Normalized to 18 decimals (TODO: Figure out how to raise, getting slippage reverts)
                swapKey:        integration.entryId
            }));
        }

        else if (integration.category == Category.MAPLE) {
            console2.log("Running SLL E2E test for", integration.label);

            _testMapleIntegration(MapleE2ETestParams({
                ctx:           _getSparkLiquidityLayerContext(),
                vault:         integration.integration,
                depositAmount: 1_000_000e6,
                depositKey:    integration.entryId,
                redeemKey:     integration.exitId,
                withdrawKey:   integration.exitId2,
                tolerance:     10
            }));
        }

        else if (integration.category == Category.PSM) {
            console2.log("Running SLL E2E test for", integration.label);

            _testPSMIntegration(PSMSwapE2ETestParams({
                ctx:        _getSparkLiquidityLayerContext(),
                psm:        integration.integration,
                swapAmount: 100_000_000e6,
                swapKey:    integration.entryId
            }));
        }

        else if (integration.category == Category.FARM) {
            console2.log("Running SLL E2E test for", integration.label);

            _testFarmIntegration(FarmE2ETestParams({
                ctx:           _getSparkLiquidityLayerContext(),
                farm:          integration.integration,
                depositAmount: 100_000_000e6,
                depositKey:    integration.entryId,
                withdrawKey:   integration.exitId
            }));
        }

        else if (integration.category == Category.ETHENA) {
            console2.log("Running SLL E2E test for", integration.label);

            _testEthenaIntegration(EthenaE2ETestParams({
                ctx:           _getSparkLiquidityLayerContext(),
                depositAmount: 1_000_000e6,
                mintKey:       integration.entryId,
                depositKey:    integration.entryId2,
                cooldownKey:   integration.exitId,
                burnKey:       integration.exitId2,
                tolerance:     10
            }));
        }

        else if (integration.category == Category.CORE) {
            console2.log("Running SLL E2E test for", integration.label);

            _testCoreIntegration(CoreE2ETestParams({
                ctx:        _getSparkLiquidityLayerContext(),
                mintAmount: 100_000_000e6,
                burnAmount: 50_000_000e6,
                mintKey:    integration.entryId
            }));
        }

        else if (integration.category == Category.CENTRIFUGE) {
            console2.log("Running SLL E2E test for", integration.label);

            _testCentrifugeIntegration(CentrifugeE2ETestParams({
                ctx:           _getSparkLiquidityLayerContext(),
                vault:         integration.integration,
                depositAmount: 100_000_000e6,
                depositKey:    integration.entryId,
                withdrawKey:   integration.exitId
            }));
        }

        else if (integration.category == Category.BUIDL) {
            console2.log("Running SLL E2E test for", integration.label);

            (
                address depositAsset,
                address depositDestination,
                address withdrawAsset,
                address withdrawDestination
            ) = abi.decode(integration.extraData, (address, address, address, address));

            // TODO: Figure out data structure
            _testBUIDLIntegration(BUIDLE2ETestParams({
                ctx:                 _getSparkLiquidityLayerContext(),
                depositAsset:        depositAsset,
                depositDestination:  depositDestination,
                depositAmount:       100_000_000e6,
                depositKey:          integration.entryId,
                withdrawAsset:       withdrawAsset,
                withdrawDestination: withdrawDestination,
                withdrawAmount:      100_000_000e6,
                withdrawKey:         integration.exitId
            }));
        }

        else if (integration.category == Category.REWARDS_TRANSFER) {
            console2.log("Running SLL E2E test for", integration.label);

            (
                address asset,
                address destination
            ) = abi.decode(integration.extraData, (address, address));

            _testTransferAssetIntegration(TransferAssetE2ETestParams({
                ctx:            _getSparkLiquidityLayerContext(),
                asset:          asset,
                destination:    destination,
                transferKey:    integration.entryId,
                transferAmount: 100_000_000e6
            }));
        }

        else if (integration.category == Category.SUPERSTATE) {
            console2.log("Running SLL E2E test for", integration.label);

            (
                address depositAsset,
                address withdrawAsset,
                address withdrawDestination
            ) = abi.decode(integration.extraData, (address, address, address));

            _testSuperstateIntegration(SuperstateE2ETestParams({
                ctx:                 _getSparkLiquidityLayerContext(),
                vault:               integration.integration,
                depositAsset:        depositAsset,
                depositAmount:       100_000_000e6,
                depositKey:          integration.entryId,
                withdrawAsset:       withdrawAsset,
                withdrawDestination: withdrawDestination,
                withdrawAmount:      100_000_000e6,
                withdrawKey:         integration.exitId
            }));
        }

        // else if (integration.category == Category.CCTP) {
        //     // console2.log("Running SLL E2E test for", integration.label);

        //     // TODO: Add back in once multichain is configured
        //     // ChainId domainId;

        //     // if      (integration.integration == address(uint160(CCTPForwarder.DOMAIN_ID_CIRCLE_ARBITRUM_ONE))) domainId = ChainIdUtils.ArbitrumOne();
        //     // else if (integration.integration == address(uint160(CCTPForwarder.DOMAIN_ID_CIRCLE_BASE)))         domainId = ChainIdUtils.Base();
        //     // else if (integration.integration == address(uint160(CCTPForwarder.DOMAIN_ID_CIRCLE_OPTIMISM)))     domainId = ChainIdUtils.Optimism();
        //     // else if (integration.integration == address(uint160(CCTPForwarder.DOMAIN_ID_CIRCLE_UNICHAIN)))     domainId = ChainIdUtils.Unichain();
        //     // else revert("Invalid domain ID");

        //     // _testE2ESLLCrossChainForDomain(
        //     //     domainId,
        //     //     MainnetController(_getSparkLiquidityLayerContext(ChainIdUtils.Ethereum()).controller),
        //     //     ForeignController(_getSparkLiquidityLayerContext(domainId).controller)
        //     // );
        // }

        else {
            console2.log("NOT running SLL E2E test for", integration.label);
        }

        vm.revertTo(snapshot);
    }

    /**********************************************************************************************/
    /*** Assertion helper functions                                                             ***/
    /**********************************************************************************************/

    function _checkRateLimitKeys(SLLIntegration[] memory integrations, EnumerableSet.Bytes32Set storage rateLimitKeys) internal {
        for (uint256 i = 0; i < integrations.length; ++i) {
            require(
                integrations[i].entryId  != bytes32(0) ||
                integrations[i].entryId2 != bytes32(0) ||
                integrations[i].exitId   != bytes32(0) ||
                integrations[i].exitId2  != bytes32(0),
                "Empty integration"
            );
        }

        for (uint256 i = 0; i < integrations.length; ++i) {
            assertTrue(rateLimitKeys.contains(integrations[i].entryId)  || integrations[i].entryId  == bytes32(0));
            assertTrue(rateLimitKeys.contains(integrations[i].entryId2) || integrations[i].entryId2 == bytes32(0));
            assertTrue(rateLimitKeys.contains(integrations[i].exitId)   || integrations[i].exitId   == bytes32(0));
            assertTrue(rateLimitKeys.contains(integrations[i].exitId2)  || integrations[i].exitId2  == bytes32(0));

            rateLimitKeys.remove(integrations[i].entryId);
            rateLimitKeys.remove(integrations[i].entryId2);
            rateLimitKeys.remove(integrations[i].exitId);
            rateLimitKeys.remove(integrations[i].exitId2);
        }

        assertTrue(rateLimitKeys.length() == 0, "Rate limit keys not fully covered");
    }

    /**********************************************************************************************/
    /*** Data populating helper functions                                                       ***/
    /**********************************************************************************************/

    function _populateRateLimitKeys(bool isPostExecution) internal returns (bytes32[] memory uniqueKeys) {
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

        // Collects all new logs from rate limits after spell is executed
        if (isPostExecution) {
            VmSafe.Log[] memory newLogs = vm.getRecordedLogs();
            for (uint256 i = 0; i < newLogs.length; i++) {
                if (newLogs[i].topics[0] == IRateLimits.RateLimitDataSet.selector) {
                    ( uint256 maxAmount,,, ) = abi.decode(newLogs[i].data, (uint256,uint256,uint256,uint256));
                    if (maxAmount == 0) continue;
                    _ethereumRateLimitKeys.add(newLogs[i].topics[1]);
                }
            }
        }

        // Copy to memory (OZ returns a memory array view of the storage vector)
        uniqueKeys = _ethereumRateLimitKeys.values();

        console2.log("Rate limit keys", _ethereumRateLimitKeys.length());
    }

    function _loadPreExecutionIntegrations() internal {
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
        ethereumSllIntegrations.push(_createSLLIntegration("ERC4626-FLUID_SUSDS",        Category.ERC4626, Ethereum.FLUID_SUSDS));  // TODO: Fix FluidLiquidityError

        ethereumSllIntegrations.push(_createSLLIntegration("ETHENA-SUSDE", Category.ETHENA, Ethereum.SUSDE));

        ethereumSllIntegrations.push(_createSLLIntegration("MAPLE-SYRUP_USDC", Category.MAPLE, Ethereum.SYRUP_USDC));

        ethereumSllIntegrations.push(_createSLLIntegration("PSM-USDS", Category.PSM, Ethereum.PSM));

        ethereumSllIntegrations.push(_createSLLIntegration("REWARDS_TRANSFER-MORPHO_TOKEN", Category.REWARDS_TRANSFER, MORPHO_TOKEN, address(0), SPARK_MULTISIG, address(0)));

        ethereumSllIntegrations.push(_createSLLIntegration("SUPERSTATE-USTB", Category.SUPERSTATE, Ethereum.USDC, Ethereum.USTB, address(0), Ethereum.USTB));
    }

    function _loadPostExecutionIntegrations() internal {
        ethereumSllIntegrations.push(_createSLLIntegration("FARM-USDS_SPK_FARM",   Category.FARM,       USDS_SPK_FARM));
        ethereumSllIntegrations.push(_createSLLIntegration("CURVE_SWAP-PYUSDUSDS", Category.CURVE_SWAP, CURVE_PYUSDUSDS));
        ethereumSllIntegrations.push(_createSLLIntegration("CURVE_LP-PYUSDUSDS",   Category.CURVE_LP,   CURVE_PYUSDUSDS));
    }

    /**********************************************************************************************/
    /*** Data processing helper functions                                                       ***/
    /**********************************************************************************************/

    function _createSLLIntegration(string memory label, Category category, address integration) internal returns (SLLIntegration memory) {
        bytes32 entryId  = bytes32(0);
        bytes32 entryId2 = bytes32(0);
        bytes32 exitId   = bytes32(0);
        bytes32 exitId2  = bytes32(0);

        mainnetController = MainnetController(_getSparkLiquidityLayerContext().controller);

        if (category == Category.ERC4626) {
            entryId = RateLimitHelpers.makeAssetKey(mainnetController.LIMIT_4626_DEPOSIT(),  integration);
            exitId  = RateLimitHelpers.makeAssetKey(mainnetController.LIMIT_4626_WITHDRAW(), integration);
        }
        else if (category == Category.ETHENA) {
            entryId  = mainnetController.LIMIT_USDE_MINT();
            entryId2 = RateLimitHelpers.makeAssetKey(mainnetController.LIMIT_4626_DEPOSIT(), integration);
            exitId   = mainnetController.LIMIT_SUSDE_COOLDOWN();
            exitId2  = mainnetController.LIMIT_USDE_BURN();
        }
        else if (category == Category.FARM) {
            entryId = RateLimitHelpers.makeAssetKey(mainnetController.LIMIT_FARM_DEPOSIT(),  integration);
            exitId  = RateLimitHelpers.makeAssetKey(mainnetController.LIMIT_FARM_WITHDRAW(), integration);
        }
        else if (category == Category.AAVE) {
            entryId = RateLimitHelpers.makeAssetKey(mainnetController.LIMIT_AAVE_DEPOSIT(),  integration);
            exitId  = RateLimitHelpers.makeAssetKey(mainnetController.LIMIT_AAVE_WITHDRAW(), integration);
        }
        else if (category == Category.MAPLE) {
            entryId = RateLimitHelpers.makeAssetKey(mainnetController.LIMIT_4626_DEPOSIT(),  integration);
            exitId  = RateLimitHelpers.makeAssetKey(mainnetController.LIMIT_MAPLE_REDEEM(),  integration);
            exitId2 = RateLimitHelpers.makeAssetKey(mainnetController.LIMIT_4626_WITHDRAW(), integration);
        }
        else if (category == Category.CORE) {
            entryId = mainnetController.LIMIT_USDS_MINT();
        }
        else if (category == Category.CENTRIFUGE) {
            entryId = RateLimitHelpers.makeAssetKey(mainnetController.LIMIT_7540_DEPOSIT(), integration);
            exitId  = RateLimitHelpers.makeAssetKey(mainnetController.LIMIT_7540_REDEEM(),  integration);
        }
        else if (category == Category.PSM) {
            entryId = mainnetController.LIMIT_USDS_TO_USDC();
        }
        else if (category == Category.CURVE_LP) {
            entryId = RateLimitHelpers.makeAssetKey(mainnetController.LIMIT_CURVE_DEPOSIT(),  integration);
            exitId  = RateLimitHelpers.makeAssetKey(mainnetController.LIMIT_CURVE_WITHDRAW(), integration);
        }
        else if (category == Category.CURVE_SWAP) {
            entryId = RateLimitHelpers.makeAssetKey(mainnetController.LIMIT_CURVE_SWAP(), integration);
        }
        else if (category == Category.CCTP_GENERAL) {
            entryId = mainnetController.LIMIT_USDC_TO_CCTP();
        }
        else {
            revert("Invalid category");
        }

        return SLLIntegration({
            label:       label,
            category:    category,
            integration: integration,
            entryId:     entryId,
            entryId2:    entryId2,
            exitId:      exitId,
            exitId2:     exitId2,
            extraData:   new bytes(0)
        });
    }

    function _createSLLIntegration(string memory label, Category category, uint32 domain) internal view returns (SLLIntegration memory) {
        bytes32 entryId = bytes32(0);

        if (category == Category.CCTP) {
            entryId = RateLimitHelpers.makeDomainKey(mainnetController.LIMIT_USDC_TO_DOMAIN(), domain);
        }
        else {
            revert("Invalid category");
        }

        return SLLIntegration({
            label:       label,
            category:    category,
            integration: address(uint160(domain)),  // Unique ID
            entryId:     entryId,
            entryId2:    bytes32(0),
            exitId:      bytes32(0),
            exitId2:     bytes32(0),
            extraData:   new bytes(0)
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
        bytes32 entryId  = bytes32(0);
        bytes32 entryId2 = bytes32(0);
        bytes32 exitId   = bytes32(0);
        bytes32 exitId2  = bytes32(0);

        bytes memory extraData = new bytes(0);

        if (category == Category.BUIDL) {
            entryId   = RateLimitHelpers.makeAssetDestinationKey(mainnetController.LIMIT_ASSET_TRANSFER(), assetIn,  depositDestination);
            exitId    = RateLimitHelpers.makeAssetDestinationKey(mainnetController.LIMIT_ASSET_TRANSFER(), assetOut, withdrawDestination);
            extraData = abi.encode(assetIn, depositDestination, assetOut, withdrawDestination);
        }
        else if (category == Category.SUPERSTATE) {
            entryId   = mainnetController.LIMIT_SUPERSTATE_SUBSCRIBE();
            exitId    = keccak256("LIMIT_SUPERSTATE_REDEEM");  // Have to use hash because this function was removed
            exitId2   = RateLimitHelpers.makeAssetDestinationKey(mainnetController.LIMIT_ASSET_TRANSFER(), assetOut, withdrawDestination);
            extraData = abi.encode(assetIn, assetOut, withdrawDestination);
        }
        else if (category == Category.REWARDS_TRANSFER) {
            entryId   = RateLimitHelpers.makeAssetDestinationKey(mainnetController.LIMIT_ASSET_TRANSFER(), assetIn, depositDestination);
            extraData = abi.encode(assetIn, depositDestination);
        }
        else {
            revert("Invalid category");
        }

        return SLLIntegration({
            label:       label,
            category:    category,
            integration: assetOut,  // Default to assetOut for transferAsset type integrations because this is the LP token
            entryId:     entryId,
            entryId2:    entryId2,
            exitId:      exitId,
            exitId2:     exitId2,
            extraData:   extraData
        });
    }

}
