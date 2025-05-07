// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.10;

import { Ethereum } from 'spark-address-registry/Ethereum.sol';

import '../../../src/test-harness/SparkTestBase.sol';

import { ChainIdUtils } from '../../../src/libraries/ChainId.sol';

import { IERC20 }               from 'forge-std/interfaces/IERC20.sol';
import { ISparkLendFreezerMom } from 'sparklend-freezer/interfaces/ISparkLendFreezerMom.sol';

interface SparkLendFreezerMom {
    function authority() external view returns (address);
}

interface IAuthority {
    function canCall(address src, address dst, bytes4 sig) external view returns (bool);
    function hat() external view returns (address);
    function lock(uint256 amount) external;
    function vote(address[] calldata slate) external;
    function lift(address target) external;
}

interface IExecutable {
    function execute() external;
}

contract SparkEthereum_20250515Test is SparkTestBase {

    address public constant SKY = 0x56072C95FAA701256059aa122697B133aDEd9279;

    constructor() {
        id = "20250515";
    }

    function setUp() public {
        setupDomains("2025-05-06T17:20:00Z");

        deployPayloads();
    }

    function test_ETHEREUM_sparkLend_freezerMomAuthorityUpdate() public onChain(ChainIdUtils.Ethereum()) {
        assertEq(SparkLendFreezerMom(Ethereum.FREEZER_MOM).authority(), Ethereum.CHIEF);

        executeAllPayloadsAndBridges();

        assertEq(SparkLendFreezerMom(Ethereum.FREEZER_MOM).authority(), 0x929d9A1435662357F54AdcF64DcEE4d6b867a6f9);
    }

    function test_ETHEREUM_FreezerMom() public override onChain(ChainIdUtils.Ethereum()) {
        _runFreezerMomTests(Ethereum.CHIEF);

        executeAllPayloadsAndBridges();

        _runFreezerMomTests(0x929d9A1435662357F54AdcF64DcEE4d6b867a6f9);
    }

    function _runFreezerMomTests(address authority_) internal {
        ISparkLendFreezerMom freezerMom = ISparkLendFreezerMom(Ethereum.FREEZER_MOM);

        // Sanity checks - cannot call Freezer Mom unless you have the hat
        vm.expectRevert("SparkLendFreezerMom/not-authorized");
        freezerMom.freezeMarket(Ethereum.DAI, true);
        vm.expectRevert("SparkLendFreezerMom/not-authorized");
        freezerMom.freezeAllMarkets(true);
        vm.expectRevert("SparkLendFreezerMom/not-authorized");
        freezerMom.pauseMarket(Ethereum.DAI, true);
        vm.expectRevert("SparkLendFreezerMom/not-authorized");
        freezerMom.pauseAllMarkets(true);

        _assertFrozen(Ethereum.DAI,  false);
        _assertFrozen(Ethereum.WETH, false);
        _voteAndCast(authority_, SKY, Ethereum.SPELL_FREEZE_DAI);
        _assertFrozen(Ethereum.DAI,  true);
        _assertFrozen(Ethereum.WETH, false);

        _voteAndCast(authority_, SKY, Ethereum.SPELL_FREEZE_ALL);
        _assertFrozen(Ethereum.DAI,  true);
        _assertFrozen(Ethereum.WETH, true);

        _assertPaused(Ethereum.DAI,  false);
        _assertPaused(Ethereum.WETH, false);
        _voteAndCast(authority_, SKY, Ethereum.SPELL_PAUSE_DAI);
        _assertPaused(Ethereum.DAI,  true);
        _assertPaused(Ethereum.WETH, false);

        _voteAndCast(authority_, SKY, Ethereum.SPELL_PAUSE_ALL);
        _assertPaused(Ethereum.DAI,  true);
        _assertPaused(Ethereum.WETH, true);
    }


    function _voteAndCast(address _authority, address _token, address _spell) internal {
        IAuthority authority = IAuthority(_authority);

        address mkrWhale = makeAddr("mkrWhale");
        uint256 amount = 1_000_000 ether;

        deal(_token, mkrWhale, amount);

        vm.startPrank(mkrWhale);
        IERC20(_token).approve(address(authority), amount);
        authority.lock(amount);

        address[] memory slate = new address[](1);
        slate[0] = _spell;
        authority.vote(slate);

        vm.roll(block.number + 1);

        authority.lift(_spell);

        vm.stopPrank();

        assertEq(authority.hat(), _spell);

        vm.prank(makeAddr("randomUser"));
        IExecutable(_spell).execute();
    }

}
