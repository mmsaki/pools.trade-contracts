// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {ILiquidityLauncher} from "../src/interfaces/ILiquidityLauncher.sol";
import {Distribution} from "../src/types/Distribution.sol";

struct UERC20Metadata {
    string description;
    string website;
    string image;
    bytes extraData;
}

interface IERC20Meta {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function totalSupply() external view returns (uint256);
    function balanceOf(address) external view returns (uint256);
    function allowance(address, address) external view returns (uint256);
}

interface IStateView {
    function getSlot0(bytes32 poolId)
        external
        view
        returns (uint160 sqrtPriceX96, int24 tick, uint24 protocolFee, uint24 lpFee);
    function getLiquidity(bytes32 poolId) external view returns (uint128);
}

/// Robinhood Chain mainnet deployment, as observed live. See the README's
/// contract table for how each address was recovered and verified.
abstract contract LaunchBase is Test {
    ILiquidityLauncher constant LAUNCHER =
        ILiquidityLauncher(0x0000FffFBE8efE702c8703aE3477FF5dE3d319C0);
    address constant UERC20_FACTORY = 0x000000e200088D55C39a11F609E5F667729ad49b;
    address constant LIQUIDITY_STRATEGY = 0x23f8209572b4a1C2AD88A42749E830791Fb027f1;
    address constant CROWD_TOKEN_STRATEGY = 0x05d552391067389EE44fec3924157ed33F976000;
    address constant CROWD_BID_STRATEGY = 0x1242c9439d589cAE85E121B1f79f2aF51e91DCEE;
    IStateView constant STATE_VIEW = IStateView(0xF3334192D15450CdD385c8B70e03f9A6bD9E673b);
    address constant POOL_MANAGER = 0x8366a39CC670B4001A1121B8F6A443A643e40951;

    uint128 constant SUPPLY = 1_000_000_000e18;

    function setUp() public virtual {
        vm.createSelectFork(vm.envOr("ROBINHOOD_RPC", string("https://rpc.mainnet.chain.robinhood.com/rpc")));
    }

    function createToken(string memory name, string memory symbol, string memory image)
        internal
        returns (address)
    {
        bytes memory tokenData =
            abi.encode(UERC20Metadata("a launch test", "https://example.com", image, ""));
        return LAUNCHER.createToken(
            UERC20_FACTORY, name, symbol, 18, SUPPLY, address(LAUNCHER), tokenData
        );
    }

    function poolId(address token, uint24 fee, int24 tickSpacing) internal pure returns (bytes32) {
        return keccak256(abi.encode(address(0), token, fee, tickSpacing, address(0)));
    }
}
