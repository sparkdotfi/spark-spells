// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import { Test, StdChains, console }       from 'forge-std/Test.sol';
import { Address }                        from 'src/libraries/Address.sol';
import { Base }                           from 'spark-address-registry/Base.sol';
import { Gnosis }                         from 'spark-address-registry/Gnosis.sol';
import { Ethereum }                       from 'spark-address-registry/Ethereum.sol';
import { IExecutor }                      from 'lib/spark-gov-relay/src/interfaces/IExecutor.sol';
import { IPoolAddressesProviderRegistry } from 'sparklend-v1-core/contracts/interfaces/IPoolAddressesProviderRegistry.sol';
import { IRateLimits }                    from "spark-alm-controller/src/interfaces/IRateLimits.sol";
import { IMetaMorpho }                    from 'lib/metamorpho/src/interfaces/IMetaMorpho.sol';

import { Domain, DomainHelpers } from "xchain-helpers/testing/Domain.sol";
import { ChainIdUtils, ChainId } from "src/libraries/ChainId.sol";
import { OptimismBridgeTesting } from "xchain-helpers/testing/bridges/OptimismBridgeTesting.sol";
import { AMBBridgeTesting }      from "xchain-helpers/testing/bridges/AMBBridgeTesting.sol";
import { CCTPBridgeTesting }     from "xchain-helpers/testing/bridges/CCTPBridgeTesting.sol";
import { Bridge }                from "xchain-helpers/testing/Bridge.sol";

