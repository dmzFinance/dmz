// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "./IIdentityRegistry.sol";

contract IdentityRegistry is AccessControl, IIdentityRegistry {
    struct Identity {
        uint256 expiryDate;
        address[] wallets;
        bytes32 data;
        bytes32 country;
    }

    uint256 public maxWalletsPerIdentity;
    mapping(bytes32 => Identity) private identities;
    mapping(address => bytes32) private addressToHashTx;
    address[] public admins;

    modifier onlyAdmin() {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Only the admin can call this function");
        _;
    }

    constructor(uint256 _maxWalletsPerIdentity) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        admins.push(msg.sender);
        maxWalletsPerIdentity = _maxWalletsPerIdentity;
    }

    function registerIdentity(
        bytes32 hashTx,
        bytes32 country,
        bytes32 data,
        uint256 expiryDate,
        address[] memory wallets
    ) external onlyAdmin {
        require(wallets.length <= maxWalletsPerIdentity, "Exceeds maximum wallets allowed per identity");
        require(expiryDate > block.timestamp, "Invalid expiry date; must be greater than current time");
        
        Identity storage newIdentity = identities[hashTx];
        require(newIdentity.expiryDate == 0, "Identity already exists");

        // Check if each wallet is already associated with another identity
        for (uint256 i = 0; i < wallets.length; i++) {
            require(addressToHashTx[wallets[i]] == bytes32(0), "One or more wallets are already registered");
        }

        newIdentity.expiryDate = expiryDate;
        newIdentity.data = data;
        newIdentity.country = country;
        newIdentity.wallets = wallets;

        for (uint256 i = 0; i < wallets.length; i++) {
            addressToHashTx[wallets[i]] = hashTx;
        }
        emit IdentityRegistered(hashTx, expiryDate, wallets, country, data);
    }

    function registerIdentities(
        bytes32[] memory hashTxs,
        bytes32[] memory countries,
        bytes32[] memory datas,
        uint256[] memory expiryDates,
        address[][] memory walletsLists
    ) external onlyAdmin {
        require(hashTxs.length == countries.length, "Countries length mismatch");
        require(hashTxs.length == datas.length, "Datas length mismatch");
        require(hashTxs.length == expiryDates.length, "Expiry dates length mismatch");
        require(hashTxs.length == walletsLists.length, "Wallets lists length mismatch");

        for (uint256 j = 0; j < hashTxs.length; j++) {
            require(expiryDates[j] > block.timestamp, "Invalid expiry date; must be greater than current time");
            require(walletsLists[j].length <= maxWalletsPerIdentity, "Exceeds maximum wallets allowed per identity");

            Identity storage newIdentity = identities[hashTxs[j]];
            require(newIdentity.expiryDate == 0, "Identity already exists");

            for (uint256 i = 0; i < walletsLists[j].length; i++) {
                require(addressToHashTx[walletsLists[j][i]] == bytes32(0), "One or more wallets are already registered");
            }

            newIdentity.expiryDate = expiryDates[j];
            newIdentity.data = datas[j];
            newIdentity.country = countries[j];
            newIdentity.wallets = walletsLists[j];

            for (uint256 i = 0; i < walletsLists[j].length; i++) {
                addressToHashTx[walletsLists[j][i]] = hashTxs[j];
            }

            emit IdentityRegistered(hashTxs[j], expiryDates[j], walletsLists[j], countries[j], datas[j]);
        }
    }


    function deleteIdentity(bytes32 hashTx) external onlyAdmin {
        Identity storage identity = identities[hashTx];
        require(identity.expiryDate > 0, "Identity not found");
        
        for (uint256 i = 0; i < identity.wallets.length; i++) {
            delete addressToHashTx[identity.wallets[i]];
        }

        delete identities[hashTx];
        emit IdentityDeleted(hashTx);
    }

    function addAdmin(address newAdmin) external onlyAdmin {
        require(!isAdmin(newAdmin), "Address is already an admin");
        grantRole(DEFAULT_ADMIN_ROLE, newAdmin);
        admins.push(newAdmin);
    }

    function isAdmin(address admin) public view returns (bool) {
        for (uint i = 0; i < admins.length; i++) {
            if (admins[i] == admin) {
                return true;
            }
        }
        return false;
    }


    function removeAdmin(address adminToRemove) external onlyAdmin {
        revokeRole(DEFAULT_ADMIN_ROLE, adminToRemove);
        for (uint256 i = 0; i < admins.length; i++) {
            if (admins[i] == adminToRemove) {
                admins[i] = admins[admins.length - 1];
                admins.pop();
                break;
            }
        }
        emit AdminRemoved(adminToRemove);
    }
    function addWallets(bytes32 hashTx, address[] memory newWallets) external onlyAdmin {
        Identity storage identity = identities[hashTx];
        require(identity.expiryDate > 0, "Identity not found");
        require(identity.wallets.length + newWallets.length <= maxWalletsPerIdentity, "Exceeds maximum wallets allowed per identity");
        
        for (uint256 j = 0; j < newWallets.length; j++) {
            // Check if the new wallet is already associated with another identity
            require(addressToHashTx[newWallets[j]] == bytes32(0), "One or more wallets are already registered with another identity");
            identity.wallets.push(newWallets[j]);
            addressToHashTx[newWallets[j]] = hashTx;
        }
        emit WalletsAdded(hashTx, newWallets);
    }


    function removeWallets(bytes32 hashTx, address[] memory walletsToRemove) external onlyAdmin {
        require(walletsToRemove.length <= maxWalletsPerIdentity, "Number of wallets to remove exceeds maximum allowed");
        Identity storage identity = identities[hashTx];
        require(identity.expiryDate > 0, "Identity not found");

        for (uint256 j = 0; j < walletsToRemove.length; j++) {
            require(addressToHashTx[walletsToRemove[j]] == hashTx, "Wallet does not belong to the specified identity");
            uint256 index = 0;
            while (index < identity.wallets.length && identity.wallets[index] != walletsToRemove[j]) {
                index++;
            }
            require(index < identity.wallets.length, "One or more wallets not found in this identity");
            identity.wallets[index] = identity.wallets[identity.wallets.length - 1];
            identity.wallets.pop();
            delete addressToHashTx[walletsToRemove[j]];
        }
        emit WalletsRemoved(hashTx, walletsToRemove);
    }

    function updateExpiryDate(bytes32 hashTx, uint256 newExpiryDate) external onlyAdmin {
        Identity storage identity = identities[hashTx];
        require(identity.expiryDate > 0, "Identity not found");
        identity.expiryDate = newExpiryDate;
        emit ExpiryDateUpdated(hashTx, newExpiryDate);
    }

    function updateCountry(bytes32 hashTx, bytes32 country) external onlyAdmin {
        Identity storage identity = identities[hashTx];
        require(identity.expiryDate > 0, "Identity not found");
        identity.country = country;
        emit CountryUpdated(hashTx, country);
    }

    function updateData(bytes32 hashTx, bytes32 data) external onlyAdmin {
        Identity storage identity = identities[hashTx];
        require(identity.expiryDate > 0, "Identity not found");
        identity.data = data;
        emit DataUpdated(hashTx, data);
    }

    function verifyAddress(address walletToVerify) external view returns (bool, bytes32) {
        bytes32 hashTx = addressToHashTx[walletToVerify];
        if (hashTx == bytes32(0)) {
            return (false, bytes32(0));
        }

        Identity storage identity = identities[hashTx];
        if (identity.expiryDate < block.timestamp) {
            return (false, identity.country);
        }

        for (uint256 i = 0; i < identity.wallets.length; i++) {
            if (identity.wallets[i] == walletToVerify) {
                return (true, identity.country);
            }
        }
        return (false, bytes32(0));
    }


    function getIdentityDetails(bytes32 hashTx) external view returns (uint256 expiryDate, address[] memory wallets, bytes32 country, bytes32 data) {
        Identity storage identity = identities[hashTx];
        require(identity.expiryDate > 0, "Identity not found");
        return (identity.expiryDate, identity.wallets, identity.country, identity.data);
    }
}
