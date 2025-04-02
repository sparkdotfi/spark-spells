// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import { Test }      from "forge-std/Test.sol";
import { StdChains } from "forge-std/StdChains.sol";
import { console }   from "forge-std/console.sol";

import { Address } from '../libraries/Address.sol';

import { IPoolAddressesProviderRegistry } from 'sparklend-v1-core/contracts/interfaces/IPoolAddressesProviderRegistry.sol';

import { Arbitrum } from 'spark-address-registry/Arbitrum.sol';
import { Base }     from 'spark-address-registry/Base.sol';
import { Ethereum } from 'spark-address-registry/Ethereum.sol';
import { Gnosis }   from 'spark-address-registry/Gnosis.sol';

import { IExecutor } from 'lib/spark-gov-relay/src/interfaces/IExecutor.sol';

import { Domain, DomainHelpers } from "xchain-helpers/testing/Domain.sol";
import { OptimismBridgeTesting } from "xchain-helpers/testing/bridges/OptimismBridgeTesting.sol";
import { AMBBridgeTesting }      from "xchain-helpers/testing/bridges/AMBBridgeTesting.sol";
import { ArbitrumBridgeTesting } from "xchain-helpers/testing/bridges/ArbitrumBridgeTesting.sol";
import { CCTPBridgeTesting }     from "xchain-helpers/testing/bridges/CCTPBridgeTesting.sol";
import { Bridge }                from "xchain-helpers/testing/Bridge.sol";
import { RecordedLogs }          from "xchain-helpers/testing/utils/RecordedLogs.sol";

import { ChainIdUtils, ChainId } from "../libraries/ChainId.sol";
import { SparkPayloadEthereum }  from "../SparkPayloadEthereum.sol";

