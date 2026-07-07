// SPDX-License-Identifier: LicenseRef-Caducus-Commercial
pragma solidity ^0.8.24;

/// @title ChainConfig
/// @notice CCIP + VRF infrastructure addresses for testnet deployment.
/// @dev Sourced from Chainlink CCIP Directory and VRF v2.5 supported networks.
library ChainConfig {
    enum Network {
        Sepolia,
        ArbitrumSepolia,
        BaseSepolia
    }

    struct NetworkConfig {
        string name;
        Network network;
        uint256 chainId;
        uint64 chainSelector;
        address ccipRouter;
        address linkToken;
        address vrfCoordinator;
        bytes32 vrfKeyHash;
        /// @notice CRE KeystoneForwarder for this network (docs.chain.link CRE forwarder directory).
        address creForwarder;
    }

    uint256 internal constant SEPOLIA_CHAIN_ID = 11_155_111;
    uint256 internal constant ARBITRUM_SEPOLIA_CHAIN_ID = 421_614;
    uint256 internal constant BASE_SEPOLIA_CHAIN_ID = 84532;

    uint64 internal constant SEPOLIA_SELECTOR = 16015286601757825753;
    uint64 internal constant ARBITRUM_SEPOLIA_SELECTOR = 3478487238524512106;
    uint64 internal constant BASE_SEPOLIA_SELECTOR = 10344971235874465080;

    function getNetworkConfig(Network network) internal pure returns (NetworkConfig memory cfg) {
        if (network == Network.Sepolia) {
            return sepoliaConfig();
        }
        if (network == Network.ArbitrumSepolia) {
            return arbitrumSepoliaConfig();
        }
        if (network == Network.BaseSepolia) {
            return baseSepoliaConfig();
        }
        revert("ChainConfig: unknown network");
    }

    function sepoliaConfig() internal pure returns (NetworkConfig memory) {
        return NetworkConfig({
            name: "ethereum-sepolia",
            network: Network.Sepolia,
            chainId: SEPOLIA_CHAIN_ID,
            chainSelector: SEPOLIA_SELECTOR,
            ccipRouter: 0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59,
            linkToken: 0x779877A7B0D9E8603169DdbD7836e478b4624789,
            vrfCoordinator: 0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B,
            vrfKeyHash: 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae,
            creForwarder: 0xF8344CFd5c43616a4366C34E3EEE75af79a74482
        });
    }

    function arbitrumSepoliaConfig() internal pure returns (NetworkConfig memory) {
        return NetworkConfig({
            name: "arbitrum-sepolia",
            network: Network.ArbitrumSepolia,
            chainId: ARBITRUM_SEPOLIA_CHAIN_ID,
            chainSelector: ARBITRUM_SEPOLIA_SELECTOR,
            ccipRouter: 0x2a9C5afB0d0e4BAb2BCdaE109EC4b0c4Be15a165,
            linkToken: 0xb1D4538B4571d411F07960EF2838Ce337FE1E80E,
            vrfCoordinator: 0x5CE8D5A2BC84beb22a398CCA51996F7930313D61,
            vrfKeyHash: 0x1770bdc7eec7771f7ba4ffd640f34260d7f095b79c92d34a5b2551d6f6cfd2be,
            creForwarder: 0x76c9cf548b4179F8901cda1f8623568b58215E62
        });
    }

    function baseSepoliaConfig() internal pure returns (NetworkConfig memory) {
        return NetworkConfig({
            name: "base-sepolia",
            network: Network.BaseSepolia,
            chainId: BASE_SEPOLIA_CHAIN_ID,
            chainSelector: BASE_SEPOLIA_SELECTOR,
            ccipRouter: 0xD3b06cEbF099CE7DA4AcCf578aaebFDBd6e88a93,
            linkToken: 0xE4aB69C077896252FAFBD49EFD26B5D171A32410,
            vrfCoordinator: 0x5C210eF41CD1a72de73bF76eC39637bB0d3d7BEE,
            vrfKeyHash: 0x9e1344a1247c8a1785d0a4681a27152bffdb43666ae5bf7d14d24a5efd44bf71,
            creForwarder: 0xF8344CFd5c43616a4366C34E3EEE75af79a74482
        });
    }

    /// @notice All supported testnet networks (for peer wiring in deploy scripts).
    function allNetworks() internal pure returns (NetworkConfig[3] memory networks) {
        networks[0] = sepoliaConfig();
        networks[1] = arbitrumSepoliaConfig();
        networks[2] = baseSepoliaConfig();
    }

    /// @notice All CCIP-connected testnet selectors used by LaneToken hop routing.
    function supportedChainSelectors() internal pure returns (uint256[] memory selectors) {
        selectors = new uint256[](3);
        selectors[0] = SEPOLIA_SELECTOR;
        selectors[1] = ARBITRUM_SEPOLIA_SELECTOR;
        selectors[2] = BASE_SEPOLIA_SELECTOR;
    }

    function networkFromEnv(string memory chainName) internal pure returns (Network) {
        bytes32 key = keccak256(bytes(chainName));
        if (key == keccak256(bytes("sepolia")) || key == keccak256(bytes("ethereum-sepolia"))) {
            return Network.Sepolia;
        }
        if (key == keccak256(bytes("arbitrum-sepolia"))) {
            return Network.ArbitrumSepolia;
        }
        if (key == keccak256(bytes("base-sepolia"))) {
            return Network.BaseSepolia;
        }
        revert("ChainConfig: unknown DEPLOY_CHAIN");
    }
}
