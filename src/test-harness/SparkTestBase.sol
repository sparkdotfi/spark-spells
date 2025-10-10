// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;

import { IERC20 }   from "forge-std/interfaces/IERC20.sol";
import { IERC4626 } from "forge-std/interfaces/IERC4626.sol";

import { console2 } from "forge-std/console2.sol";
import { VmSafe }   from "forge-std/Vm.sol";

import { IAToken } from "sparklend-v1-core/interfaces/IAToken.sol";

import { Base }     from "spark-address-registry/Base.sol"; // Keep as code using it is currently commented.
import { Ethereum } from "spark-address-registry/Ethereum.sol";

import { IRateLimits }       from "spark-alm-controller/src/interfaces/IRateLimits.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";
import { MainnetController } from "spark-alm-controller/src/MainnetController.sol";
import { ForeignController } from "spark-alm-controller/src/ForeignController.sol"; // Keep as code using it is currently commented.

import { CCTPForwarder } from "xchain-helpers/forwarders/CCTPForwarder.sol";

import { ChainIdUtils }                      from "../libraries/ChainId.sol"; // Keep as code using it is currently commented.
import { ICurvePoolLike, ISparkVaultV2Like } from "../interfaces/Interfaces.sol";
import { SparkEthereumTests }                from "./SparkEthereumTests.sol";

