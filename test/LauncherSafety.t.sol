// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {LaunchBase, IERC20Meta, UERC20Metadata} from "./LaunchBase.sol";
import {ILiquidityLauncher} from "../src/interfaces/ILiquidityLauncher.sol";
import {Distribution} from "../src/types/Distribution.sol";

interface ITokenURI {
    function tokenURI() external view returns (string memory);
}

contract LauncherSafetyTest is LaunchBase {
    function test_graffiti_is_the_keccak_of_the_creator() public view {
        assertEq(
            LAUNCHER.getGraffiti(address(this)), keccak256(abi.encode(address(this)))
        );
    }

    function test_zero_recipient_is_refused() public {
        vm.expectRevert(ILiquidityLauncher.RecipientCannotBeZeroAddress.selector);
        LAUNCHER.createToken(UERC20_FACTORY, "T", "T", 18, SUPPLY, address(0), "");
    }

    function test_launch_events_fire() public {
        address token = createToken("John Pork", "JOHN", "ipfs://bafkreitest");
        vm.expectEmit(true, true, false, true, address(LAUNCHER));
        emit ILiquidityLauncher.TokenDistributed(token, LIQUIDITY_STRATEGY, SUPPLY);
        LAUNCHER.distributeToken(
            token,
            Distribution(LIQUIDITY_STRATEGY, SUPPLY, abi.encode(address(this))),
            keccak256("events-test")
        );
    }

    function test_metadata_is_onchain_json() public {
        address token = createToken("John Pork", "JOHN", "ipfs://bafkreitest");
        string memory uri = ITokenURI(token).tokenURI();
        assertEq(bytes(uri).length > 29, true);
        bytes memory head = new bytes(29);
        for (uint256 i = 0; i < 29; i++) {
            head[i] = bytes(uri)[i];
        }
        assertEq(string(head), "data:application/json;base64,");
    }

    /// The interface's @dev warning, demonstrated: a token parked on the
    /// launcher WITHOUT batching the distribution can be distributed by
    /// ANYONE, with the thief as creator-fee recipient. This is why the site
    /// always sends createToken + distributeToken in one multicall.
    function test_parked_supply_is_anyones_to_distribute() public {
        address token = createToken("John Pork", "JOHN", "ipfs://bafkreitest");
        address thief = makeAddr("thief");
        vm.prank(thief);
        LAUNCHER.distributeToken(
            token, Distribution(LIQUIDITY_STRATEGY, SUPPLY, abi.encode(thief)), bytes32(0)
        );
        assertEq(IERC20Meta(token).balanceOf(address(LAUNCHER)), 0, "the thief distributed our supply");
    }
}
