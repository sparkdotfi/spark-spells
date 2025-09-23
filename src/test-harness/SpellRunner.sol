// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import { console }   from "forge-std/console.sol";
import { IERC20 }    from "forge-std/interfaces/IERC20.sol";
import { StdChains } from "forge-std/StdChains.sol";
import { Test }      from "forge-std/Test.sol";

import { Address } from '../libraries/Address.sol';

import { Arbitrum } from 'spark-address-registry/Arbitrum.sol';
import { Base }     from 'spark-address-registry/Base.sol';
import { Ethereum } from 'spark-address-registry/Ethereum.sol';
import { Gnosis }   from 'spark-address-registry/Gnosis.sol';
import { Optimism } from 'spark-address-registry/Optimism.sol';
import { Unichain } from 'spark-address-registry/Unichain.sol';

import { IExecutor } from 'lib/spark-gov-relay/src/interfaces/IExecutor.sol';

import { Domain, DomainHelpers } from "xchain-helpers/testing/Domain.sol";
import { OptimismBridgeTesting } from "xchain-helpers/testing/bridges/OptimismBridgeTesting.sol";
import { AMBBridgeTesting }      from "xchain-helpers/testing/bridges/AMBBridgeTesting.sol";
import { ArbitrumBridgeTesting } from "xchain-helpers/testing/bridges/ArbitrumBridgeTesting.sol";
import { CCTPBridgeTesting }     from "xchain-helpers/testing/bridges/CCTPBridgeTesting.sol";
import { Bridge, BridgeType }    from "xchain-helpers/testing/Bridge.sol";
import { RecordedLogs }          from "xchain-helpers/testing/utils/RecordedLogs.sol";

import { ChainIdUtils, ChainId } from "../libraries/ChainId.sol";
import { SparkPayloadEthereum }  from "../SparkPayloadEthereum.sol";

interface IChiefLike {
    function hat() external view returns (address);
    function lock(uint256 amount) external;
    function vote(address[] calldata slate) external;
    function lift(address target) external;
}

interface IDssSpellLike {
    function schedule() external;
    function nextCastTime() external view returns (uint256);
    function cast() external;
}

