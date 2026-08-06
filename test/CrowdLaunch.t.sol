// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {LaunchBase, IERC20Meta} from "./LaunchBase.sol";
import {Distribution} from "../src/types/Distribution.sol";

/// The Crowd Launch flow: the whole supply goes to the auction strategy, half
/// to be sold over a 4-hour TWAP-bid window, the rest reserved for the pool
/// that is seeded if the auction graduates.
///
/// The strategy's configData is a deep nested struct captured from the site
/// (see the README). Fields that belong to THAT capture — the predicted token,
/// the creator (left as 0xdead placeholders by the site preview), and the
/// auction's absolute block numbers — are patched below; the economic terms
/// (supply split, $10K graduation target, fee 2500, spacing 50, price
/// schedule) are kept verbatim.
contract CrowdLaunchTest is LaunchBase {
    function test_crowd_launch_hands_the_supply_to_the_auction() public {
        address token = createToken("John Pork", "JOHN", "ipfs://bafkreitest");
        LAUNCHER.distributeToken(
            token,
            Distribution(CROWD_TOKEN_STRATEGY, SUPPLY, crowdConfig(token, address(this))),
            keccak256("crowd-launch-test")
        );
        assertEq(IERC20Meta(token).balanceOf(address(LAUNCHER)), 0, "auction pulled everything");
        assertEq(STATE_VIEW.getLiquidity(poolId(token, 2500, 50)), 0, "no pool until graduation");
    }
}
