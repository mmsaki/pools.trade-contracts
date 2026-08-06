// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {LaunchBase, IERC20Meta, UERC20Metadata} from "./LaunchBase.sol";
import {Distribution} from "../src/types/Distribution.sol";

/// The Instant Launch flow the pools.trade site performs, as two direct calls
/// instead of one multicall — equivalent here, where nothing can interleave.
/// The strategy's configData is just the creator fee recipient.
contract InstantLaunchTest is LaunchBase {
    function test_instant_launch_creates_a_live_v4_pool() public {
        address token = createToken("John Pork", "JOHN", "ipfs://bafkreitest");
        assertEq(IERC20Meta(token).symbol(), "JOHN");
        assertEq(IERC20Meta(token).totalSupply(), SUPPLY);
        assertEq(IERC20Meta(token).balanceOf(address(LAUNCHER)), SUPPLY);

        LAUNCHER.distributeToken(
            token, Distribution(LIQUIDITY_STRATEGY, SUPPLY, abi.encode(address(this))), keccak256("instant-launch-test")
        );

        assertEq(IERC20Meta(token).balanceOf(address(LAUNCHER)), 0, "strategy pulled everything");
        (uint160 sqrtPriceX96,,,) = STATE_VIEW.getSlot0(poolId(token, 2500, 25));
        assertGt(sqrtPriceX96, 0, "pool initialized");
        assertGt(IERC20Meta(token).balanceOf(POOL_MANAGER), 0, "supply is in the pool");
        // The locked range sits entirely below the starting price - the pool
        // opens with tokens only, so ACTIVE liquidity is zero until the first
        // buy pays ETH in and the price steps into the range.
        assertEq(STATE_VIEW.getLiquidity(poolId(token, 2500, 25)), 0);
    }

    /// The same flow as one multicall, exactly as the site sends it. The
    /// token address inside distributeToken must be the not-yet-deployed
    /// token, so it is taken from a simulated first leg.
    function test_instant_launch_as_a_single_multicall() public {
        uint256 snap = vm.snapshotState();
        address predicted = createToken("John Pork", "JOHN", "ipfs://bafkreitest");
        vm.revertToState(snap);

        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeWithSelector(
            0xdec14be1,
            UERC20_FACTORY,
            "John Pork",
            "JOHN",
            uint8(18),
            SUPPLY,
            address(LAUNCHER),
            abi.encode(UERC20Metadata("a launch test", "https://example.com", "ipfs://bafkreitest", ""))
        );
        calls[1] = abi.encodeWithSelector(
            0xb6982b48,
            predicted,
            Distribution(LIQUIDITY_STRATEGY, SUPPLY, abi.encode(address(this))),
            keccak256("instant-launch-test")
        );
        (bool ok,) = address(LAUNCHER).call(abi.encodeWithSelector(0xac9650d8, calls));
        assertTrue(ok, "multicall");
        (uint160 sqrtPriceX96,,,) = STATE_VIEW.getSlot0(poolId(predicted, 2500, 25));
        assertGt(sqrtPriceX96, 0, "pool initialized");
    }
}