abstract contract SpellRunner is Test {
    using DomainHelpers for Domain;
    using DomainHelpers for StdChains.Chain;

    enum BridgeType {
        OPTIMISM,
        CCTP,
        GNOSIS
    }

    struct ChainSpellMetadata{
      address                        payload;
      IExecutor                      executor;
      Domain                         domain;
      /// @notice on mainnet: empty
      /// on L2s: bridges that'll include txs in the L2. there can be multiple
      /// bridges for a given chain, such as canonical OP bridge and CCTP
      /// USDC-specific bridge
      Bridge[]                       bridges;
      BridgeType[]                   bridgeTypes;
      /// @notice coupled to AdvancedLiquidityManagementTests, rate limits for
      /// Spark Advanced Liquidity Management
      IRateLimits                    almRateLimits;
      /// @notice coupled to SparklendTests, zero on chains where sparklend is not present
      IPoolAddressesProviderRegistry sparklendPooAddressProviderRegistry;
      /// @notice coupled to MorphoTests, Morpho Dai Vault on every supported
      /// chain. Zero if not present
      IMetaMorpho morphoVaultDAI;
    }

    mapping(ChainId chainId => ChainSpellMetadata chainSpellMetadata) internal chainSpellMetadata;

    ChainId[] internal allChains;
    string internal    id;

    modifier onChain(ChainId chainId) virtual;

    /// @dev to be called in setUp
    function setupDomains(uint256 mainnetForkBlock, uint256 baseForkBlock, uint256 gnosisForkBlock) internal {
        // configure the different chains
        chainSpellMetadata[ChainIdUtils.Ethereum()].domain = getChain("mainnet").createFork(mainnetForkBlock);
        chainSpellMetadata[ChainIdUtils.Base()].domain     = getChain("base").createFork(baseForkBlock);
        chainSpellMetadata[ChainIdUtils.Gnosis()].domain   = getChain("gnosis_chain").createFork(gnosisForkBlock);

        // set spell executor for every chain
        chainSpellMetadata[ChainIdUtils.Ethereum()].executor = IExecutor(Ethereum.SPARK_PROXY);
        chainSpellMetadata[ChainIdUtils.Base()].executor     = IExecutor(Base.SPARK_EXECUTOR);
        chainSpellMetadata[ChainIdUtils.Gnosis()].executor   = IExecutor(Gnosis.AMB_EXECUTOR);

        // configure CCTP and OP canonical bridges between mainnet and L2s
        chainSpellMetadata[ChainIdUtils.Base()].bridges.push(
            OptimismBridgeTesting.createNativeBridge(
                chainSpellMetadata[ChainIdUtils.Ethereum()].domain,
                chainSpellMetadata[ChainIdUtils.Base()].domain
        ));
        chainSpellMetadata[ChainIdUtils.Base()].bridgeTypes.push(BridgeType.OPTIMISM);
        chainSpellMetadata[ChainIdUtils.Gnosis()].bridges.push(
            AMBBridgeTesting.createGnosisBridge(
                chainSpellMetadata[ChainIdUtils.Ethereum()].domain,
                chainSpellMetadata[ChainIdUtils.Gnosis()].domain
        ));
        chainSpellMetadata[ChainIdUtils.Gnosis()].bridgeTypes.push(BridgeType.GNOSIS);

        // set entrypoint contract to query addresses for all other sparklend
        // contracts, where sparklend is present (coupled to SparklendTests)
        chainSpellMetadata[ChainIdUtils.Ethereum()].sparklendPooAddressProviderRegistry = IPoolAddressesProviderRegistry(Ethereum.POOL_ADDRESSES_PROVIDER_REGISTRY);
        chainSpellMetadata[ChainIdUtils.Gnosis()].sparklendPooAddressProviderRegistry   = IPoolAddressesProviderRegistry(Gnosis.POOL_ADDRESSES_PROVIDER_REGISTRY);

        // set contract providing Spark Advanced Liquidity Management rate
        // limits for chains where it is present
        chainSpellMetadata[ChainIdUtils.Ethereum()].almRateLimits = IRateLimits(Ethereum.ALM_RATE_LIMITS);
        chainSpellMetadata[ChainIdUtils.Base()].almRateLimits     = IRateLimits(Base.ALM_RATE_LIMITS);

        // set entrypoint for Morpho contracts
        // TODO: add addresses for morpho on Base when we support it
        chainSpellMetadata[ChainIdUtils.Ethereum()].morphoVaultDAI = IMetaMorpho(Ethereum.MORPHO_VAULT_DAI_1);

        allChains.push(ChainIdUtils.Ethereum());
        allChains.push(ChainIdUtils.Base());
        allChains.push(ChainIdUtils.Gnosis());
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
        relayMessageOverBridges();
    }

    /// @dev bridge contracts themselves are stored on mainnet
    function relayMessageOverBridges() private onChain(ChainIdUtils.Ethereum()) {
        for (uint256 i = 0; i < allChains.length; i++) {
            ChainId chainId = ChainIdUtils.fromDomain(chainSpellMetadata[allChains[i]].domain);
            for (uint256 j = 0; j < chainSpellMetadata[chainId].bridges.length ; j++){
                _executeBridge(chainSpellMetadata[chainId].bridges[j], chainSpellMetadata[chainId].bridgeTypes[j]);
            }
        }
    }

    /// @dev this does not relay messages/USDC from L2s to mainnet
    function _executeBridge(Bridge storage bridge, BridgeType bridgeType) private {
        if (bridgeType == BridgeType.OPTIMISM) {
            OptimismBridgeTesting.relayMessagesToDestination(bridge, false);
        } else if (bridgeType == BridgeType.CCTP) {
            CCTPBridgeTesting.relayMessagesToDestination(bridge, false);
        } else if (bridgeType == BridgeType.GNOSIS) {
            AMBBridgeTesting.relayMessagesToDestination(bridge, false);
        }
    }

    function executeL2PayloadsFromBridges() private onChain(ChainIdUtils.Ethereum()) {
        // Base
        chainSpellMetadata[ChainIdUtils.Base()].domain.selectFork();
        IExecutor(Base.SPARK_EXECUTOR).execute(IExecutor(Base.SPARK_EXECUTOR).actionsSetCount() - 1);
        // Gnosis: TODO
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
}