abstract contract SpellRunner is Test {
    using DomainHelpers for Domain;
    using DomainHelpers for StdChains.Chain;

    enum BridgeType {
        OPTIMISM,
        CCTP,
        GNOSIS,
        ARBITRUM
    }

    struct ChainSpellMetadata {
      address                        payload;
      IExecutor                      executor;
      Domain                         domain;
      /// @notice on mainnet: empty
      /// on L2s: bridges that'll include txs in the L2. there can be multiple
      /// bridges for a given chain, such as canonical OP bridge and CCTP
      /// USDC-specific bridge
      Bridge[]                       bridges;
      BridgeType[]                   bridgeTypes;
      // @notice coupled to SparklendTests, zero on chains where sparklend is not present
      IPoolAddressesProviderRegistry sparklendPooAddressProviderRegistry;
    }

    mapping(ChainId chainId => ChainSpellMetadata chainSpellMetadata) internal chainSpellMetadata;

    ChainId[] internal allChains;
    string internal    id;

    modifier onChain(ChainId chainId) virtual {
        ChainId currentChain = ChainIdUtils.fromUint(block.chainid);
        chainSpellMetadata[chainId].domain.selectFork();
        _;
        chainSpellMetadata[currentChain].domain.selectFork();
    }

    /// @dev to be called in setUp
    function setupDomains(uint256 mainnetForkBlock, uint256 baseForkBlock, uint256 gnosisForkBlock, uint256 arbitrumOneForkBlock) internal {
        chainSpellMetadata[ChainIdUtils.Ethereum()].domain    = getChain("mainnet").createFork(mainnetForkBlock);
        chainSpellMetadata[ChainIdUtils.Base()].domain        = getChain("base").createFork(baseForkBlock);
        chainSpellMetadata[ChainIdUtils.Gnosis()].domain      = getChain("gnosis_chain").createFork(gnosisForkBlock);
        chainSpellMetadata[ChainIdUtils.ArbitrumOne()].domain = getChain("arbitrum_one").createFork(arbitrumOneForkBlock);

        chainSpellMetadata[ChainIdUtils.Ethereum()].executor    = IExecutor(Ethereum.SPARK_PROXY);
        chainSpellMetadata[ChainIdUtils.Base()].executor        = IExecutor(Base.SPARK_EXECUTOR);
        chainSpellMetadata[ChainIdUtils.Gnosis()].executor      = IExecutor(Gnosis.AMB_EXECUTOR);
        chainSpellMetadata[ChainIdUtils.ArbitrumOne()].executor = IExecutor(Arbitrum.SPARK_EXECUTOR);

        console.log("--- setupDomains");

        // Arbitrum One
        chainSpellMetadata[ChainIdUtils.ArbitrumOne()].bridges.push(
            ArbitrumBridgeTesting.createNativeBridge(
                chainSpellMetadata[ChainIdUtils.Ethereum()].domain,
                chainSpellMetadata[ChainIdUtils.ArbitrumOne()].domain
        ));
        chainSpellMetadata[ChainIdUtils.ArbitrumOne()].bridgeTypes.push(BridgeType.ARBITRUM);
        chainSpellMetadata[ChainIdUtils.ArbitrumOne()].bridges.push(
            CCTPBridgeTesting.createCircleBridge(
                chainSpellMetadata[ChainIdUtils.Ethereum()].domain,
                chainSpellMetadata[ChainIdUtils.ArbitrumOne()].domain
        ));
        chainSpellMetadata[ChainIdUtils.ArbitrumOne()].bridgeTypes.push(BridgeType.CCTP);

        // Base
        chainSpellMetadata[ChainIdUtils.Base()].bridges.push(
            OptimismBridgeTesting.createNativeBridge(
                chainSpellMetadata[ChainIdUtils.Ethereum()].domain,
                chainSpellMetadata[ChainIdUtils.Base()].domain
        ));
        chainSpellMetadata[ChainIdUtils.Base()].bridgeTypes.push(BridgeType.OPTIMISM);
        chainSpellMetadata[ChainIdUtils.Base()].bridges.push(
            CCTPBridgeTesting.createCircleBridge(
                chainSpellMetadata[ChainIdUtils.Ethereum()].domain,
                chainSpellMetadata[ChainIdUtils.Base()].domain
        ));
        chainSpellMetadata[ChainIdUtils.Base()].bridgeTypes.push(BridgeType.CCTP);

        // Gnosis
        chainSpellMetadata[ChainIdUtils.Gnosis()].bridges.push(
            AMBBridgeTesting.createGnosisBridge(
                chainSpellMetadata[ChainIdUtils.Ethereum()].domain,
                chainSpellMetadata[ChainIdUtils.Gnosis()].domain
        ));
        chainSpellMetadata[ChainIdUtils.Gnosis()].bridgeTypes.push(BridgeType.GNOSIS);

        chainSpellMetadata[ChainIdUtils.Ethereum()].sparklendPooAddressProviderRegistry = IPoolAddressesProviderRegistry(Ethereum.POOL_ADDRESSES_PROVIDER_REGISTRY);
        chainSpellMetadata[ChainIdUtils.Gnosis()].sparklendPooAddressProviderRegistry   = IPoolAddressesProviderRegistry(Gnosis.POOL_ADDRESSES_PROVIDER_REGISTRY);

        allChains.push(ChainIdUtils.Ethereum());
        allChains.push(ChainIdUtils.Base());
        allChains.push(ChainIdUtils.Gnosis());
        allChains.push(ChainIdUtils.ArbitrumOne());

        console.log("arb num bridges ", chainSpellMetadata[ChainIdUtils.ArbitrumOne()].bridges.length);
        console.log("base num bridges", chainSpellMetadata[ChainIdUtils.Base()].bridges.length);
    }

    function spellIdentifier(ChainId chainId) private view returns(string memory){
        string memory slug            = string(abi.encodePacked("Spark", chainId.toDomainString(), "_", id));
        string memory identifier = string(abi.encodePacked(slug, ".sol:", slug));
        return identifier;
    }

    function deployPayload(ChainId chainId) internal onChain(chainId) returns(address) {
        return deployCode(spellIdentifier(chainId));
    }

    function deployPayloads() internal {
        for (uint256 i = 0; i < allChains.length; i++) {
            ChainId chainId = ChainIdUtils.fromDomain(chainSpellMetadata[allChains[i]].domain);
            string memory identifier = spellIdentifier(chainId);
            try vm.getCode(identifier) {
                chainSpellMetadata[chainId].payload = deployPayload(chainId);
            } catch {
                console.log("skipping spell deployment for network: ", chainId.toDomainString());
            }
        }
    }

    /// @dev takes care to revert the selected fork to what was chosen before
    function executeAllPayloadsAndBridges() internal {
        // only execute mainnet payload
        executeMainnetPayload();
        // then use bridges to execute other chains' payloads
        _relayMessageOverBridges();
        // execute the foreign payloads (either by simulation or real execute)
        _executeForeignPayloads();
    }

    /// @dev bridge contracts themselves are stored on mainnet
    function _relayMessageOverBridges() internal onChain(ChainIdUtils.Ethereum()) {
        for (uint256 i = 0; i < allChains.length; i++) {
            ChainId chainId = ChainIdUtils.fromDomain(chainSpellMetadata[allChains[i]].domain);
            for (uint256 j = 0; j < chainSpellMetadata[chainId].bridges.length ; j++){
                _executeBridge(chainSpellMetadata[chainId].bridges[j], chainSpellMetadata[chainId].bridgeTypes[j]);
            }
        }
    }

    /// @dev this does not relay messages from L2s to mainnet except in the case of USDC
    function _executeBridge(Bridge storage bridge, BridgeType bridgeType) private {
        if (bridgeType == BridgeType.OPTIMISM) {
            OptimismBridgeTesting.relayMessagesToDestination(bridge, false);
        } else if (bridgeType == BridgeType.CCTP) {
            CCTPBridgeTesting.relayMessagesToDestination(bridge, false);
            CCTPBridgeTesting.relayMessagesToSource(bridge, false);
        } else if (bridgeType == BridgeType.GNOSIS) {
            AMBBridgeTesting.relayMessagesToDestination(bridge, false);
        } else if (bridgeType == BridgeType.ARBITRUM) {
            ArbitrumBridgeTesting.relayMessagesToDestination(bridge, false);
        }
    }

    function _executeForeignPayloads() private onChain(ChainIdUtils.Ethereum()) {
        for (uint256 i = 0; i < allChains.length; i++) {
            ChainId chainId = ChainIdUtils.fromDomain(chainSpellMetadata[allChains[i]].domain);
            if (chainId == ChainIdUtils.Ethereum()) continue;  // Don't execute mainnet
            address mainnetSpellPayload = _getForeignPayloadFromMainnetSpell(chainId);
            IExecutor executor = chainSpellMetadata[chainId].executor;
            if (mainnetSpellPayload != address(0)) {
                // We assume the payload has been queued in the executor (will revert otherwise)
                chainSpellMetadata[chainId].domain.selectFork();
                uint256 actionsSetId = executor.actionsSetCount() - 1;
                uint256 prevTimestamp = block.timestamp;
                vm.warp(executor.getActionsSetById(actionsSetId).executionTime);
                executor.execute(actionsSetId);
                vm.warp(prevTimestamp);
            } else {
                // We will simulate execution until the real spell is deployed in the mainnet spell
                address payload = chainSpellMetadata[chainId].payload;
                if (payload != address(0)) {
                    chainSpellMetadata[chainId].domain.selectFork();
                    vm.prank(address(executor));
                    executor.executeDelegateCall(
                        payload,
                        abi.encodeWithSignature('execute()')
                    );

                    console.log("simulating execution payload for network: ", chainId.toDomainString());
                }
            }

        }
    }

    function _getForeignPayloadFromMainnetSpell(ChainId chainId) internal onChain(ChainIdUtils.Ethereum()) returns (address) {
        SparkPayloadEthereum spell = SparkPayloadEthereum(chainSpellMetadata[ChainIdUtils.Ethereum()].payload);
        if (chainId == ChainIdUtils.Base()) {
            return spell.PAYLOAD_BASE();
        } else if (chainId == ChainIdUtils.Gnosis()) {
            return spell.PAYLOAD_GNOSIS();
        } else if (chainId == ChainIdUtils.ArbitrumOne()) {
            return spell.PAYLOAD_ARBITRUM();
        } else {
            revert("Unsupported chainId");
        }
    }

    function executeMainnetPayload() internal onChain(ChainIdUtils.Ethereum()){
        address payloadAddress = chainSpellMetadata[ChainIdUtils.Ethereum()].payload;
        IExecutor executor     = chainSpellMetadata[ChainIdUtils.Ethereum()].executor;
        require(Address.isContract(payloadAddress), "PAYLOAD IS NOT A CONTRACT");

        vm.prank(Ethereum.PAUSE_PROXY);
        (bool success,) = address(executor).call(abi.encodeWithSignature(
            'exec(address,bytes)',
            payloadAddress,
            abi.encodeWithSignature('execute()')
        ));
        require(success, "FAILED TO EXECUTE PAYLOAD");
    }

    function _clearLogs() internal {
        RecordedLogs.clearLogs();

        // Need to also reset all bridge indicies
        for (uint256 i = 0; i < allChains.length; i++) {
            ChainId chainId = ChainIdUtils.fromDomain(chainSpellMetadata[allChains[i]].domain);
            for (uint256 j = 0; j < chainSpellMetadata[chainId].bridges.length ; j++){
                chainSpellMetadata[chainId].bridges[j].lastSourceLogIndex = 0;
                chainSpellMetadata[chainId].bridges[j].lastDestinationLogIndex = 0;
            }
        }
    }

}
