// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.10;

import { IERC20 } from 'forge-std/interfaces/IERC20.sol';

import { Ethereum } from 'spark-address-registry/Ethereum.sol';

import { ISparkLendFreezerMom } from 'sparklend-freezer/interfaces/ISparkLendFreezerMom.sol';

import { ChainIdUtils } from '../../../src/libraries/ChainId.sol';

import '../../../src/test-harness/SparkTestBase.sol';

interface IAuthority {
    function canCall(address src, address dst, bytes4 sig) external view returns (bool);
    function hat() external view returns (address);
    function launch() external;
    function lift(address target) external;
    function lock(uint256 amount) external;
    function vote(address[] calldata slate) external;
}

interface IExecutable {
    function execute() external;
}

contract SparkEthereum_20250515Test is SparkTestBase {

    address public constant SKY       = 0x56072C95FAA701256059aa122697B133aDEd9279;
    address public constant NEW_CHIEF = 0x929d9A1435662357F54AdcF64DcEE4d6b867a6f9;

    constructor() {
        id = "20250515";
    }

    function setUp() public {
        setupDomains("2025-05-06T17:20:00Z");

        deployPayloads();

        address mkrWhale = makeAddr("governanceWhale");
        uint256 amount   = 2_400_000_000e18;  // Threshold amount to activate the chief.

        IAuthority authority = IAuthority(NEW_CHIEF);

        deal(SKY, mkrWhale, amount);

        vm.startPrank(mkrWhale);
        IERC20(SKY).approve(NEW_CHIEF, amount);
        authority.lock(amount);

        address[] memory slate = new address[](1);
        slate[0] = address(0);
        authority.vote(slate);

        authority.launch();  // Necessary to activate the new chief.

        vm.stopPrank();

        // min amount of blocks that have to pass in order to vote again.
        vm.roll(block.number + 11);
    }

    function test_ETHEREUM_SparkLend_FreezerMomAuthorityUpdate() public onChain(ChainIdUtils.Ethereum()) {
        assertEq(ISparkLendFreezerMom(Ethereum.FREEZER_MOM).authority(), Ethereum.CHIEF);

        executeAllPayloadsAndBridges();

        assertEq(ISparkLendFreezerMom(Ethereum.FREEZER_MOM).authority(), NEW_CHIEF);
    }

    function test_ETHEREUM_FreezerMom() public override onChain(ChainIdUtils.Ethereum()) {
        uint256 snapshot = vm.snapshot();
        _runFreezerMomTests(Ethereum.MKR, Ethereum.CHIEF);

        vm.revertTo(snapshot);
        executeAllPayloadsAndBridges();

        _runFreezerMomTests(SKY, NEW_CHIEF);
    }

    function _runFreezerMomTests(address token_, address authority_) internal {
        ISparkLendFreezerMom freezerMom = ISparkLendFreezerMom(Ethereum.FREEZER_MOM);

        // Sanity checks - cannot call Freezer Mom unless you have the hat or have wards access
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
        _voteAndCast(authority_, token_, Ethereum.SPELL_FREEZE_DAI);
        _assertFrozen(Ethereum.DAI,  true);
        _assertFrozen(Ethereum.WETH, false);

        _voteAndCast(authority_, token_, Ethereum.SPELL_FREEZE_ALL);
        _assertFrozen(Ethereum.DAI,  true);
        _assertFrozen(Ethereum.WETH, true);

        _assertPaused(Ethereum.DAI,  false);
        _assertPaused(Ethereum.WETH, false);
        _voteAndCast(authority_, token_, Ethereum.SPELL_PAUSE_DAI);
        _assertPaused(Ethereum.DAI,  true);
        _assertPaused(Ethereum.WETH, false);

        _voteAndCast(authority_, token_, Ethereum.SPELL_PAUSE_ALL);
        _assertPaused(Ethereum.DAI,  true);
        _assertPaused(Ethereum.WETH, true);
    }

    function _voteAndCast(address _authority, address token, address spell) internal {
        IAuthority authority = IAuthority(_authority);

        address mkrWhale = makeAddr("governanceWhale");
        uint256 amount   = 1_000_000 ether;

        deal(token, mkrWhale, amount);

        vm.startPrank(mkrWhale);
        IERC20(token).approve(address(authority), amount);
        authority.lock(amount);

        address[] memory slate = new address[](1);
        slate[0] = spell;
        authority.vote(slate);

        // min amount of blocks that have to pass in order to vote again.
        vm.roll(block.number + 11);

        authority.lift(spell);

        vm.stopPrank();

        assertEq(authority.hat(), spell);

        vm.prank(makeAddr("randomUser"));
        IExecutable(spell).execute();
    }

}