abstract contract SpellRunner is Test {
    using DomainHelpers for Domain;
    using DomainHelpers for StdChains.Chain;

    // ChainData is already taken in StdChains
    struct DomainData {
        address                        skySpell;
        address                        payload;
        IExecutor                      executor;
        Domain                         domain;
        /// @notice on mainnet: empty
        /// on L2s: bridges that'll include txs in the L2. there can be multiple
        /// bridges for a given chain, such as canonical OP bridge and CCTP
        /// USDC-specific bridge
        Bridge[]                       bridges;
        // These are set only if there is a controller upgrade on this chain in this spell
        address                        prevController;
        address                        newController;
    }

    mapping(ChainId => DomainData) internal chainData;

    ChainId[] internal allChains;
    string internal    id;

    modifier onChain(ChainId chainId) {
        uint256 currentFork = vm.activeFork();
        // uint256 currentTimestamp = vm.getBlockTimestamp();
        if (chainData[chainId].domain.forkId != currentFork) chainData[chainId].domain.selectFork();
        _;
        if (vm.activeFork() != currentFork) vm.selectFork(currentFork);
        // vm.warp(currentTimestamp);
    }

    /// @dev maximum 3 chains in 1 query
    function getBlocksFromDate(string memory date, string[] memory chains) internal returns (uint256[] memory blocks) {
        blocks = new uint256[](chains.length);

        // Process chains in batches of 3
        for (uint256 batchStart; batchStart < chains.length; batchStart += 3) {
            uint256 batchSize = chains.length - batchStart < 3 ? chains.length - batchStart : 3;
            string[] memory batchChains = new string[](batchSize);

            // Create batch of chains
            for (uint256 i = 0; i < batchSize; i++) {
                batchChains[i] = chains[batchStart + i];
            }

            // Build networks parameter for this batch
            string memory networks = "";
            for (uint256 i = 0; i < batchSize; i++) {
                if (i == 0) {
                    networks = string(abi.encodePacked("networks=", batchChains[i]));
                } else {
                    networks = string(abi.encodePacked(networks, "&networks=", batchChains[i]));
                }
            }

            string[] memory inputs = new string[](8);
            inputs[0] = "curl";
            inputs[1] = "-s";
            inputs[2] = "--request";
            inputs[3] = "GET";
            inputs[4] = "--url";
            inputs[5] = string(abi.encodePacked("https://api.g.alchemy.com/data/v1/", vm.envString("ALCHEMY_APIKEY"), "/utility/blocks/by-timestamp?", networks, "&timestamp=", date, "&direction=AFTER"));
            inputs[6] = "--header";
            inputs[7] = "accept: application/json";

            string memory response = string(vm.ffi(inputs));

            // Store results in the correct positions of the final blocks array
            for (uint256 i = 0; i < batchSize; i++) {
                blocks[batchStart + i] = vm.parseJsonUint(response, string(abi.encodePacked(".data[", vm.toString(i), "].block.number")));
            }
        }
    }

    function setupBlocksFromDate(string memory date) internal {
        string[] memory chains = new string[](4);
        chains[0] = "eth-mainnet";
        chains[1] = "base-mainnet";
        chains[2] = "arb-mainnet";
        chains[3] = "opt-mainnet";

        uint256[] memory blocks = getBlocksFromDate(date, chains);

        console.log("Mainnet block:  ", blocks[0]);
        console.log("Base block:     ", blocks[1]);
        console.log("Arbitrum block: ", blocks[2]);
        console.log("Optimism block: ", blocks[3]);

        setChain("unichain", ChainData({
            name: "Unichain",
            rpcUrl: vm.envString("UNICHAIN_RPC_URL"),
            chainId: 130
        }));

        chainData[ChainIdUtils.Ethereum()].domain    = getChain("mainnet").createFork(blocks[0]);
        chainData[ChainIdUtils.Base()].domain        = getChain("base").createFork(blocks[1]);
        chainData[ChainIdUtils.ArbitrumOne()].domain = getChain("arbitrum_one").createFork(blocks[2]);
        chainData[ChainIdUtils.Gnosis()].domain      = getChain("gnosis_chain").createFork(39404891);  // Gnosis block lookup is not supported by Alchemy
        chainData[ChainIdUtils.Optimism()].domain    = getChain("optimism").createFork(blocks[3]);
        chainData[ChainIdUtils.Unichain()].domain    = getChain("unichain").createFork(27541311);
    }

    /// @dev to be called in setUp
    function setupDomains(string memory date) internal {
        setupBlocksFromDate(date);

        // We default to Ethereum domain
        chainData[ChainIdUtils.Ethereum()].domain.selectFork();

        chainData[ChainIdUtils.Ethereum()].executor    = IExecutor(Ethereum.SPARK_PROXY);
        chainData[ChainIdUtils.Base()].executor        = IExecutor(Base.SPARK_EXECUTOR);
        chainData[ChainIdUtils.Gnosis()].executor      = IExecutor(Gnosis.AMB_EXECUTOR);
        chainData[ChainIdUtils.ArbitrumOne()].executor = IExecutor(Arbitrum.SPARK_EXECUTOR);
        chainData[ChainIdUtils.Optimism()].executor    = IExecutor(Optimism.SPARK_EXECUTOR);
        chainData[ChainIdUtils.Unichain()].executor    = IExecutor(Unichain.SPARK_EXECUTOR);

        // Arbitrum One
        chainData[ChainIdUtils.ArbitrumOne()].bridges.push(
            ArbitrumBridgeTesting.createNativeBridge(
                chainData[ChainIdUtils.Ethereum()].domain,
                chainData[ChainIdUtils.ArbitrumOne()].domain
            )
        );
        chainData[ChainIdUtils.ArbitrumOne()].bridges.push(
            CCTPBridgeTesting.createCircleBridge(
                chainData[ChainIdUtils.Ethereum()].domain,
                chainData[ChainIdUtils.ArbitrumOne()].domain
            )
        );

        // Base
        chainData[ChainIdUtils.Base()].bridges.push(
            OptimismBridgeTesting.createNativeBridge(
                chainData[ChainIdUtils.Ethereum()].domain,
                chainData[ChainIdUtils.Base()].domain
            )
        );
        chainData[ChainIdUtils.Base()].bridges.push(
            CCTPBridgeTesting.createCircleBridge(
                chainData[ChainIdUtils.Ethereum()].domain,
                chainData[ChainIdUtils.Base()].domain
            )
        );

        // Gnosis
        chainData[ChainIdUtils.Gnosis()].bridges.push(
            AMBBridgeTesting.createGnosisBridge(
                chainData[ChainIdUtils.Ethereum()].domain,
                chainData[ChainIdUtils.Gnosis()].domain
            )
        );

        // Optimism
        chainData[ChainIdUtils.Optimism()].bridges.push(
            OptimismBridgeTesting.createNativeBridge(
                chainData[ChainIdUtils.Ethereum()].domain,
                chainData[ChainIdUtils.Optimism()].domain
            )
        );
        chainData[ChainIdUtils.Optimism()].bridges.push(
            CCTPBridgeTesting.createCircleBridge(
                chainData[ChainIdUtils.Ethereum()].domain,
                chainData[ChainIdUtils.Optimism()].domain
            )
        );

        // Unichain
        chainData[ChainIdUtils.Unichain()].bridges.push(
            OptimismBridgeTesting.createNativeBridge(
                chainData[ChainIdUtils.Ethereum()].domain,
                chainData[ChainIdUtils.Unichain()].domain
            )
        );
        chainData[ChainIdUtils.Unichain()].bridges.push(
            CCTPBridgeTesting.createCircleBridge(
                chainData[ChainIdUtils.Ethereum()].domain,
                chainData[ChainIdUtils.Unichain()].domain
            )
        );

        allChains.push(ChainIdUtils.Ethereum());
        allChains.push(ChainIdUtils.Base());
        allChains.push(ChainIdUtils.Gnosis());
        allChains.push(ChainIdUtils.ArbitrumOne());
        allChains.push(ChainIdUtils.Optimism());
        allChains.push(ChainIdUtils.Unichain());
    }

    function spellIdentifier(ChainId chainId) private view returns(string memory) {
        string memory slug       = string(abi.encodePacked("Spark", chainId.toDomainString(), "_", id));
        string memory identifier = string(abi.encodePacked(slug, ".sol:", slug));
        return identifier;
    }

    function deployPayload(ChainId chainId) internal onChain(chainId) returns(address) {
        return deployCode(spellIdentifier(chainId));
    }

    function deployPayloads() internal {
        for (uint256 i = 0; i < allChains.length; i++) {
            ChainId chainId = ChainIdUtils.fromDomain(chainData[allChains[i]].domain);
            string memory identifier = spellIdentifier(chainId);
            try vm.getCode(identifier) {
                chainData[chainId].payload = deployPayload(chainId);
            } catch {
                console.log("skipping spell deployment for network: ", chainId.toDomainString());
            }
        }
    }

    function logTimestamps(string memory label) internal {
        uint256 blockTimestampValue = block.timestamp        > 1758289691 ? block.timestamp        - 1758289691 : block.timestamp;
        uint256 vmTimestampValue    = vm.getBlockTimestamp() > 1758289691 ? vm.getBlockTimestamp() - 1758289691 : vm.getBlockTimestamp();
        console.log("-------------", label, "---");
        console.log("block.timestamp", blockTimestampValue);
        console.log("VM timestamp   ", vmTimestampValue);
        console.log("");
    }

    /// @dev takes care to revert the selected fork to what was chosen before
    function executeAllPayloadsAndBridges() internal {
        logTimestamps("PRE EXECUTE");
        // only execute mainnet payload
        executeMainnetPayload();
        logTimestamps("PRE RELAY");
        // then use bridges to execute other chains' payloads
        _relayMessageOverBridges();
        logTimestamps("PRE FOREIGN EXECUTE");
        // execute the foreign payloads (either by simulation or real execute)
        _executeForeignPayloads();
        logTimestamps("POST FOREIGN EXECUTE");
    }

    /// @dev bridge contracts themselves are stored on mainnet
    function _relayMessageOverBridges() internal onChain(ChainIdUtils.Ethereum()) {
        for (uint256 i = 0; i < allChains.length; i++) {
            ChainId chainId = ChainIdUtils.fromDomain(chainData[allChains[i]].domain);
            for (uint256 j = 0; j < chainData[chainId].bridges.length ; j++){
                console.log("Executing bridge for chain: ", chainId.toDomainString());
                logTimestamps("PRE BRIDGE");
                _executeBridge(chainData[chainId].bridges[j]);
                logTimestamps("POST BRIDGE");
            }
        }
    }

    /// @dev this does not relay messages from L2s to mainnet except in the case of USDC
    function _executeBridge(Bridge storage bridge) private {
        uint256 prevTimestamp = block.timestamp;
        if (bridge.bridgeType == BridgeType.OPTIMISM) {
            OptimismBridgeTesting.relayMessagesToDestination(bridge, false);
            logTimestamps("Optimism");
        } else if (bridge.bridgeType == BridgeType.CCTP) {
            CCTPBridgeTesting.relayMessagesToDestination(bridge, false);
            logTimestamps("CCTP To");
            // CCTPBridgeTesting.relayMessagesToSource(bridge, false);
            logTimestamps("CCTP From");
        } else if (bridge.bridgeType == BridgeType.AMB) {
            AMBBridgeTesting.relayMessagesToDestination(bridge, false);
            logTimestamps("AMB");
        } else if (bridge.bridgeType == BridgeType.ARBITRUM) {
            ArbitrumBridgeTesting.relayMessagesToDestination(bridge, false);
            logTimestamps("Arbitrum");
        }
        vm.warp(prevTimestamp);
    }

    function _executeForeignPayloads() private onChain(ChainIdUtils.Ethereum()) {
        for (uint256 i = 0; i < allChains.length; i++) {
            console.log("Executing foreign payload for chain: ", allChains[i].toDomainString());
            logTimestamps("PRE FOREIGN EXECUTE");
            ChainId chainId = ChainIdUtils.fromDomain(chainData[allChains[i]].domain);
            if (chainId == ChainIdUtils.Ethereum()) continue;  // Don't execute mainnet
            address mainnetSpellPayload = _getForeignPayloadFromMainnetSpell(chainId);
            IExecutor executor = chainData[chainId].executor;
            console.log("simulating execution payload for network: ", chainId.toDomainString());
            console.log("mainnetSpellPayload", mainnetSpellPayload);
            if (mainnetSpellPayload != address(0)) {
                // We assume the payload has been queued in the executor (will revert otherwise)
                chainData[chainId].domain.selectFork();
                uint256 actionsSetId = executor.actionsSetCount() - 1;
                uint256 prevTimestamp = block.timestamp;
                vm.warp(executor.getActionsSetById(actionsSetId).executionTime);
                executor.execute(actionsSetId);
                vm.warp(prevTimestamp);
            } else {
                // We will simulate execution until the real spell is deployed in the mainnet spell
                address payload = chainData[chainId].payload;
                if (payload != address(0)) {
                    chainData[chainId].domain.selectFork();
                    vm.prank(address(executor));
                    executor.executeDelegateCall(
                        payload,
                        abi.encodeWithSignature('execute()')
                    );

                    console.log("simulating execution payload for network: ", chainId.toDomainString());
                }
            }
            logTimestamps("POST FOREIGN EXECUTE");
        }
        logTimestamps("POST FOREIGN EXECUTE LOOP");
    }

    function _getForeignPayloadFromMainnetSpell(ChainId chainId) internal onChain(ChainIdUtils.Ethereum()) returns (address) {
        SparkPayloadEthereum spell = SparkPayloadEthereum(chainData[ChainIdUtils.Ethereum()].payload);
        if (chainId == ChainIdUtils.Base()) {
            return spell.PAYLOAD_BASE();
        } else if (chainId == ChainIdUtils.Gnosis()) {
            return spell.PAYLOAD_GNOSIS();
        } else if (chainId == ChainIdUtils.ArbitrumOne()) {
            return spell.PAYLOAD_ARBITRUM();
        } else if (chainId == ChainIdUtils.Optimism()) {
            return spell.PAYLOAD_OPTIMISM();
        } else if (chainId == ChainIdUtils.Unichain()) {
            return spell.PAYLOAD_UNICHAIN();
        } else {
            revert("Unsupported chainId");
        }
    }

    function executeMainnetPayload() internal onChain(ChainIdUtils.Ethereum()) {
        // If Sky spell is deployed, execute through full callstack
        if (chainData[ChainIdUtils.Ethereum()].skySpell != address(0)) {
            _vote(chainData[ChainIdUtils.Ethereum()].skySpell);
            _scheduleWaitAndCast(chainData[ChainIdUtils.Ethereum()].skySpell);
            return;
        }

        address payloadAddress = chainData[ChainIdUtils.Ethereum()].payload;
        IExecutor executor     = chainData[ChainIdUtils.Ethereum()].executor;
        require(Address.isContract(payloadAddress), "PAYLOAD IS NOT A CONTRACT");

        vm.prank(Ethereum.PAUSE_PROXY);
        (bool success,) = address(executor).call(abi.encodeWithSignature(
            'exec(address,bytes)',
            payloadAddress,
            abi.encodeWithSignature('execute()')
        ));
        require(success, "FAILED TO EXECUTE PAYLOAD");
    }

    function _vote(address spell_) internal {
        IChiefLike chief = IChiefLike(Ethereum.CHIEF);
        IERC20     sky   = IERC20(Ethereum.SKY);

        if (chief.hat() != spell_) {
            deal(address(sky), address(this), 100_000_000_000e18);
            sky.approve(address(chief), type(uint256).max);
            chief.lock(100_000_000_000e18);
            address[] memory slate = new address[](1);
            slate[0] = spell_;
            chief.vote(slate);
            chief.lift(spell_);
        }
        assertEq(chief.hat(), spell_, "TestError/spell-is-not-hat");
    }

    function _scheduleWaitAndCast(address spell_) internal {
        IDssSpellLike(spell_).schedule();

        vm.warp(IDssSpellLike(spell_).nextCastTime());

        IDssSpellLike(spell_).cast();

        _fixChronicleStaleness();
    }

    function _fixChronicleStaleness(address oracle) internal {
        bytes32 pokeDataSlot = bytes32(uint256(4));
        bytes32 pokeData     = vm.load(oracle, pokeDataSlot);
        uint128 pokePrice    = uint128(bytes16(pokeData << 128));

        uint256 expiresAt = 365 days * 100;

        vm.store(oracle, pokeDataSlot, bytes32(expiresAt << 128 | uint256(pokePrice)));
    }

    function _fixChronicleStaleness() internal {
        address chronicleBtc = 0x24C392CDbF32Cf911B258981a66d5541d85269ce;
        address chronicleEth = 0x46ef0071b1E2fF6B42d36e5A177EA43Ae5917f4E;

        _fixChronicleStaleness(chronicleBtc);
        _fixChronicleStaleness(chronicleEth);
    }

    function _clearLogs() internal {
        RecordedLogs.clearLogs();

        // Need to also reset all bridge indicies
        for (uint256 i = 0; i < allChains.length; i++) {
            ChainId chainId = ChainIdUtils.fromDomain(chainData[allChains[i]].domain);
            for (uint256 j = 0; j < chainData[chainId].bridges.length ; j++){
                chainData[chainId].bridges[j].lastSourceLogIndex = 0;
                chainData[chainId].bridges[j].lastDestinationLogIndex = 0;
            }
        }
    }

}