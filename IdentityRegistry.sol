// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./IIdentityRegistry.sol";

/**
 * @title IdentityRegistry
 * @dev Identity registry contract for managing user identity information and associated wallet addresses
 * @notice Uses AccessControlDefaultAdminRules for secure admin permission management
 */
contract IdentityRegistry is AccessControlDefaultAdminRules, IIdentityRegistry {
    using SafeERC20 for IERC20;
    // ==================== Struct Definitions ====================

    /**
     * @dev Identity information structure
     * @param expiryDate Identity expiration timestamp
     * @param wallets Array of associated wallet addresses
     * @param data Hash value of identity-related data
     * @param country Hash value of country code
     */
    struct Identity {
        uint256 expiryDate;
        address[] wallets;
        bytes32 data;
        bytes32 country;
    }

    // ==================== State Variables ====================

    /// @dev Maximum number of wallets that can be associated with each identity
    uint256 public maxWalletsPerIdentity;

    /// @dev Mapping from identity hash to identity information
    mapping(bytes32 => Identity) private identities;

    /// @dev Mapping from wallet address to identity hash
    mapping(address => bytes32) private addressToHashTx;

    // ==================== Modifiers ====================

    /**
     * @dev Modifier to restrict function access to admin only
     * @notice Checks if the caller has the default admin role
     */
    modifier onlyAdmin() {
        require(
            hasRole(DEFAULT_ADMIN_ROLE, msg.sender),
            "IdentityRegistry: caller is not an admin"
        );
        _;
    }

    // ==================== Constructor ====================

    /**
     * @dev Constructor
     * @param _maxWalletsPerIdentity Maximum number of wallets that can be associated with each identity
     * @param _initialAdmin Initial admin address
     */
    constructor(
        uint256 _maxWalletsPerIdentity,
        address _initialAdmin
    ) AccessControlDefaultAdminRules(1 days, _initialAdmin) {
        require(
            _maxWalletsPerIdentity > 0,
            "IdentityRegistry: max wallets must be greater than zero"
        );
        require(
            _initialAdmin != address(0),
            "IdentityRegistry: initial admin cannot be zero address"
        );

        maxWalletsPerIdentity = _maxWalletsPerIdentity;
    }

    // ==================== Identity Registration Functions ====================

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
    ) external onlyAdmin {
        require(hashTx != bytes32(0), "IdentityRegistry: hash cannot be zero");
        require(
            wallets.length <= maxWalletsPerIdentity,
            "IdentityRegistry: exceeds maximum wallets per identity"
        );
        require(
            wallets.length > 0,
            "IdentityRegistry: must provide at least one wallet"
        );
        require(
            expiryDate > block.timestamp,
            "IdentityRegistry: expiry date must be in the future"
        );

        Identity storage newIdentity = identities[hashTx];
        require(
            newIdentity.expiryDate == 0,
            "IdentityRegistry: identity already exists"
        );

        // Check if all wallet addresses are available for registration
        for (uint256 i = 0; i < wallets.length; i++) {
            require(
                wallets[i] != address(0),
                "IdentityRegistry: wallet cannot be zero address"
            );
            require(
                addressToHashTx[wallets[i]] == bytes32(0),
                "IdentityRegistry: wallet already registered"
            );
            addressToHashTx[wallets[i]] = hashTx;
        }

        // Set identity information
        newIdentity.expiryDate = expiryDate;
        newIdentity.data = data;
        newIdentity.country = country;
        newIdentity.wallets = wallets;

        emit IdentityRegistered(hashTx, expiryDate, wallets, country, data);
    }

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
    ) external onlyAdmin {
        uint256 length = hashTxs.length;
        require(length > 0, "IdentityRegistry: arrays cannot be empty");
        require(
            length == countries.length,
            "IdentityRegistry: countries length mismatch"
        );
        require(
            length == datas.length,
            "IdentityRegistry: datas length mismatch"
        );
        require(
            length == expiryDates.length,
            "IdentityRegistry: expiry dates length mismatch"
        );
        require(
            length == walletsLists.length,
            "IdentityRegistry: wallets lists length mismatch"
        );

        for (uint256 j = 0; j < length; j++) {
            bytes32 hashTx = hashTxs[j];
            require(
                hashTx != bytes32(0),
                "IdentityRegistry: hash cannot be zero"
            );
            require(
                expiryDates[j] > block.timestamp,
                "IdentityRegistry: expiry date must be in the future"
            );
            require(
                walletsLists[j].length <= maxWalletsPerIdentity,
                "IdentityRegistry: exceeds maximum wallets per identity"
            );
            require(
                walletsLists[j].length > 0,
                "IdentityRegistry: must provide at least one wallet"
            );

            Identity storage newIdentity = identities[hashTx];
            require(
                newIdentity.expiryDate == 0,
                "IdentityRegistry: identity already exists"
            );

            // Check and register wallet addresses
            for (uint256 i = 0; i < walletsLists[j].length; i++) {
                address wallet = walletsLists[j][i];
                require(
                    wallet != address(0),
                    "IdentityRegistry: wallet cannot be zero address"
                );
                require(
                    addressToHashTx[wallet] == bytes32(0),
                    "IdentityRegistry: wallet already registered"
                );
                addressToHashTx[wallet] = hashTx;
            }

            // Set identity information
            newIdentity.expiryDate = expiryDates[j];
            newIdentity.data = datas[j];
            newIdentity.country = countries[j];
            newIdentity.wallets = walletsLists[j];

            emit IdentityRegistered(
                hashTx,
                expiryDates[j],
                walletsLists[j],
                countries[j],
                datas[j]
            );
        }
    }

    // ==================== Identity Management Functions ====================

    /**
     * @dev Delete an identity
     * @param hashTx Hash identifier of the identity to delete
     */
    function deleteIdentity(bytes32 hashTx) external onlyAdmin {
        Identity storage identity = identities[hashTx];
        require(
            identity.expiryDate > 0,
            "IdentityRegistry: identity not found"
        );

        // Clear all associated wallet address mappings
        for (uint256 i = 0; i < identity.wallets.length; i++) {
            delete addressToHashTx[identity.wallets[i]];
        }

        delete identities[hashTx];
        emit IdentityDeleted(hashTx);
    }

    // ==================== Wallet Management Functions ====================

    /**
     * @dev Add new wallet addresses to an existing identity
     * @param hashTx Identity hash identifier
     * @param newWallets Array of new wallet addresses to add
     */
    function addWallets(
        bytes32 hashTx,
        address[] memory newWallets
    ) external onlyAdmin {
        require(
            newWallets.length > 0,
            "IdentityRegistry: must provide at least one wallet"
        );

        Identity storage identity = identities[hashTx];
        require(
            identity.expiryDate > 0,
            "IdentityRegistry: identity not found"
        );
        require(
            identity.expiryDate > block.timestamp,
            "IdentityRegistry: identity has expired"
        );
        require(
            identity.wallets.length + newWallets.length <=
                maxWalletsPerIdentity,
            "IdentityRegistry: exceeds maximum wallets per identity"
        );

        // Add new wallets and check if they are already registered
        for (uint256 j = 0; j < newWallets.length; j++) {
            address newWallet = newWallets[j];
            require(
                newWallet != address(0),
                "IdentityRegistry: wallet cannot be zero address"
            );
            require(
                addressToHashTx[newWallet] == bytes32(0),
                "IdentityRegistry: wallet already registered"
            );

            identity.wallets.push(newWallet);
            addressToHashTx[newWallet] = hashTx;
        }

        emit WalletsAdded(hashTx, newWallets);
    }

    /**
     * @dev Remove wallet addresses from an identity
     * @param hashTx Identity hash identifier
     * @param walletsToRemove Array of wallet addresses to remove
     */
    function removeWallets(
        bytes32 hashTx,
        address[] memory walletsToRemove
    ) external onlyAdmin {
        require(
            walletsToRemove.length > 0,
            "IdentityRegistry: must provide at least one wallet to remove"
        );

        Identity storage identity = identities[hashTx];
        require(
            identity.expiryDate > 0,
            "IdentityRegistry: identity not found"
        );
        require(
            identity.wallets.length > walletsToRemove.length,
            "IdentityRegistry: cannot remove all wallets"
        );

        // Remove wallet addresses
        for (uint256 j = 0; j < walletsToRemove.length; j++) {
            address walletToRemove = walletsToRemove[j];
            require(
                addressToHashTx[walletToRemove] == hashTx,
                "IdentityRegistry: wallet not associated with identity"
            );

            // Find the wallet address in the array
            uint256 index = 0;
            while (
                index < identity.wallets.length &&
                identity.wallets[index] != walletToRemove
            ) {
                index++;
            }
            require(
                index < identity.wallets.length,
                "IdentityRegistry: wallet not found in identity"
            );

            // Replace the element to be deleted with the last element, then remove the last element
            identity.wallets[index] = identity.wallets[
                identity.wallets.length - 1
            ];
            identity.wallets.pop();
            delete addressToHashTx[walletToRemove];
        }

        emit WalletsRemoved(hashTx, walletsToRemove);
    }

    // ==================== Identity Information Update Functions ====================

    /**
     * @dev Update identity expiration date
     * @param hashTx Identity hash identifier
     * @param newExpiryDate New expiration timestamp
     */
    function updateExpiryDate(
        bytes32 hashTx,
        uint256 newExpiryDate
    ) external onlyAdmin {
        Identity storage identity = identities[hashTx];
        require(
            identity.expiryDate > 0,
            "IdentityRegistry: identity not found"
        );
        require(
            newExpiryDate > block.timestamp,
            "IdentityRegistry: new expiry date must be in the future"
        );

        identity.expiryDate = newExpiryDate;
        emit ExpiryDateUpdated(hashTx, newExpiryDate);
    }

    /**
     * @dev Update identity country information
     * @param hashTx Identity hash identifier
     * @param country New country code hash value
     */
    function updateCountry(bytes32 hashTx, bytes32 country) external onlyAdmin {
        Identity storage identity = identities[hashTx];
        require(
            identity.expiryDate > 0,
            "IdentityRegistry: identity not found"
        );
        require(
            identity.expiryDate > block.timestamp,
            "IdentityRegistry: identity has expired"
        );

        identity.country = country;
        emit CountryUpdated(hashTx, country);
    }

    /**
     * @dev Update identity data information
     * @param hashTx Identity hash identifier
     * @param data New data hash value
     */
    function updateData(bytes32 hashTx, bytes32 data) external onlyAdmin {
        Identity storage identity = identities[hashTx];
        require(
            identity.expiryDate > 0,
            "IdentityRegistry: identity not found"
        );
        require(
            identity.expiryDate > block.timestamp,
            "IdentityRegistry: identity has expired"
        );

        identity.data = data;
        emit DataUpdated(hashTx, data);
    }

    // ==================== Query Functions ====================

    /**
     * @dev Verify if a wallet address is valid and not expired
     * @param walletToVerify Wallet address to verify
     * @return isValid Whether the wallet is valid
     * @return country Country code of the associated identity (if valid)
     */
    function verifyAddress(
        address walletToVerify
    ) external view returns (bool isValid, bytes32 country) {
        bytes32 hashTx = addressToHashTx[walletToVerify];

        // If wallet address is not registered
        if (hashTx == bytes32(0)) {
            return (false, bytes32(0));
        }

        Identity storage identity = identities[hashTx];

        // If identity has expired
        if (identity.expiryDate <= block.timestamp) {
            return (false, identity.country);
        }

        return (true, identity.country);
    }

    /**
     * @dev Get detailed information of an identity
     * @param hashTx Identity hash identifier
     * @return expiryDate Expiration timestamp
     * @return wallets Array of associated wallet addresses
     * @return country Country code hash value
     * @return data Data hash value
     */
    function getIdentityDetails(
        bytes32 hashTx
    )
        external
        view
        returns (
            uint256 expiryDate,
            address[] memory wallets,
            bytes32 country,
            bytes32 data
        )
    {
        Identity storage identity = identities[hashTx];
        require(
            identity.expiryDate > 0,
            "IdentityRegistry: identity not found"
        );

        return (
            identity.expiryDate,
            identity.wallets,
            identity.country,
            identity.data
        );
    }

    // ==================== Token Recovery Functions ====================

    /**
     * @dev Recover ERC20 tokens that were accidentally sent to this contract
     * @param token Address of the ERC20 token contract to recover
     * @param to Address to send the recovered tokens to
     * @param amount Amount to recover (0 means recover all available balance)
     */
    function recoverERC20(
        address token,
        address to,
        uint256 amount
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(token != address(0), "Token address cannot be zero");
        require(to != address(0), "Recipient address cannot be zero");
        require(token != address(this), "Cannot recover own tokens");

        IERC20 tokenContract = IERC20(token);
        uint256 balance = tokenContract.balanceOf(address(this));
        require(balance > 0, "No tokens to recover");

        // If amount is 0, recover all available balance
        uint256 recoverAmount = amount == 0 ? balance : amount;
        require(recoverAmount <= balance, "Insufficient token balance");

        tokenContract.safeTransfer(to, recoverAmount);
        emit TokensRecovered(token, to, recoverAmount);
    }

    /**
     * @dev Recover Ether that was accidentally sent to this contract
     * @param to Address to send the recovered Ether to
     * @param amount Amount to recover (0 means recover all available balance)
     */
    function recoverEther(
        address payable to,
        uint256 amount
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(to != address(0), "Recipient address cannot be zero");

        uint256 balance = address(this).balance;
        require(balance > 0, "No ether to recover");

        // If amount is 0, recover all available balance
        uint256 recoverAmount = amount == 0 ? balance : amount;
        require(recoverAmount <= balance, "Insufficient ether balance");

        (bool success, ) = to.call{value: recoverAmount}("");
        require(success, "Ether transfer failed");
        emit EtherRecovered(to, recoverAmount);
    }
    /**
     * @dev Override revokeRole to prevent admin self-revocation
     */
    function revokeRole(bytes32 role, address account) public virtual override {
        require(
            !(role == DEFAULT_ADMIN_ROLE && account == msg.sender),
            "Admins cannot revoke their own admin role"
        );
        super.revokeRole(role, account);
    }

    /**
     * @dev Completely disable renounceRole function
     * @notice This function is disabled for security reasons
     * Users cannot renounce their own roles - only admins can revoke roles
     */
    function renounceRole(
        bytes32 role,
        address callerConfirmation
    ) public virtual override {
        role;
        callerConfirmation;
        revert("IdentityRegistry: renounceRole is disabled for security");
    }
}
