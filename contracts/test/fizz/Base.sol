// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2 <0.9.0;

import {Actor} from "./Actor.sol";
import {Clamp} from "./utils/Clamp.sol";
import {DecimalPrinter} from "./utils/DecimalPrinter.sol";
import {Deployer} from "./utils/Deployer.sol";
import {vm} from "./utils/Hevm.sol";
import {Logger} from "./utils/Logger.sol";
import {Math} from "./utils/Math.sol";
import {StringUtils} from "./utils/StringUtils.sol";
import {EnumerableSet} from "./utils/EnumerableSet.sol";
import {LaneController} from "../../src/core/LaneController.sol";
import {LaneExecutor} from "../../src/core/LaneExecutor.sol";
import {LaneToken} from "../../src/core/LaneToken.sol";
import {MockERC20} from "../../src/mocks/MockERC20.sol";
import {MockCCIPRouter} from "../../src/mocks/MockCCIPRouter.sol";
import {MockDeliveringCCIPRouter} from "../../src/mocks/MockDeliveringCCIPRouter.sol";
import {MockVRFCoordinatorV2Plus} from "../../src/mocks/MockVRFCoordinatorV2Plus.sol";
import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Base contract with state variables and setup functions
abstract contract Base is StringUtils, Clamp, Deployer, Math {
    using DecimalPrinter for uint256;

    string[] internal ACTOR_LABELS = ["Alice", "Bob", "Charlie"];
    uint256 internal constant BLOCK_INTERVAL = 12 seconds;
    uint256 internal constant INITIAL_ETH_BALANCE = 1_000 ether;
    uint256 internal constant INITIAL_TOKEN_BALANCE = 1_000_000e6;
    uint64 internal constant HOP_CHAIN_A = 111;
    uint64 internal constant HOP_CHAIN_B = 222;
    uint64 internal constant ORIGIN_SELECTOR = 111;
    uint64 internal constant REMOTE_SELECTOR = 222;
    uint64 internal constant SOLO_CHAIN_SELECTOR = 333;
    uint64 internal constant HOME_SELECTOR = 444;

    struct Ghosts {
        uint256 controllerDeposits;
        uint256 controllerPayouts;
        uint256 laneTokenDeposits;
        uint256 laneTokenWithdrawals;
        uint256 executorHopsDelivered;
    }

    Ghosts internal ghosts;

    address[] internal actors;
    address internal actor;
    address internal admin;
    address internal treasury;
    address internal gasReserve;
    address internal cre;

    LaneController internal controller;
    LaneExecutor internal executor;
    LaneToken internal laneToken;
    LaneToken internal originLaneToken;
    LaneToken internal remoteLaneToken;
    MockERC20 internal bettingToken;
    MockCCIPRouter internal execRouter;
    MockDeliveringCCIPRouter internal soloRouter;
    MockVRFCoordinatorV2Plus internal vrfCoordinator;

    uint256[] internal knownRoundIds;
    uint256 internal lastSoloGameId;
    uint256 internal lastCrossChainGameId;
    uint256 internal execMessageNonce;

    modifier asActor() virtual {
        vm.startPrank(actor);
        _;
        vm.stopPrank();
    }

    modifier asAdmin() virtual {
        vm.startPrank(admin);
        _;
        vm.stopPrank();
    }

    modifier asCre() virtual {
        vm.startPrank(cre);
        _;
        vm.stopPrank();
    }

    modifier asExecutor() virtual {
        vm.startPrank(address(executor));
        _;
        vm.stopPrank();
    }

    function setup() internal {
        vm.warp(1_000_000);
        treasury = address(0xBEEF);
        gasReserve = address(0xCAFE);
        cre = address(0xC0E00000000000000000000000000000000001);
        admin = address(this);
        vm.label(admin, "Admin");
        vm.label(treasury, "Treasury");
        vm.label(gasReserve, "GasReserve");
        vm.label(cre, "CRE");

        bettingToken = new MockERC20("USDC", "USDC", 6);
        controller = new LaneController(admin, address(bettingToken), treasury, gasReserve, cre);
        controller.setRoundCooldown(0);

        execRouter = new MockCCIPRouter();
        executor = new LaneExecutor(address(execRouter), admin);
        executor.setLaneController(address(controller));
        executor.setHomeConfig(HOME_SELECTOR, HOME_SELECTOR, address(controller), address(executor));
        executor.setRemoteExecutor(HOP_CHAIN_A, address(executor));
        executor.setRemoteExecutor(HOP_CHAIN_B, address(executor));
        executor.setHopSender(cre, true);
        controller.setHopRecorder(address(executor), true);
        vm.deal(address(executor), 100 ether);

        soloRouter = new MockDeliveringCCIPRouter();
        vrfCoordinator = new MockVRFCoordinatorV2Plus();

        uint256[] memory soloChains = new uint256[](1);
        soloChains[0] = SOLO_CHAIN_SELECTOR;
        laneToken = new LaneToken(
            address(soloRouter),
            address(bettingToken),
            address(vrfCoordinator),
            1,
            bytes32(0),
            block.chainid,
            SOLO_CHAIN_SELECTOR,
            soloChains
        );
        laneToken.setRemoteLaneToken(SOLO_CHAIN_SELECTOR, address(laneToken));
        soloRouter.setChainSelector(address(laneToken), SOLO_CHAIN_SELECTOR);
        vm.deal(address(laneToken), 100 ether);

        uint256[] memory originChains = new uint256[](2);
        originChains[0] = REMOTE_SELECTOR;
        originChains[1] = ORIGIN_SELECTOR;
        originLaneToken = new LaneToken(
            address(soloRouter),
            address(bettingToken),
            address(vrfCoordinator),
            1,
            bytes32(0),
            block.chainid + 1,
            ORIGIN_SELECTOR,
            originChains
        );

        uint256[] memory remoteChains = new uint256[](2);
        remoteChains[0] = ORIGIN_SELECTOR;
        remoteChains[1] = REMOTE_SELECTOR;
        remoteLaneToken = new LaneToken(
            address(soloRouter),
            address(bettingToken),
            address(vrfCoordinator),
            1,
            bytes32(0),
            block.chainid + 2,
            REMOTE_SELECTOR,
            remoteChains
        );

        originLaneToken.setRemoteLaneToken(REMOTE_SELECTOR, address(remoteLaneToken));
        remoteLaneToken.setRemoteLaneToken(ORIGIN_SELECTOR, address(originLaneToken));
        soloRouter.setChainSelector(address(originLaneToken), ORIGIN_SELECTOR);
        soloRouter.setChainSelector(address(remoteLaneToken), REMOTE_SELECTOR);
        vm.deal(address(originLaneToken), 100 ether);
        vm.deal(address(remoteLaneToken), 100 ether);

        setupActors();
    }

    function setupActors() internal {
        for (uint256 i; i < ACTOR_LABELS.length; i++) {
            address _actor = address(new Actor{value: INITIAL_ETH_BALANCE}());
            actors.push(_actor);
            vm.label(_actor, ACTOR_LABELS[i]);
            bettingToken.mint(_actor, INITIAL_TOKEN_BALANCE);
            vm.startPrank(_actor);
            bettingToken.approve(address(controller), type(uint256).max);
            bettingToken.approve(address(laneToken), type(uint256).max);
            bettingToken.approve(address(originLaneToken), type(uint256).max);
            bettingToken.approve(address(remoteLaneToken), type(uint256).max);
            vm.stopPrank();
        }
        actor = actors[0];
    }

    function toActor(address addy) internal view returns (address) {
        return actors[uint256(uint160(addy)) % actors.length];
    }

    function toActorNotCurrent(address addy) internal view returns (address) {
        address _actor = actors[uint256(uint160(addy)) % actors.length];
        if (_actor == actor) {
            _actor = actors[(uint256(uint160(addy)) + 1) % actors.length];
        }
        return _actor;
    }

    function sumActorsBalances() internal view returns (uint256 sumOfBalances) {
        for (uint256 i; i < actors.length; i++) {
            sumOfBalances += actors[i].balance;
        }
    }

    function sumActorsERC20Balances(address _token) internal view returns (uint256 sumOfBalances) {
        for (uint256 i; i < actors.length; i++) {
            sumOfBalances += IERC20(_token).balanceOf(actors[i]);
        }
    }

    function skipBlocks(uint256 blocks) internal {
        vm.roll(block.number + blocks);
        vm.warp(block.timestamp + blocks * BLOCK_INTERVAL);
    }

    function skipTime(uint256 time) internal {
        uint256 blocks = (time + BLOCK_INTERVAL - 1) / BLOCK_INTERVAL;
        vm.roll(block.number + blocks);
        vm.warp(block.timestamp + time);
    }

    function _twoLanePaths() internal pure returns (uint64[][] memory paths) {
        paths = new uint64[][](2);
        paths[0] = new uint64[](1);
        paths[0][0] = HOP_CHAIN_A;
        paths[1] = new uint64[](1);
        paths[1][0] = HOP_CHAIN_B;
    }

    function _trackRound(uint256 roundId) internal {
        if (knownRoundIds.length == 0 || knownRoundIds[knownRoundIds.length - 1] != roundId) {
            knownRoundIds.push(roundId);
        }
    }

    function _laneTokenSolvent(LaneToken token) internal view returns (bool) {
        uint256 onChain = bettingToken.balanceOf(address(token));
        uint256 booked = token.s_totalBooked() + token.s_tokensInPlay();
        return onChain >= booked;
    }

    function _deliverExecutorHop(uint256 roundId, uint8 laneId, uint64 hopChain, uint256 sendTime) internal {
        execMessageNonce++;
        Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
            messageId: keccak256(abi.encodePacked("exec", execMessageNonce)),
            sourceChainSelector: hopChain,
            sender: abi.encode(address(executor)),
            data: abi.encode(roundId, laneId, hopChain, sendTime),
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });
        vm.prank(address(execRouter));
        executor.ccipReceive(message);
        ghosts.executorHopsDelivered++;
    }
}