// TODO: MDL inherited by the specific `SparkEthereum_x.t.sol` proposal test contract.
/// @dev Convenience contract meant to be the single point of entry for all spell-specific test contracts.
abstract contract SparkTestBase is SparkEthereumTests {

    // TODO: Put in registry
    address internal constant AAVE_CORE_AUSDT    = 0x23878914EFE38d27C4D67Ab83ed1b93A74D4086a;
    address internal constant AAVE_ETH_LIDO_USDS = 0x09AA30b182488f769a9824F15E6Ce58591Da4781;
    address internal constant AAVE_ETH_USDC      = 0x98C23E9d8f34FEFb1B7BD6a91B7FF122F4e16F5c;
    address internal constant AAVE_ETH_USDS      = 0x32a6268f9Ba3642Dda7892aDd74f1D34469A4259;
    address internal constant BUIDL_DEPOSIT      = 0xD1917664bE3FdAea377f6E8D5BF043ab5C3b1312;
    address internal constant BUIDL_REDEEM       = 0x8780Dd016171B91E4Df47075dA0a947959C34200;
    address internal constant CURVE_PYUSDUSDC    = 0x383E6b4437b59fff47B619CBA855CA29342A8559;
    address internal constant CURVE_PYUSDUSDS    = 0xA632D59b9B804a956BfaA9b48Af3A1b74808FC1f;
    address internal constant MORPHO_TOKEN       = 0x58D97B57BB95320F9a05dC918Aef65434969c2B2;
    address internal constant MORPHO_USDC_BC     = 0x56A76b428244a50513ec81e225a293d128fd581D;
    address internal constant SPARK_MULTISIG     = 0x2E1b01adABB8D4981863394bEa23a1263CBaeDfC;
    address internal constant SYRUP              = 0x643C4E15d7d62Ad0aBeC4a9BD4b001aA3Ef52d66;
    address internal constant USDE_ATOKEN        = 0x4F5923Fc5FD4a93352581b38B7cD26943012DECF;
    address internal constant USDS_ATOKEN        = 0xC02aB1A5eaA8d1B114EF786D9bde108cD4364359;
    address internal constant USDS_SPK_FARM      = 0x173e314C7635B45322cd8Cb14f44b312e079F3af;
    address internal constant USCC_DEPOSIT       = 0xDB48AC0802F9A79145821A5430349cAff6d676f7;

    address internal constant NEW_ALM_CONTROLLER_ETHEREUM = 0x577Fa18a498e1775939b668B0224A5e5a1e56fc3;

    uint256 internal constant START_BLOCK = 21029247;

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
        SPARK_VAULT_V2,
        SUPERSTATE,
        SUPERSTATE_USCC,
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

    /**********************************************************************************************/
    /*** Tests                                                                                  ***/
    /**********************************************************************************************/

    function test_ETHEREUM_E2E_sparkLiquidityLayer() external {
        MainnetController mainnetController = MainnetController(_getSparkLiquidityLayerContext().controller);

        bytes32[]        memory rateLimitKeys = _getRateLimitKeys(false);
        SLLIntegration[] memory integrations  = _getPreExecutionIntegrations(mainnetController);

        _checkRateLimitKeys(integrations, rateLimitKeys);

        skip(2 days);  // Ensure rate limits are recharged

        for (uint256 i = 0; i < integrations.length; ++i) {
            _runSLLE2ETests(integrations[i]);
        }

        vm.recordLogs();  // Used for vm.getRecordedLogs() in populateRateLimitKeys() to get new keys

        // TODO: Change back to _executeAllPayloadsAndBridges() after dealing with multichain events
        _executeMainnetPayload();

        rateLimitKeys = _getRateLimitKeys(true);
        integrations  = _getPostExecutionIntegrations(integrations, mainnetController);

        console2.log("Rate limit keys", rateLimitKeys.length);
        console2.log("Integrations", integrations.length);

        _checkRateLimitKeys(integrations, rateLimitKeys);

        // for (uint256 i = 0; i < integrations.length; ++i) {
        //     _runSLLE2ETests(integrations[i]);
        // }
    }

    /**********************************************************************************************/
    /*** State-Modifying Functions                                                              ***/
    /**********************************************************************************************/

    // TODO: MDL, this function should be broken up into one function per test.
    function _runSLLE2ETests(SLLIntegration memory integration) internal {
        uint256 snapshot = vm.snapshot();

        if (integration.category == Category.AAVE) {
            console2.log("Running SLL E2E test for", integration.label);

            address asset    = IAToken(integration.integration).UNDERLYING_ASSET_ADDRESS();
            uint256 decimals = IERC20(asset).decimals();

            uint256 normalizedDepositAmount = asset == Ethereum.WETH ? 1_000 : 50_000_000;

            _testAaveIntegration(E2ETestParams({
                ctx:           _getSparkLiquidityLayerContext(),
                vault:         integration.integration,
                depositAmount: normalizedDepositAmount * 10 ** decimals,  // Lower to avoid supply cap issues (TODO: Fix)
                depositKey:    integration.entryId,
                withdrawKey:   integration.exitId,
                tolerance:     10
            }));
        }

        else if (integration.category == Category.ERC4626) {
            console2.log("Running SLL E2E test for", integration.label);

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
            console2.log("Skipping SLL E2E test for", integration.label, "[DEPRECATED] due to protocol upgrade");
        }

        else if (integration.category == Category.BUIDL) {
            console2.log("Running SLL E2E test for", integration.label);

            (
                address depositAsset,
                address depositDestination,
                address withdrawAsset,
                address withdrawDestination
            ) = abi.decode(integration.extraData, (address, address, address, address));

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
                transferAmount: 100_000 * 10 ** IERC20(asset).decimals()
            }));
        }

        else if (integration.category == Category.SUPERSTATE) {
            console2.log("Skipping SLL E2E test for", integration.label, "[DEPRECATED] due to protocol upgrade");

            // TODO: Replace - Get out of the loop
            vm.revertTo(snapshot);
            return;

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

        else if (integration.category == Category.SUPERSTATE_USCC) {
            console2.log("Running SLL E2E test for", integration.label);

            (
                address depositAsset,
                address depositDestination,
                address withdrawAsset,
                address withdrawDestination
            ) = abi.decode(integration.extraData, (address, address, address, address));

            _testSuperstateUsccIntegration(SuperstateUsccE2ETestParams({
                ctx:                 _getSparkLiquidityLayerContext(),
                depositAsset:        depositAsset,
                depositDestination:  depositDestination,
                depositAmount:       1_000_000e6,
                depositKey:          integration.entryId,
                withdrawAsset:       withdrawAsset,
                withdrawDestination: withdrawDestination,
                withdrawAmount:      1_000_000e6,
                withdrawKey:         integration.exitId
            }));
        }

        else if (integration.category == Category.SPARK_VAULT_V2) {
            console2.log("Running SLL E2E test for", integration.label);

            IERC20 asset = IERC20(ISparkVaultV2Like(integration.integration).asset());

            uint256 amount   = address(asset) == Ethereum.WETH ? 1_000 : 10_000_000;
            uint256 decimals = asset.decimals();

            _testSparkVaultV2Integration(SparkVaultV2E2ETestParams({
                ctx:             _getSparkLiquidityLayerContext(),
                vault:           integration.integration,
                takeKey:         integration.entryId,
                transferKey:     integration.exitId,
                takeAmount:      amount * 10 ** decimals,
                transferAmount:  amount * 10 ** decimals,
                userVaultAmount: amount * 10 ** decimals,
                tolerance:       10
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
    /*** Data populating helper functions                                                       ***/
    /**********************************************************************************************/

    function _getRateLimitKeys(bool isPostExecution) internal returns (bytes32[] memory rateLimitKeys) {
        bytes32[] memory topics = new bytes32[](1);
        topics[0] = IRateLimits.RateLimitDataSet.selector;

        VmSafe.EthGetLogs[] memory allLogs = vm.eth_getLogs(
            START_BLOCK,
            block.number,
            Ethereum.ALM_RATE_LIMITS,
            topics
        );

        rateLimitKeys = new bytes32[](0);

        // Collect unique keys from topics[1] (`key`)
        for (uint256 i = 0; i < allLogs.length; ++i) {
            if (allLogs[i].topics.length <= 1) continue;

            ( uint256 maxAmount, , , ) = abi.decode(allLogs[i].data, (uint256,uint256,uint256,uint256));

            // console2.log("Max amount", maxAmount);
            // // console2.log("Key", allLogs[i].topics[1]);
            // console2.log("Containing", _contains(rateLimitKeys, allLogs[i].topics[1]));
            // console2.log("i", i);

            // If the last event has a max amount of 0, remove the key and
            // consider the rate limit as offboarded
            rateLimitKeys = maxAmount == 0
                ? _removeIfContaining(rateLimitKeys, allLogs[i].topics[1])
                : _appendIfNotContaining(rateLimitKeys, allLogs[i].topics[1]);
        }

        // Collects all new logs from rate limits after spell is executed
        if (isPostExecution) {
            VmSafe.Log[] memory newLogs = vm.getRecordedLogs();

            for (uint256 i = 0; i < newLogs.length; ++i) {
                if (newLogs[i].topics[0] != IRateLimits.RateLimitDataSet.selector) continue;

                ( uint256 maxAmount, , , ) = abi.decode(newLogs[i].data, (uint256,uint256,uint256,uint256));

                // If the last event has a max amount of 0, remove the key and
                // consider the rate limit as offboarded
                rateLimitKeys = maxAmount == 0
                    ? _removeIfContaining(rateLimitKeys, allLogs[i].topics[1])
                    : _appendIfNotContaining(rateLimitKeys, allLogs[i].topics[1]);
            }
        }

        console2.log("Rate limit keys", rateLimitKeys.length);
    }

    function _getPreExecutionIntegrations(
        MainnetController mainnetController
    ) internal returns (SLLIntegration[] memory integrations) {
        integrations = new SLLIntegration[](40);

        integrations[0]  = _createSLLIntegration(mainnetController, "AAVE-CORE_AUSDT",    Category.AAVE, AAVE_CORE_AUSDT);
        integrations[1]  = _createSLLIntegration(mainnetController, "AAVE-DAI_SPTOKEN",   Category.AAVE, Ethereum.DAI_SPTOKEN);
        integrations[2]  = _createSLLIntegration(mainnetController, "AAVE-ETH_LIDO_USDS", Category.AAVE, AAVE_ETH_LIDO_USDS);
        integrations[3]  = _createSLLIntegration(mainnetController, "AAVE-ETH_USDC",      Category.AAVE, AAVE_ETH_USDC);
        integrations[4]  = _createSLLIntegration(mainnetController, "AAVE-ETH_USDS",      Category.AAVE, AAVE_ETH_USDS);
        integrations[5]  = _createSLLIntegration(mainnetController, "AAVE-PYUSD_SPTOKEN", Category.AAVE, Ethereum.PYUSD_SPTOKEN);
        integrations[6]  = _createSLLIntegration(mainnetController, "AAVE-SPETH",         Category.AAVE, Ethereum.WETH_SPTOKEN);
        integrations[7]  = _createSLLIntegration(mainnetController, "AAVE-USDC_SPTOKEN",  Category.AAVE, Ethereum.USDC_SPTOKEN); // SparkLend
        integrations[8]  = _createSLLIntegration(mainnetController, "AAVE-USDE_ATOKEN",   Category.AAVE, USDE_ATOKEN);
        integrations[9]  = _createSLLIntegration(mainnetController, "AAVE-USDS_SPTOKEN",  Category.AAVE, Ethereum.USDS_SPTOKEN);
        integrations[10] = _createSLLIntegration(mainnetController, "AAVE-USDT_SPTOKEN",  Category.AAVE, Ethereum.USDT_SPTOKEN);

        integrations[11] = _createSLLIntegration(mainnetController, "BUIDL-USDC", Category.BUIDL, Ethereum.USDC, Ethereum.BUIDLI, BUIDL_DEPOSIT, BUIDL_REDEEM);

        integrations[12] = _createSLLIntegration(mainnetController, "CCTP_GENERAL", Category.CCTP_GENERAL, Ethereum.USDC);

        integrations[13] = _createSLLIntegration(mainnetController, "CCTP-ARBITRUM_ONE", Category.CCTP, CCTPForwarder.DOMAIN_ID_CIRCLE_ARBITRUM_ONE);
        integrations[14] = _createSLLIntegration(mainnetController, "CCTP-BASE",         Category.CCTP, CCTPForwarder.DOMAIN_ID_CIRCLE_BASE);
        integrations[15] = _createSLLIntegration(mainnetController, "CCTP-OPTIMISM",     Category.CCTP, CCTPForwarder.DOMAIN_ID_CIRCLE_OPTIMISM);
        integrations[16] = _createSLLIntegration(mainnetController, "CCTP-UNICHAIN",     Category.CCTP, CCTPForwarder.DOMAIN_ID_CIRCLE_UNICHAIN);

        integrations[17] = _createSLLIntegration(mainnetController, "CENTRIFUGE-JTRSY_VAULT", Category.CENTRIFUGE, Ethereum.JTRSY_VAULT);

        integrations[18] = _createSLLIntegration(mainnetController, "CORE-USDS", Category.CORE, Ethereum.USDS);

        integrations[19] = _createSLLIntegration(mainnetController, "CURVE_LP-PYUSDUSDS", Category.CURVE_LP, Ethereum.CURVE_PYUSDUSDS);
        integrations[20] = _createSLLIntegration(mainnetController, "CURVE_LP-SUSDSUSDT", Category.CURVE_LP, Ethereum.CURVE_SUSDSUSDT);

        integrations[21] = _createSLLIntegration(mainnetController, "CURVE_SWAP-PYUSDUSDC", Category.CURVE_SWAP, Ethereum.CURVE_PYUSDUSDC);
        integrations[22] = _createSLLIntegration(mainnetController, "CURVE_SWAP-PYUSDUSDS", Category.CURVE_SWAP, Ethereum.CURVE_PYUSDUSDS);
        integrations[23] = _createSLLIntegration(mainnetController, "CURVE_SWAP-SUSDSUSDT", Category.CURVE_SWAP, Ethereum.CURVE_SUSDSUSDT);
        integrations[24] = _createSLLIntegration(mainnetController, "CURVE_SWAP-USDCUSDT",  Category.CURVE_SWAP, Ethereum.CURVE_USDCUSDT);

        integrations[25] = _createSLLIntegration(mainnetController, "ERC4626-MORPHO_USDC_BC",     Category.ERC4626, MORPHO_USDC_BC);
        integrations[26] = _createSLLIntegration(mainnetController, "ERC4626-MORPHO_VAULT_DAI_1", Category.ERC4626, Ethereum.MORPHO_VAULT_DAI_1);
        integrations[27] = _createSLLIntegration(mainnetController, "ERC4626-MORPHO_VAULT_USDS",  Category.ERC4626, Ethereum.MORPHO_VAULT_USDS);
        integrations[28] = _createSLLIntegration(mainnetController, "ERC4626-SUSDS",              Category.ERC4626, Ethereum.SUSDS);
        integrations[29] = _createSLLIntegration(mainnetController, "ERC4626-FLUID_SUSDS",        Category.ERC4626, Ethereum.FLUID_SUSDS);  // TODO: Fix FluidLiquidityError

        integrations[30] = _createSLLIntegration(mainnetController, "ETHENA-SUSDE", Category.ETHENA, Ethereum.SUSDE);

        integrations[31] = _createSLLIntegration(mainnetController, "FARM-USDS_SPK_FARM", Category.FARM, USDS_SPK_FARM);

        integrations[32] = _createSLLIntegration(mainnetController, "MAPLE-SYRUP_USDC", Category.MAPLE, Ethereum.SYRUP_USDC);

        integrations[33] = _createSLLIntegration(mainnetController, "PSM-USDS", Category.PSM, Ethereum.PSM);

        integrations[34] = _createSLLIntegration(mainnetController, "REWARDS_TRANSFER-MORPHO_TOKEN", Category.REWARDS_TRANSFER, MORPHO_TOKEN, address(0), SPARK_MULTISIG, address(0));
        integrations[35] = _createSLLIntegration(mainnetController, "REWARDS_TRANSFER-SYRUP",        Category.REWARDS_TRANSFER, SYRUP,        address(0), SPARK_MULTISIG, address(0));

        integrations[36] = _createSLLIntegration(mainnetController, "SPARK_VAULT_V2-SPETH",  Category.SPARK_VAULT_V2, Ethereum.SPARK_VAULT_V2_SPETH);
        integrations[37] = _createSLLIntegration(mainnetController, "SPARK_VAULT_V2-SPUSDC", Category.SPARK_VAULT_V2, Ethereum.SPARK_VAULT_V2_SPUSDC);
        integrations[38] = _createSLLIntegration(mainnetController, "SPARK_VAULT_V2-SPUSDT", Category.SPARK_VAULT_V2, Ethereum.SPARK_VAULT_V2_SPUSDT);

        integrations[39] = _createSLLIntegration(mainnetController, "SUPERSTATE-USTB", Category.SUPERSTATE, Ethereum.USDC, Ethereum.USTB, address(0), Ethereum.USTB);
    }

    function _getPostExecutionIntegrations(
        SLLIntegration[]  memory integrations,
        MainnetController        mainnetController
    ) internal returns (SLLIntegration[] memory newIntegrations) {
        newIntegrations = new SLLIntegration[](integrations.length - 2);

        for (uint256 i = 0; i < newIntegrations.length; ++i) {
            if (
                _isEqual(integrations[i].label, "BUIDL-USDC") ||
                _isEqual(integrations[i].label, "CENTRIFUGE-JTRSY_VAULT")
            ) continue;

            newIntegrations[i] = integrations[i];
        }

    }

    /**********************************************************************************************/
    /*** Data processing helper functions                                                       ***/
    /**********************************************************************************************/

    // TODO: MDL, revisit this if and when `_runSLLE2ETests` is refactored.
    function _createSLLIntegration(
        MainnetController        mainnetController,
        string            memory label,
        Category                 category,
        address                  integration
    ) internal returns (SLLIntegration memory) {
        bytes32 entryId  = bytes32(0);
        bytes32 entryId2 = bytes32(0);
        bytes32 exitId   = bytes32(0);
        bytes32 exitId2  = bytes32(0);

        if (category == Category.ERC4626) {
            entryId = RateLimitHelpers.makeAssetKey(mainnetController.LIMIT_4626_DEPOSIT(),  integration);
            exitId  = RateLimitHelpers.makeAssetKey(mainnetController.LIMIT_4626_WITHDRAW(), integration);
        } else if (category == Category.ETHENA) {
            entryId  = mainnetController.LIMIT_USDE_MINT();
            entryId2 = RateLimitHelpers.makeAssetKey(mainnetController.LIMIT_4626_DEPOSIT(), integration);
            exitId   = mainnetController.LIMIT_SUSDE_COOLDOWN();
            exitId2  = mainnetController.LIMIT_USDE_BURN();
        } else if (category == Category.FARM) {
            entryId = RateLimitHelpers.makeAssetKey(mainnetController.LIMIT_FARM_DEPOSIT(),  integration);
            exitId  = RateLimitHelpers.makeAssetKey(mainnetController.LIMIT_FARM_WITHDRAW(), integration);
        } else if (category == Category.AAVE) {
            entryId = RateLimitHelpers.makeAssetKey(mainnetController.LIMIT_AAVE_DEPOSIT(),  integration);
            exitId  = RateLimitHelpers.makeAssetKey(mainnetController.LIMIT_AAVE_WITHDRAW(), integration);
        } else if (category == Category.MAPLE) {
            entryId = RateLimitHelpers.makeAssetKey(mainnetController.LIMIT_4626_DEPOSIT(),  integration);
            exitId  = RateLimitHelpers.makeAssetKey(mainnetController.LIMIT_MAPLE_REDEEM(),  integration);
            exitId2 = RateLimitHelpers.makeAssetKey(mainnetController.LIMIT_4626_WITHDRAW(), integration);
        } else if (category == Category.CORE) {
            entryId = mainnetController.LIMIT_USDS_MINT();
        } else if (category == Category.CENTRIFUGE) {
            entryId = RateLimitHelpers.makeAssetKey(mainnetController.LIMIT_7540_DEPOSIT(), integration);
            exitId  = RateLimitHelpers.makeAssetKey(mainnetController.LIMIT_7540_REDEEM(),  integration);
        } else if (category == Category.PSM) {
            entryId = mainnetController.LIMIT_USDS_TO_USDC();
        } else if (category == Category.CURVE_LP) {
            entryId = RateLimitHelpers.makeAssetKey(mainnetController.LIMIT_CURVE_DEPOSIT(),  integration);
            exitId  = RateLimitHelpers.makeAssetKey(mainnetController.LIMIT_CURVE_WITHDRAW(), integration);
        } else if (category == Category.CURVE_SWAP) {
            entryId = RateLimitHelpers.makeAssetKey(mainnetController.LIMIT_CURVE_SWAP(), integration);
        } else if (category == Category.CCTP_GENERAL) {
            entryId = mainnetController.LIMIT_USDC_TO_CCTP();
        } else if (category == Category.SPARK_VAULT_V2) {
            entryId = RateLimitHelpers.makeAssetKey(mainnetController.LIMIT_SPARK_VAULT_TAKE(), integration);
            exitId  = RateLimitHelpers.makeAssetDestinationKey(mainnetController.LIMIT_ASSET_TRANSFER(), ISparkVaultV2Like(integration).asset(), integration);
        } else {
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

    // TODO: MDL, revisit this if and when `_runSLLE2ETests` is refactored.
    function _createSLLIntegration(
        MainnetController        mainnetController,
        string            memory label,
        Category                 category,
        uint32                   domain
    ) internal view returns (SLLIntegration memory) {
        bytes32 entryId = bytes32(0);

        if (category == Category.CCTP) {
            entryId = RateLimitHelpers.makeDomainKey(mainnetController.LIMIT_USDC_TO_DOMAIN(), domain);
        } else {
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

    // TODO: MDL, revisit this if and when `_runSLLE2ETests` is refactored.
    function _createSLLIntegration(
        MainnetController        mainnetController,
        string            memory label,
        Category                 category,
        address                  assetIn,
        address                  assetOut,
        address                  depositDestination,
        address                  withdrawDestination
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
        } else if (category == Category.SUPERSTATE) {
            entryId   = mainnetController.LIMIT_SUPERSTATE_SUBSCRIBE();
            exitId    = keccak256("LIMIT_SUPERSTATE_REDEEM");  // Have to use hash because this function was removed
            exitId2   = RateLimitHelpers.makeAssetDestinationKey(mainnetController.LIMIT_ASSET_TRANSFER(), assetOut, withdrawDestination);
            extraData = abi.encode(assetIn, assetOut, withdrawDestination);
        } else if (category == Category.SUPERSTATE_USCC) {
            entryId   = RateLimitHelpers.makeAssetDestinationKey(mainnetController.LIMIT_ASSET_TRANSFER(), assetIn,  depositDestination);
            exitId    = RateLimitHelpers.makeAssetDestinationKey(mainnetController.LIMIT_ASSET_TRANSFER(), assetOut, withdrawDestination);
            extraData = abi.encode(assetIn, depositDestination, assetOut, withdrawDestination);
        } else if (category == Category.REWARDS_TRANSFER) {
            entryId   = RateLimitHelpers.makeAssetDestinationKey(mainnetController.LIMIT_ASSET_TRANSFER(), assetIn, depositDestination);
            extraData = abi.encode(assetIn, depositDestination);
        } else {
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

    /**********************************************************************************************/
    /*** Other View/Pure Functions                                                               **/
    /**********************************************************************************************/

    function _checkRateLimitKeys(SLLIntegration[] memory integrations, bytes32[] memory rateLimitKeys) internal pure {
        for (uint256 i = 0; i < integrations.length; ++i) {
            console2.log("integrations[i].label", integrations[i].label);
            require(
                integrations[i].entryId  != bytes32(0) ||
                integrations[i].entryId2 != bytes32(0) ||
                integrations[i].exitId   != bytes32(0) ||
                integrations[i].exitId2  != bytes32(0),
                "Empty integration"
            );

            bool found;

            if (integrations[i].entryId != bytes32(0)) {
                rateLimitKeys = _remove(rateLimitKeys, integrations[i].entryId);
            }

            if (integrations[i].entryId2 != bytes32(0)) {
                rateLimitKeys = _remove(rateLimitKeys, integrations[i].entryId2);
            }

            if (integrations[i].exitId != bytes32(0)) {
                rateLimitKeys = _remove(rateLimitKeys, integrations[i].exitId);
            }

            if (integrations[i].exitId2 != bytes32(0)) {
                rateLimitKeys = _remove(rateLimitKeys, integrations[i].exitId2);
            }
        }

        assertTrue(rateLimitKeys.length == 0, "Rate limit keys not fully covered");
    }

    function _appendIfNotContaining(bytes32[] memory array, bytes32 value) internal pure returns (bytes32[] memory newArray) {
        if (_contains(array, value)) return array;

        newArray = new bytes32[](array.length + 1);

        for (uint256 i = 0; i < array.length; ++i) {
            newArray[i] = array[i];
        }

        newArray[array.length] = value;
    }

    function _contains(bytes32[] memory array, bytes32 value) internal pure returns (bool) {
        for (uint256 i = 0; i < array.length; ++i) {
            if (array[i] == value) return true;
        }

        return false;
    }

    function _removeAndReturnFound(bytes32[] memory array, bytes32 value) internal pure returns (bytes32[] memory newArray, bool found) {
        // Assume `array` was built using `_appendIfNotContaining`.
        newArray = new bytes32[](array.length - 1);

        uint256 writeIndex = 0;

        for (uint256 readIndex = 0; readIndex < array.length; ++readIndex) {
            if (array[readIndex] == value) continue;

            // If we are about to write past the end of the new array, it means we've never found the value,
            // so we can return the original array.
            if (writeIndex == newArray.length) return (array, false);

            newArray[writeIndex++] = array[readIndex];
        }

        return (newArray, true);
    }

    function _remove(bytes32[] memory array, bytes32 value) internal pure returns (bytes32[] memory newArray) {
        bool found;
        (newArray, found) = _removeAndReturnFound(array, value);
        assertTrue(found, "Value not found");
    }

    function _removeIfContaining(bytes32[] memory array, bytes32 value) internal pure returns (bytes32[] memory newArray) {
        ( newArray, ) = _removeAndReturnFound(array, value);
    }

}
