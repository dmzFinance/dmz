// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IIdentityRegistry
 * @dev Interface for the IdentityRegistry contract
 * @notice Defines the events and functions for identity management
 */
interface IIdentityRegistry {
    
    // ==================== Events Declaration ====================
    
    /**
     * @dev Emitted when a new identity is registered
     * @param hashTx Unique hash identifier for the identity
     * @param expiryDate Identity expiration timestamp
     * @param wallets Array of associated wallet addresses
     * @param country Hash value of country code
     * @param data Hash value of identity-related data
     */
    event IdentityRegistered(
        bytes32 indexed hashTx, 
        uint256 expiryDate, 
        address[] wallets, 
        bytes32 country, 
        bytes32 data
    );
    
    /**
     * @dev Emitted when an identity is deleted
     * @param hashTx Hash identifier of the deleted identity
     */
    event IdentityDeleted(bytes32 indexed hashTx);
    
    /**
     * @dev Emitted when new wallets are added to an identity
     * @param hashTx Identity hash identifier
     * @param newWallets Array of newly added wallet addresses
     */
    event WalletsAdded(bytes32 indexed hashTx, address[] newWallets);
    
    /**
     * @dev Emitted when wallets are removed from an identity
     * @param hashTx Identity hash identifier
     * @param walletsToRemove Array of removed wallet addresses
     */
    event WalletsRemoved(bytes32 indexed hashTx, address[] walletsToRemove);
    
    /**
     * @dev Emitted when an identity's expiry date is updated
     * @param hashTx Identity hash identifier
     * @param newExpiryDate New expiration timestamp
     */
    event ExpiryDateUpdated(bytes32 indexed hashTx, uint256 newExpiryDate);
    
    /**
     * @dev Emitted when an identity's country is updated
     * @param hashTx Identity hash identifier
     * @param country New country code hash value
     */
    event CountryUpdated(bytes32 indexed hashTx, bytes32 country);
    
    /**
     * @dev Emitted when an identity's data is updated
     * @param hashTx Identity hash identifier
     * @param data New data hash value
     */
    event DataUpdated(bytes32 indexed hashTx, bytes32 data);

    /**
    * @dev Emitted when tokens are recovered from the contract
    * @param token Address of the recovered token contract
    * @param to Address that received the recovered tokens
    * @param amount Amount of tokens recovered
    */
    event TokensRecovered(address token, address to, uint256 amount);

    // ==================== Function Declarations ====================
    
    /**
     * @dev Register a single identity
     * @param hashTx Unique hash identifier for the identity
     * @param country Hash value of country code
     * @param data Hash value of identity-related data
     * @param expiryDate Identity expiration timestamp
     * @param wallets Array of wallet addresses to associate
     */
    function registerIdentity(
        bytes32 hashTx, 
        bytes32 country, 
        bytes32 data, 
        uint256 expiryDate, 
        address[] memory wallets
    ) external;
    
    /**
     * @dev Register multiple identities in batch
     * @param hashTxs Array of identity hash identifiers
     * @param countries Array of country code hash values
     * @param datas Array of identity data hash values
     * @param expiryDates Array of expiration timestamps
     * @param walletsLists Two-dimensional array of wallet addresses
     */
    function registerIdentities(
        bytes32[] memory hashTxs, 
        bytes32[] memory countries, 
        bytes32[] memory datas, 
        uint256[] memory expiryDates, 
        address[][] memory walletsLists
    ) external;
    
    /**
     * @dev Delete an identity
     * @param hashTx Hash identifier of the identity to delete
     */
    function deleteIdentity(bytes32 hashTx) external;
    
    /**
     * @dev Add new wallet addresses to an existing identity
     * @param hashTx Identity hash identifier
     * @param newWallets Array of new wallet addresses to add
     */
    function addWallets(bytes32 hashTx, address[] memory newWallets) external;
    
    /**
     * @dev Remove wallet addresses from an identity
     * @param hashTx Identity hash identifier
     * @param walletsToRemove Array of wallet addresses to remove
     */
    function removeWallets(bytes32 hashTx, address[] memory walletsToRemove) external;
    
    /**
     * @dev Update identity expiration date
     * @param hashTx Identity hash identifier
     * @param newExpiryDate New expiration timestamp
     */
    function updateExpiryDate(bytes32 hashTx, uint256 newExpiryDate) external;
    
    /**
     * @dev Update identity country information
     * @param hashTx Identity hash identifier
     * @param country New country code hash value
     */
    function updateCountry(bytes32 hashTx, bytes32 country) external;
    
    /**
     * @dev Update identity data information
     * @param hashTx Identity hash identifier
     * @param data New data hash value
     */
    function updateData(bytes32 hashTx, bytes32 data) external;
    
    /**
     * @dev Verify if a wallet address is valid and not expired
     * @param walletToVerify Wallet address to verify
     * @return isValid Whether the wallet is valid
     * @return country Country code of the associated identity (if valid)
     */
    function verifyAddress(address walletToVerify) external view returns (bool isValid, bytes32 country);
    
    /**
     * @dev Get detailed information of an identity
     * @param hashTx Identity hash identifier
     * @return expiryDate Expiration timestamp
     * @return wallets Array of associated wallet addresses
     * @return country Country code hash value
     * @return data Data hash value
     */
    function getIdentityDetails(bytes32 hashTx) external view 
        returns (
            uint256 expiryDate, 
            address[] memory wallets, 
            bytes32 country, 
            bytes32 data
        );
}