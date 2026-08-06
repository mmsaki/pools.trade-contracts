// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {LaunchBase, IERC20Meta} from "./LaunchBase.sol";
import {Distribution} from "../src/types/Distribution.sol";

interface ICrowdStrategy {
    function migrate(address auction) external;
}

interface ICCA {
    function submitBid(
        uint256 maxPrice,
        uint128 amount,
        address owner,
        uint256 prevTickPrice,
        bytes calldata data
    ) external payable returns (uint256 bidId);
    function exitBid(uint256 bidId) external;
    function claimTokensBatch(address owner, uint256[] calldata bidIds) external;
    function floorPrice() external view returns (uint256);
    function checkpoint() external;
    function isGraduated() external view returns (bool);
    function currencyRaised() external view returns (uint256);
    function requiredCurrencyRaised() external view returns (uint256);
    function tickSpacing() external view returns (uint256);
    function clearingPrice() external view returns (uint256);
}

/// Bidding on a crowd launch's CCA, decoded from live mainnet bids:
/// submitBid(maxPrice, amount=msg.value, owner, priceHint, "").
contract CrowdBidTest is LaunchBase {
    address auction;
    address token;

    /// A valid bid price is a multiple of tickSpacing above floorPrice —
    /// anything else reverts TickPriceNotAtBoundary. Read both from the
    /// auction and stand ten ticks above the floor.
    function alignedPrice() internal view returns (uint256) {
        return ICCA(auction).floorPrice() + ICCA(auction).tickSpacing() * 10;
    }

    function setUp() public override {
        super.setUp();
        token = createToken("John Pork", "JOHN", "ipfs://bafkreitest");
        vm.recordLogs();
        LAUNCHER.distributeToken(
            token,
            Distribution(CROWD_TOKEN_STRATEGY, SUPPLY, crowdConfig(token, address(this))),
            keccak256("crowd-bid-test")
        );
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i = 0; i < logs.length; i++) {
            address e = logs[i].emitter;
            if (e != address(LAUNCHER) && e != UERC20_FACTORY && e != token && e != CROWD_TOKEN_STRATEGY) {
                auction = e;
                break;
            }
        }
        require(auction != address(0), "auction not found in launch logs");
        vm.deal(address(this), 5000 ether);
        vm.roll(block.number + 2);
    }

    function test_submit_a_bid() public {
        uint256 price = alignedPrice();
        uint256 bidId = ICCA(auction).submitBid{value: 0.05 ether}(
            price, 0.05 ether, address(this), ICCA(auction).floorPrice(), ""
        );
        assertGt(address(auction).balance, 0, "the auction holds the bid");
        assertGe(bidId, 0);
    }

    /// A winning bid is committed while the auction runs (AuctionIsNotOver)
    /// — exits happen after the end. An under-target raise fails the launch
    /// and the bid comes back whole.
    function test_after_a_failed_auction_the_bid_refunds() public {
        uint256 price = alignedPrice();
        uint256 bidId = ICCA(auction).submitBid{value: 0.05 ether}(
            price, 0.05 ether, address(this), ICCA(auction).floorPrice(), ""
        );
        vm.roll(block.number + WINDOW_BLOCKS + 2);
        uint256 before = address(this).balance;
        ICCA(auction).exitBid(bidId);
        assertGt(address(this).balance, before, "the bid came back");
    }

    /// What a bid can and cannot do while the raise is short of target.
    ///
    /// The CCA issues tokens on a per-block schedule and only sells what is
    /// bid for, so demand concentrated in a few blocks of a 144k-block window
    /// cannot reach the target however large it is — the live GOAT auction
    /// cleared ~146 ETH spread across its whole window. That makes a
    /// graduation end-to-end impractical to stage here, and this pins the
    /// rules a bidder actually meets instead of faking one:
    ///   - claims revert NotGraduated until the raise clears,
    ///   - the bid is still exitable after the end, whole.
    function test_claims_wait_for_graduation_and_the_bid_stays_exitable() public {
        uint256 price = alignedPrice();
        uint256 bidId = ICCA(auction).submitBid{value: 0.6 ether}(
            price, 0.6 ether, address(this), ICCA(auction).floorPrice(), ""
        );
        for (uint256 i = 0; i < 23; i++) {
            vm.roll(block.number + 6000);
            ICCA(auction).checkpoint();
        }
        vm.roll(block.number + WINDOW_BLOCKS + 2);
        ICCA(auction).checkpoint();
        assertFalse(ICCA(auction).isGraduated(), "a partial raise does not graduate");
        ICCA(auction).exitBid(bidId);
        uint256[] memory ids = new uint256[](1);
        ids[0] = bidId;
        vm.expectRevert(bytes4(0xd66173a5)); // NotGraduated()
        ICCA(auction).claimTokensBatch(address(this), ids);
    }

    receive() external payable {}
}
