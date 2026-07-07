// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2 <0.9.0;

import "../Base.sol";
import {Properties} from "../Properties.sol";

abstract contract LaneTokenHandler is Properties {
    // ――――――――――――――――――――――――― Clamped ――――――――――――――――――――――――――

    function laneToken_deposit(uint256 amount) public asActor {
        amount = clampBetween(amount, 1, bettingToken.balanceOf(actor) / 5);
        if (amount == 0) return;
        laneToken.deposit(amount);
        ghosts.laneTokenDeposits += amount;
    }

    function laneToken_withdraw(uint256 amount) public asActor {
        amount = clampBetween(amount, 1, laneToken.s_balances(actor));
        if (amount == 0) return;
        laneToken.withdraw(amount);
        ghosts.laneTokenWithdrawals += amount;
    }

    function laneToken_startGame(uint256 amount, uint8 maxHops) public asActor {
        amount = clampBetween(amount, 1, laneToken.s_balances(actor));
        maxHops = uint8(clampBetween(maxHops, 1, 3));
        if (amount == 0) return;
        laneToken.startGame(SOLO_CHAIN_SELECTOR, amount, maxHops);
        lastSoloGameId = laneToken.s_gameCounter();
    }

    function laneToken_abandonGame(uint256 gameSeed) public asActor {
        uint256 gameId = lastSoloGameId == 0 ? 1 : lastSoloGameId;
        if (gameSeed % 3 == 0) gameId = gameSeed % gameId + 1;
        skipTime(8 days);
        try laneToken.abandonGame(gameId) {} catch {}
    }

    function laneToken_fulfillVrf(uint256 requestId, uint256 randomWord) public {
        uint256[] memory words = new uint256[](1);
        words[0] = randomWord;
        try vrfCoordinator.fulfillRandomWords(requestId == 0 ? 1 : requestId, address(laneToken), words) {} catch {}
    }

    function origin_deposit(uint256 amount) public asActor {
        amount = clampBetween(amount, 1, bettingToken.balanceOf(actor) / 5);
        if (amount == 0) return;
        originLaneToken.deposit(amount);
        ghosts.laneTokenDeposits += amount;
    }

    function origin_startCrossChainGame(uint256 amount, uint8 maxHops) public asActor {
        amount = clampBetween(amount, 1, originLaneToken.s_balances(actor));
        maxHops = uint8(clampBetween(maxHops, 2, 4));
        if (amount == 0) return;
        originLaneToken.startGame(REMOTE_SELECTOR, amount, maxHops);
        lastCrossChainGameId = originLaneToken.s_gameCounter();
    }

    function remote_fulfillVrfReturnToOrigin(uint256 requestId) public {
        uint256[] memory words = new uint256[](1);
        words[0] = 0;
        try vrfCoordinator.fulfillRandomWords(requestId == 0 ? 1 : requestId, address(remoteLaneToken), words) {}
        catch {}
    }

    function origin_fulfillVrf(uint256 requestId, uint256 randomWord) public {
        uint256[] memory words = new uint256[](1);
        words[0] = randomWord;
        try vrfCoordinator.fulfillRandomWords(requestId == 0 ? 1 : requestId, address(originLaneToken), words) {}
        catch {}
    }

    function origin_abandonCrossChainGame(uint256 gameSeed) public asActor {
        uint256 gameId = lastCrossChainGameId == 0 ? 1 : lastCrossChainGameId;
        if (gameSeed % 3 == 0) gameId = gameSeed % gameId + 1;
        skipTime(8 days);
        try originLaneToken.abandonGame(gameId) {} catch {}
    }

    function origin_withdraw(uint256 amount) public asActor {
        amount = clampBetween(amount, 1, originLaneToken.s_balances(actor));
        if (amount == 0) return;
        originLaneToken.withdraw(amount);
        ghosts.laneTokenWithdrawals += amount;
    }

    // ―――――――――――――――――――――――― Unclamped ―――――――――――――――――――――――――

    function laneToken_deposit_raw(uint256 amount) public asActor {
        laneToken.deposit(amount);
        ghosts.laneTokenDeposits += amount;
    }

    function laneToken_withdraw_raw(uint256 amount) public asActor {
        laneToken.withdraw(amount);
        ghosts.laneTokenWithdrawals += amount;
    }

    function laneToken_startGame_raw(uint256 amount, uint8 maxHops) public asActor {
        laneToken.startGame(SOLO_CHAIN_SELECTOR, amount, maxHops);
        lastSoloGameId = laneToken.s_gameCounter();
    }

    function origin_startCrossChainGame_raw(uint256 amount, uint8 maxHops) public asActor {
        originLaneToken.startGame(REMOTE_SELECTOR, amount, maxHops);
        lastCrossChainGameId = originLaneToken.s_gameCounter();
    }
}
