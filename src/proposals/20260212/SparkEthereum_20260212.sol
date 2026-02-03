// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { Ethereum } from "spark-address-registry/Ethereum.sol";

import { SparkPayloadEthereum } from "src/SparkPayloadEthereum.sol";

interface IDssVestLike {
    function create(
        address _usr,
        uint256 _tot,
        uint256 _bgn,
        uint256 _tau,
        uint256 _eta,
        address _mgr
    ) external returns (uint256);

    function file(bytes32, uint256) external;
}

/**
 * @title  February 12, 2026 Spark Ethereum Proposal
 * @author Phoenix Labs
 * @notice Spark Treasury:
 *         - Transfer USDS to Grove for Remaining Share of Ethena Revenue.
 *         - Initiate DssVest for SPK Contributor Vesting.
 * Forum:  https://forum.sky.money/t/february-12-2026-proposed-changes-to-spark-for-upcoming-spell/27674
 * Vote:   https://snapshot.org/#/s:sparkfi.eth/proposal/0x444abfce22102793c25d85d659ff69747fdc56091e41dd6e7c67a9ac5d1b1b15
 *         https://snapshot.org/#/s:sparkfi.eth/proposal/0x3ffd7702f9f23b9dabbb6297e6690f9f648e9968fc88fbfc4fe3aee41d764569
 */
contract SparkEthereum_20260212 is SparkPayloadEthereum {

    uint256 internal constant GROVE_PAYMENT_AMOUNT = 78_394e18;
    uint256 internal constant SPK_VESTING_AMOUNT   = 1_200_000_000e18;
    uint256 internal constant VEST_START           = 1750118400;  // 2025-06-17T00:00:00Z

    address internal constant DSS_VEST  = 0x6Bad07722818Ceff1deAcc33280DbbFdA4939A09;
    address internal constant VEST_USER = 0xEFF097C5CC7F63e9537188FE381D1360158c1511; 

    function _postExecute() internal override {
        // Transfer USDS to Grove for Remaining Share of Ethena Revenue
        IERC20(Ethereum.USDS).transfer(Ethereum.GROVE_SUBDAO_PROXY, GROVE_PAYMENT_AMOUNT);

        // Initiate DssVest for SPK Contributor Vesting

        IDssVestLike(DSS_VEST).file(bytes32("cap"), SPK_VESTING_AMOUNT / (4 * 365 days));

        IDssVestLike(DSS_VEST).create({
            _usr : VEST_USER,
            _tot : SPK_VESTING_AMOUNT,
            _bgn : VEST_START,
            _tau : 4 * 365 days,
            _eta : 365 days,
            _mgr : Ethereum.SPARK_PROXY
        });

        IERC20(Ethereum.SPK).approve(DSS_VEST, SPK_VESTING_AMOUNT);
    }

}
