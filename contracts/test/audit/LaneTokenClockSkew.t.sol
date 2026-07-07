// SPDX-License-Identifier: LicenseRef-Caducus-Commercial
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {LaneToken} from "../../src/core/LaneToken.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {MockCCIPRouter} from "../../src/mocks/MockCCIPRouter.sol";
import {MockVRFCoordinatorV2Plus} from "../../src/mocks/MockVRFCoordinatorV2Plus.sol";
import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";

/// @dev Proves _recordHop tolerates sendTime slightly in the future within MAX_CLOCK_SKEW.
contract LaneTokenClockSkewTest is Test {
    LaneToken public laneToken;
    MockERC20 public mockUsdc;
    MockCCIPRouter public mockRouter;
    MockVRFCoordinatorV2Plus public mockVrfCoordinator;

    address public player = makeAddr("player");
    address public mumbaiPeer = makeAddr("mumbaiPeer");

    uint64 constant LOCAL_SELECTOR = 999_001;
    uint64 constant MUMBAI_SELECTOR = 12532609583862916517;
    uint256 constant START_AMOUNT = 10 * 1e6;

    function setUp() public {
        mockUsdc = new MockERC20("Mock USDC", "mUSDC", 6);
        mockRouter = new MockCCIPRouter();
        mockVrfCoordinator = new MockVRFCoordinatorV2Plus();

        uint256[] memory supportedChains = new uint256[](1);
        supportedChains[0] = MUMBAI_SELECTOR;

        laneToken = new LaneToken(
            address(mockRouter),
            address(mockUsdc),
            address(mockVrfCoordinator),
            1,
            bytes32(0),
            block.chainid,
            LOCAL_SELECTOR,
            supportedChains
        );
        laneToken.setRemoteLaneToken(MUMBAI_SELECTOR, mumbaiPeer);

        mockUsdc.mint(address(laneToken), START_AMOUNT);
    }

    function _hopData(
        bytes32 foreignKey,
        uint64 originChainSelector,
        address originToken,
        uint256 originGameId,
        address initiator,
        uint256 amount,
        uint8 maxHops,
        uint256 sendTime
    ) internal pure returns (bytes memory) {
        return abi.encode(
            foreignKey, originChainSelector, originToken, originGameId, initiator, amount, maxHops, sendTime
        );
    }

    function _tokenAmounts(uint256 amount) internal view returns (Client.EVMTokenAmount[] memory) {
        Client.EVMTokenAmount[] memory amounts = new Client.EVMTokenAmount[](1);
        amounts[0] = Client.EVMTokenAmount({token: address(mockUsdc), amount: amount});
        return amounts;
    }

    function test_futureSendTimeWithinSkew_recordsHop() public {
        uint8 maxHops = 3;
        uint256 remoteChainId = 137;
        address remoteToken = mumbaiPeer;
        uint256 originGameId = 1;
        bytes32 foreignKey = keccak256(abi.encode(remoteChainId, remoteToken, originGameId));
        uint256 futureSendTime = block.timestamp + 600;

        Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
            messageId: bytes32(uint256(0xabc)),
            sourceChainSelector: MUMBAI_SELECTOR,
            sender: abi.encode(mumbaiPeer),
            data: _hopData(
                foreignKey,
                uint64(remoteChainId),
                remoteToken,
                originGameId,
                player,
                START_AMOUNT,
                maxHops,
                futureSendTime
            ),
            destTokenAmounts: _tokenAmounts(START_AMOUNT)
        });

        vm.prank(address(mockRouter));
        laneToken.ccipReceive(message);

        (,, uint8 maxHopsStored, uint8 hopCount,,, bool isActive) = laneToken.getGameRound(1);
        assertEq(maxHopsStored, maxHops);
        assertEq(hopCount, 1);
        assertTrue(isActive);
    }
}
