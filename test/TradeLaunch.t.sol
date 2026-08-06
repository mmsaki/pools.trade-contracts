// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {LaunchBase, IERC20Meta, IStateView} from "./LaunchBase.sol";
import {Distribution} from "../src/types/Distribution.sol";

interface IUniversalRouter {
    function execute(bytes calldata commands, bytes[] calldata inputs, uint256 deadline)
        external
        payable;
}

interface IPermit2 {
    function approve(address token, address spender, uint160 amount, uint48 expiration) external;
}

interface IERC20Approve {
    function approve(address spender, uint256 amount) external returns (bool);
}

struct PoolKey {
    address currency0;
    address currency1;
    uint24 fee;
    int24 tickSpacing;
    address hooks;
}

/// This chain's v4 router variant carries an extra `minHopPriceX36` slot in
/// its exact-input params — the same layout the trenches bot encodes.
struct ExactInputSingleParams {
    PoolKey poolKey;
    bool zeroForOne;
    uint128 amountIn;
    uint128 amountOutMinimum;
    uint256 minHopPriceX36;
    bytes hookData;
}

/// Trading a fresh instant launch through the Universal Router, with the
/// byte-identical encoding the trenches bot sends: commands [V4_SWAP],
/// actions [SWAP_EXACT_IN_SINGLE, SETTLE_ALL, TAKE_ALL].
contract TradeLaunchTest is LaunchBase {
    IUniversalRouter constant ROUTER =
        IUniversalRouter(0x8876789976dEcBfCbBbe364623C63652db8C0904);
    IPermit2 constant PERMIT2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    bytes1 constant V4_SWAP = 0x10;
    bytes1 constant SWAP_EXACT_IN_SINGLE = 0x06;
    bytes1 constant SETTLE_ALL = 0x0c;
    bytes1 constant TAKE_ALL = 0x0f;

    address token;

    function setUp() public override {
        super.setUp();
        token = createToken("John Pork", "JOHN", "ipfs://bafkreitest");
        LAUNCHER.distributeToken(
            token,
            Distribution(LIQUIDITY_STRATEGY, SUPPLY, abi.encode(address(this))),
            keccak256("trade-launch-test")
        );
        vm.deal(address(this), 10 ether);
    }

    receive() external payable {}

    function swapCalldata(bool buy, uint128 amountIn, uint128 minOut)
        internal
        view
        returns (bytes memory)
    {
        PoolKey memory key = PoolKey(address(0), token, 2500, 25, address(0));
        bytes memory params0 =
            abi.encode(ExactInputSingleParams(key, buy, amountIn, minOut, 0, ""));
        (address input, address output) = buy ? (address(0), token) : (token, address(0));
        bytes memory params1 = abi.encode(input, uint256(amountIn));
        bytes memory params2 = abi.encode(output, uint256(minOut));
        bytes[] memory params = new bytes[](3);
        params[0] = params0;
        params[1] = params1;
        params[2] = params2;
        bytes memory actions = abi.encodePacked(SWAP_EXACT_IN_SINGLE, SETTLE_ALL, TAKE_ALL);
        bytes[] memory inputs = new bytes[](1);
        inputs[0] = abi.encode(actions, params);
        return abi.encodeCall(IUniversalRouter.execute, (abi.encodePacked(V4_SWAP), inputs, type(uint256).max));
    }

    function buy(uint128 ethIn) internal returns (uint256 got) {
        uint256 before = IERC20Meta(token).balanceOf(address(this));
        (bool ok, bytes memory err) = address(ROUTER).call{value: ethIn}(swapCalldata(true, ethIn, 0));
        require(ok, string(err));
        got = IERC20Meta(token).balanceOf(address(this)) - before;
    }

    function test_buy_a_fresh_instant_launch() public {
        (uint160 sqrtBefore,,,) = STATE_VIEW.getSlot0(poolId(token, 2500, 25));
        uint256 got = buy(0.01 ether);
        assertGt(got, 0, "received tokens");
        (uint160 sqrtAfter,,,) = STATE_VIEW.getSlot0(poolId(token, 2500, 25));
        assertLt(sqrtAfter, sqrtBefore, "token got dearer");
        assertGt(STATE_VIEW.getLiquidity(poolId(token, 2500, 25)), 0, "range is active after the first buy");
    }

    function test_a_second_buy_gets_fewer_tokens() public {
        uint256 first = buy(0.01 ether);
        uint256 second = buy(0.01 ether);
        assertLt(second, first);
    }

    function test_min_out_is_enforced() public {
        bytes memory data = swapCalldata(true, 0.01 ether, type(uint128).max);
        (bool ok,) = address(ROUTER).call{value: 0.01 ether}(data);
        assertFalse(ok, "an impossible floor must revert");
    }

    /// UERC20 tokens fix the Permit2 allowance at infinity: approve(PERMIT2)
    /// REVERTS (Permit2AllowanceIsFixedAtInfinity, 0x3f68539a), and no
    /// token-side approval is ever needed. A seller only grants
    /// Permit2 -> router.
    function test_permit2_allowance_is_fixed_at_infinity() public {
        (bool ok,) = token.call(abi.encodeCall(IERC20Approve.approve, (address(PERMIT2), 1)));
        assertFalse(ok, "approve to Permit2 reverts by design");
        assertEq(
            IERC20Meta(token).allowance(address(this), address(PERMIT2)), type(uint256).max
        );
    }

    function test_sell_back_through_permit2() public {
        uint256 got = buy(0.01 ether);
        PERMIT2.approve(token, address(ROUTER), uint160(got), uint48(block.timestamp + 3600));
        uint256 ethBefore = address(this).balance;
        (bool ok, bytes memory err) = address(ROUTER).call(swapCalldata(false, uint128(got), 0));
        require(ok, string(err));
        uint256 proceeds = address(this).balance - ethBefore;
        assertGt(proceeds, 0, "got ETH back");
        assertLt(proceeds, 0.01 ether, "fees and impact were paid");
        assertEq(IERC20Meta(token).balanceOf(address(this)), 0, "sold everything");
    }
}
