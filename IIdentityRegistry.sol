// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IIdentityRegistry {

    // Events declaration
    event IdentityRegistered(bytes32 indexed hashTx, uint256 expiryDate, address[] wallets, bytes32 country, bytes32 data);
    event IdentityDeleted(bytes32 indexed hashTx);
    event AdminAdded(address indexed newAdmin);
    event AdminRemoved(address indexed adminToRemove);
    event WalletsAdded(bytes32 indexed hashTx, address[] newWallets);
    event WalletsRemoved(bytes32 indexed hashTx, address[] walletsToRemove);
    event ExpiryDateUpdated(bytes32 indexed hashTx, uint256 newExpiryDate);
    event CountryUpdated(bytes32 indexed hashTx, bytes32 country);
    event DataUpdated(bytes32 indexed hashTx, bytes32 data);
    event IdentitiesDeleted(bytes32[] hashTxs);
    event WalletsBatchRemoved(bytes32 hashTx, address[] wallets);

    // Function declarations
    function registerIdentity(bytes32 hashTx, bytes32 country, bytes32 data, uint256 expiryDate, address[] memory wallets) external;
    function deleteIdentity(bytes32 hashTx) external;
    function addAdmin(address newAdmin) external;
    function removeAdmin(address adminToRemove) external;
    function addWallets(bytes32 hashTx, address[] memory newWallets) external;
    function removeWallets(bytes32 hashTx, address[] memory walletsToRemove) external;
    function updateExpiryDate(bytes32 hashTx, uint256 newExpiryDate) external;
    function updateCountry(bytes32 hashTx, bytes32 country) external;
    function updateData(bytes32 hashTx, bytes32 data) external;
    function verifyAddress(address walletToVerify) external view returns (bool, bytes32);
    function getIdentityDetails(bytes32 hashTx) external view returns (uint256 expiryDate, address[] memory wallets, bytes32 country, bytes32 data);
    function registerIdentities(bytes32[] memory hashTxs, bytes32[] memory countries, bytes32[] memory datas, uint256[] memory expiryDates, address[][] memory walletsLists) external;
}
