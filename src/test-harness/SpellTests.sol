// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.0;

import { IERC20 } from "forge-std/interfaces/IERC20.sol";

import { Ethereum }  from "spark-address-registry/Ethereum.sol";
import { SparkLend } from "spark-address-registry/SparkLend.sol";

import { IAToken } from "sparklend-v1-core/interfaces/IAToken.sol";
import { IPool }   from "sparklend-v1-core/interfaces/IPool.sol";

import { SparkPayloadEthereum } from "src/SparkPayloadEthereum.sol";

import { ChainIdUtils } from "../libraries/ChainIdUtils.sol";

import { ISparkProxyLike } from "../interfaces/Interfaces.sol";

import { SpellRunner } from "./SpellRunner.sol";

abstract contract SpellTests is SpellRunner {

    address internal constant ESM = 0x09e05fF6142F2f9de8B6B65855A1d56B6cfE4c58;

    /**********************************************************************************************/
    /*** Tests                                                                                  ***/
    /**********************************************************************************************/

    function test_ETHEREUM_sparkLend_withdrawAllReserves() external onChain(ChainIdUtils.Ethereum()) {
        address[] memory reserves             = IPool(SparkLend.POOL).getReservesList();
        uint256[] memory aTokenBalancesBefore = new uint256[](reserves.length);
        bool[]    memory accruedToTreasury    = new bool[](reserves.length);

        for (uint256 i = 0; i < reserves.length; i++) {
            address aToken = IPool(SparkLend.POOL).getReserveData(reserves[i]).aTokenAddress;

            if (
                aToken != SparkLend.DAI_SPTOKEN   &&
                aToken != SparkLend.USDS_SPTOKEN  &&
                aToken != SparkLend.USDC_SPTOKEN  &&
                aToken != SparkLend.PYUSD_SPTOKEN &&
                aToken != SparkLend.USDT_SPTOKEN
            ) {
                aTokenBalancesBefore[i] = IERC20(aToken).balanceOf(Ethereum.ALM_OPS_MULTISIG);
            } else {
                aTokenBalancesBefore[i] = IERC20(aToken).balanceOf(Ethereum.ALM_PROXY);
            }

            accruedToTreasury[i] = IPool(SparkLend.POOL).getReserveData(IAToken(aToken).UNDERLYING_ASSET_ADDRESS()).accruedToTreasury > 0;
        }

        _executeAllPayloadsAndBridges();

        for (uint256 i = 0; i < reserves.length; i++) {
            address aToken = IPool(SparkLend.POOL).getReserveData(reserves[i]).aTokenAddress;

            if (
                aToken != SparkLend.DAI_SPTOKEN   &&
                aToken != SparkLend.USDS_SPTOKEN  &&
                aToken != SparkLend.USDC_SPTOKEN  &&
                aToken != SparkLend.PYUSD_SPTOKEN &&
                aToken != SparkLend.USDT_SPTOKEN
            ) {
                if (accruedToTreasury[i]) assertGt(IERC20(aToken).balanceOf(Ethereum.ALM_OPS_MULTISIG), aTokenBalancesBefore[i]);
                else                      assertEq(IERC20(aToken).balanceOf(Ethereum.ALM_OPS_MULTISIG), aTokenBalancesBefore[i]);
            } else {
                if (accruedToTreasury[i]) assertGt(IERC20(aToken).balanceOf(Ethereum.ALM_PROXY), aTokenBalancesBefore[i]);
                else                      assertEq(IERC20(aToken).balanceOf(Ethereum.ALM_PROXY), aTokenBalancesBefore[i]);
            }

            assertEq(
                IERC20(aToken).balanceOf(aToken == SparkLend.DAI_SPTOKEN ? SparkLend.DAI_TREASURY : SparkLend.TREASURY),
                0
            );

            assertEq(IPool(SparkLend.POOL).getReserveData(IAToken(aToken).UNDERLYING_ASSET_ADDRESS()).accruedToTreasury, 0);
        }
    }

    function test_ETHEREUM_PayloadsConfigured() external onChain(ChainIdUtils.Ethereum()) {
        for (uint256 i = 0; i < allChains.length; ++i) {
            uint256 chainId = chainData[allChains[i]].domain.chain.chainId;

            if (chainId == ChainIdUtils.Ethereum()) continue;  // Checking only foreign payloads

            address payload = chainData[chainId].payload;

            if (payload == address(0)) continue;

            // A payload is defined for this domain
            // We verify the mainnet spell defines this payload correctly
            address mainnetPayload = _getForeignPayloadFromMainnetSpell(chainId);
            assertEq(mainnetPayload, payload, "Mainnet payload not matching deployed payload");
        }
    }

    function test_ETHEREUM_PayloadBytecodeMatches() external {
        _testPayloadBytecodeMatches(ChainIdUtils.Ethereum());
    }

    function test_BASE_PayloadBytecodeMatches() external {
        _testPayloadBytecodeMatches(ChainIdUtils.Base());
    }

    function test_GNOSIS_PayloadBytecodeMatches() external {
        _testPayloadBytecodeMatches(ChainIdUtils.Gnosis());
    }

    function test_ARBITRUM_ONE_PayloadBytecodeMatches() external {
        _testPayloadBytecodeMatches(ChainIdUtils.ArbitrumOne());
    }

    function test_OPTIMISM_PayloadBytecodeMatches() external {
        _testPayloadBytecodeMatches(ChainIdUtils.Optimism());
    }

    function test_UNICHAIN_PayloadBytecodeMatches() external {
        _testPayloadBytecodeMatches(ChainIdUtils.Unichain());
    }

    function test_AVALANCHE_PayloadBytecodeMatches() external {
        _testPayloadBytecodeMatches(ChainIdUtils.Avalanche());
    }

    function test_ETHEREUM_SparkProxyStorage() external onChain(ChainIdUtils.Ethereum()) {
        assertEq(ISparkProxyLike(Ethereum.SPARK_PROXY).wards(ESM),                  1);
        assertEq(ISparkProxyLike(Ethereum.SPARK_PROXY).wards(Ethereum.PAUSE_PROXY), 1);

        _checkStorageSlot(Ethereum.SPARK_PROXY, 100);
        _executeAllPayloadsAndBridges();

        assertEq(ISparkProxyLike(Ethereum.SPARK_PROXY).wards(ESM),                  1);
        assertEq(ISparkProxyLike(Ethereum.SPARK_PROXY).wards(Ethereum.PAUSE_PROXY), 1);

        _checkStorageSlot(Ethereum.SPARK_PROXY, 100);
    }

    function test_officeHours() external onChain(ChainIdUtils.Ethereum()) {
        SparkPayloadEthereum payload = SparkPayloadEthereum(chainData[ChainIdUtils.Ethereum()].payload);

        assertEq(payload.officeHours(1773669599), false);  // Monday 16th March 2026, 13:59:59 UTC is not during office hours
        assertEq(payload.officeHours(1773669600), true);   // Monday 16th March 2026, 14:00:00 UTC is during office hours
        assertEq(payload.officeHours(1773694799), true);   // Monday 16th March 2026, 20:59:59 UTC is during office hours
        assertEq(payload.officeHours(1773694800), false);  // Monday 16th March 2026, 21:00:00 UTC is not during office hours

        assertEq(payload.officeHours(1773755999), false);  // Tuesday 17th March 2026, 13:59:59 UTC is not during office hours
        assertEq(payload.officeHours(1773756000), true);   // Tuesday 17th March 2026, 14:00:00 UTC is during office hours
        assertEq(payload.officeHours(1773781199), true);   // Tuesday 17th March 2026, 20:59:59 UTC is during office hours
        assertEq(payload.officeHours(1773781200), false);  // Tuesday 17th March 2026, 21:00:00 UTC is not during office hours

        assertEq(payload.officeHours(1773842399), false);  // Wednesday 18th March 2026, 13:59:59 UTC is not during office hours
        assertEq(payload.officeHours(1773842400), true);   // Wednesday 18th March 2026, 14:00:00 UTC is during office hours
        assertEq(payload.officeHours(1773867599), true);   // Wednesday 18th March 2026, 20:59:59 UTC is during office hours
        assertEq(payload.officeHours(1773867600), false);  // Wednesday 18th March 2026, 21:00:00 UTC is not during office hours

        assertEq(payload.officeHours(1773928799), false);  // Thursday 19th March 2026, 13:59:59 UTC is not during office hours
        assertEq(payload.officeHours(1773928800), true);   // Thursday 19th March 2026, 14:00:00 UTC is during office hours
        assertEq(payload.officeHours(1773953999), true);   // Thursday 19th March 2026, 20:59:59 UTC is during office hours
        assertEq(payload.officeHours(1773954000), false);  // Thursday 19th March 2026, 21:00:00 UTC is not during office hours

        assertEq(payload.officeHours(1774015199), false);  // Friday 20th March 2026, 13:59:59 UTC is not during office hours
        assertEq(payload.officeHours(1774015200), true);   // Friday 20th March 2026, 14:00:00 UTC is during office hours
        assertEq(payload.officeHours(1774040399), true);   // Friday 20th March 2026, 20:59:59 UTC is during office hours
        assertEq(payload.officeHours(1774040400), false);  // Friday 20th March 2026, 21:00:00 UTC is not during office hours

        assertEq(payload.officeHours(1774101599), false);  // Saturday 21st March 2026, 13:59:59 UTC is not during office hours
        assertEq(payload.officeHours(1774101600), false);  // Saturday 21st March 2026, 14:00:00 UTC is not during office hours
        assertEq(payload.officeHours(1774126799), false);  // Saturday 21st March 2026, 20:59:59 UTC is not during office hours
        assertEq(payload.officeHours(1774126800), false);  // Saturday 21st March 2026, 21:00:00 UTC is not during office hours

        assertEq(payload.officeHours(1774187999), false);  // Sunday 22nd March 2026, 13:59:59 UTC is not during office hours
        assertEq(payload.officeHours(1774188000), false);  // Sunday 22nd March 2026, 14:00:00 UTC is not during office hours
        assertEq(payload.officeHours(1774213199), false);  // Sunday 22nd March 2026, 20:59:59 UTC is not during office hours
        assertEq(payload.officeHours(1774213200), false);  // Sunday 22nd March 2026, 21:00:00 UTC is not during office hours
    }

    /**********************************************************************************************/
    /*** View/Pure Functions                                                                     **/
    /**********************************************************************************************/

    function _checkStorageSlot(address target, uint256 limit) internal view {
        for (uint256 slot; slot < limit; ++slot) {
            bytes32 result = vm.load(address(target), bytes32(uint256(slot)));
            require(result == bytes32(0), "Slot is not zero");
        }
    }

}
