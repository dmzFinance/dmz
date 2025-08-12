// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";
import "./IdentityRegistry.sol";

contract MyToken is
    ERC20,
    ERC20Pausable,
    ERC20Permit,
    AccessControlDefaultAdminRules
{
    using SafeERC20 for IERC20;

    address public identityRegistryAddress;
    enum CountryListType {
        Whitelist,
        Blacklist
    }
    CountryListType public countryListMode;

    // Mapping for O(1) lookups
    mapping(bytes32 => bool) public countryList;

    uint8 private _decimals;

    // Role definitions
    bytes32 public constant FUND_MANAGER_ROLE = keccak256("FUND_MANAGER_ROLE");

    enum RequestType {
        Mint,
        Burn
    }
    enum RequestStatus {
        Pending,
        Approved,
        Rejected
    }
    struct TokenRequest {
        RequestType requestType;
        address requester;
        address account;
        uint256 amount;
        RequestStatus status;
        uint256 requestedAt;
        uint256 finalizedAt;
    }
    bytes32 private _lastRequestID = 0x0;
    uint256 private _requestCounter = 0;
    mapping(bytes32 => TokenRequest) private _requests;
    mapping(address => bool) private _frozenAccounts;
    mapping(address => uint256) private _temporaryBalances;

    // Events
    event MintRequestCreated(
        bytes32 requestID,
        address requester,
        address to,
        uint256 amount,
        uint256 timestamp
    );
    event BurnRequestCreated(
        bytes32 requestID,
        address requester,
        uint256 amount,
        uint256 timestamp
    );
    event RequestApproved(
        bytes32 requestID,
        uint256 timestamp,
        RequestType requestType
    );
    event RequestRejected(
        bytes32 requestID,
        uint256 timestamp,
        RequestType requestType
    );
    event AccountFrozen(address account);
    event AccountUnfrozen(address account);
    event TokensRecovered(address token, address to, uint256 amount);
    event EtherRecovered(address to, uint256 amount);
    event CountryAdded(bytes32 country);
    event CountryRemoved(bytes32 country);
    event CountryListModeChanged(CountryListType newMode);
    event CountryListCleared();

    /**
     * @dev Constructor to initialize the token contract
     * @param name Token name
     * @param symbol Token symbol
     * @param decimals_ Number of decimals
     * @param initialAdmin Address to be granted admin role
     * @param _identityRegistryAddress Address of the identity registry contract
     * @param _countryList Array of country codes for whitelist/blacklist
     * @param _countryListMode Whether the country list is a whitelist or blacklist
     */
    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals_,
        address initialAdmin,
        address _identityRegistryAddress,
        bytes32[] memory _countryList,
        CountryListType _countryListMode
    )
        ERC20(name, symbol)
        ERC20Permit(name)
        AccessControlDefaultAdminRules(1 days, initialAdmin)
    {
        _setRoleAdmin(FUND_MANAGER_ROLE, DEFAULT_ADMIN_ROLE);

        _decimals = decimals_;
        identityRegistryAddress = _identityRegistryAddress;
        countryListMode = _countryListMode;

        // Initialize country mapping
        for (uint256 i = 0; i < _countryList.length; i++) {
            countryList[_countryList[i]] = true;
        }
    }

    /**
     * @dev Override decimals function to return custom decimal places
     * @return Number of decimal places
     */
    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    /**
     * @dev Pause all token transfers - only admin can call
     */
    function pause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /**
     * @dev Unpause all token transfers - only admin can call
     */
    function unpause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @dev Create a mint request that requires fund manager approval
     * @param to Address to mint tokens to
     * @param amount Amount of tokens to mint
     * @return requestID Unique identifier for the mint request
     */
    function mintRequest(address to, uint256 amount) public returns (bytes32) {
        require(to != address(0), "Mint to the zero address");
        require(amount > 0, "Mint amount must be positive");
        _requestCounter++;

        bytes32 requestID = keccak256(
            abi.encodePacked(
                block.timestamp,
                msg.sender,
                _lastRequestID,
                uint8(RequestType.Mint),
                _requestCounter
            )
        );
        _requests[requestID] = TokenRequest({
            requestType: RequestType.Mint,
            requester: msg.sender,
            account: to,
            amount: amount,
            status: RequestStatus.Pending,
            requestedAt: block.timestamp,
            finalizedAt: 0
        });
        _lastRequestID = requestID;
        emit MintRequestCreated(
            requestID,
            msg.sender,
            to,
            amount,
            block.timestamp
        );
        return requestID;
    }

    /**
     * @dev Create a burn request that requires fund manager approval
     * @param amount Amount of tokens to burn from caller's balance
     * @return requestID Unique identifier for the burn request
     */
    function burnRequest(uint256 amount) public returns (bytes32) {
        require(amount > 0, "Burn amount must be positive");
        transfer(address(this), amount);
        _requestCounter++;
        bytes32 requestID = keccak256(
            abi.encodePacked(
                block.timestamp,
                msg.sender,
                _lastRequestID,
                uint8(RequestType.Burn),
                _requestCounter
            )
        );
        _temporaryBalances[msg.sender] += amount;
        _requests[requestID] = TokenRequest({
            requestType: RequestType.Burn,
            requester: msg.sender,
            account: msg.sender,
            amount: amount,
            status: RequestStatus.Pending,
            requestedAt: block.timestamp,
            finalizedAt: 0
        });
        _lastRequestID = requestID;
        emit BurnRequestCreated(requestID, msg.sender, amount, block.timestamp);
        return requestID;
    }

    /**
     * @dev Approve a pending mint or burn request - only fund managers can call
     * @param requestID The unique identifier of the request to approve
     */
    function approveRequest(
        bytes32 requestID
    ) public onlyRole(FUND_MANAGER_ROLE) {
        require(
            _requests[requestID].requestedAt != 0,
            "Request does not exist"
        );
        require(
            _requests[requestID].status == RequestStatus.Pending,
            "Request is not pending"
        );
        TokenRequest storage request = _requests[requestID];

        if (request.requestType == RequestType.Mint) {
            _mint(request.account, request.amount);
        } else if (request.requestType == RequestType.Burn) {
            _burn(address(this), request.amount);
            _temporaryBalances[request.account] -= request.amount;
        }
        request.status = RequestStatus.Approved;
        request.finalizedAt = block.timestamp;
        emit RequestApproved(requestID, block.timestamp, request.requestType);
    }

    /**
     * @dev Reject a pending mint or burn request - only fund managers can call
     * @param requestID The unique identifier of the request to reject
     */
    function rejectRequest(
        bytes32 requestID
    ) public onlyRole(FUND_MANAGER_ROLE) {
        require(
            _requests[requestID].requestedAt != 0,
            "Request does not exist"
        );
        require(
            _requests[requestID].status == RequestStatus.Pending,
            "Request is not pending"
        );
        TokenRequest storage request = _requests[requestID];

        if (request.requestType == RequestType.Burn) {
            _transfer(address(this), request.account, request.amount);
            _temporaryBalances[request.account] -= request.amount;
        }
        request.status = RequestStatus.Rejected;
        request.finalizedAt = block.timestamp;
        emit RequestRejected(requestID, block.timestamp, request.requestType);
    }

    /**
     * @dev Get details of a specific request
     * @param requestID The unique identifier of the request
     * @return TokenRequest struct containing request details
     */
    function getRequest(
        bytes32 requestID
    ) public view returns (TokenRequest memory) {
        return _requests[requestID];
    }

    /**
     * @dev Force transfer tokens between addresses - only admin can call
     * @param from Address to transfer tokens from
     * @param to Address to transfer tokens to
     * @param amount Amount of tokens to transfer
     */
    function forcedTransfer(
        address from,
        address to,
        uint256 amount
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _transfer(from, to, amount);
    }

    /**
     * @dev Freeze an account to prevent transfers - only admin can call
     * @param account Address of the account to freeze
     */
    function freezeAccount(
        address account
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _frozenAccounts[account] = true;
        emit AccountFrozen(account);
    }

    /**
     * @dev Unfreeze a previously frozen account - only admin can call
     * @param account Address of the account to unfreeze
     */
    function unfreezeAccount(
        address account
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _frozenAccounts[account] = false;
        emit AccountUnfrozen(account);
    }

    /**
     * @dev Verify if an address is whitelisted based on identity registry and country restrictions
     * @param account Address to verify
     * @return bool True if the address is whitelisted, false otherwise
     */
    function _verifyWhitelisted(address account) internal view returns (bool) {
        if (identityRegistryAddress == address(0)) {
            return true;
        }
        IdentityRegistry registry = IdentityRegistry(identityRegistryAddress);
        (bool isWhitelisted, bytes32 country) = registry.verifyAddress(account);
        if (!isWhitelisted) {
            return false;
        }
        if (countryListMode == CountryListType.Whitelist) {
            return countryList[country];
        } else if (countryListMode == CountryListType.Blacklist) {
            return !countryList[country];
        }
        return true;
    }

    /**
     * @dev Override _update to add whitelist verification and freeze checks
     * @param from Address tokens are transferred from
     * @param to Address tokens are transferred to
     * @param value Amount of tokens being transferred
     */
    function _update(
        address from,
        address to,
        uint256 value
    ) internal override(ERC20, ERC20Pausable) {
        require(!_frozenAccounts[from], "ERC20: account is frozen");
        if (from != address(0)) {
            require(_verifyWhitelisted(from), "ERC20: sender not whitelisted");
        }
        require(_verifyWhitelisted(to), "ERC20: receiver not whitelisted");
        super._update(from, to, value);
    }

    /**
     * @dev Update the identity registry contract address
     * @param newRegistry Address of the new identity registry contract
     */
    function updateIdentityRegistry(
        address newRegistry
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        identityRegistryAddress = newRegistry;
    }

    // ==================== Country List Management Functions ====================

    /**
     * @dev Add a single country to the list
     * @param country Country code to add
     */
    function addCountry(bytes32 country) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(country != bytes32(0), "Invalid country code");
        require(!countryList[country], "Country already exists");

        countryList[country] = true;
        emit CountryAdded(country);
    }

    /**
     * @dev Add multiple countries to the list
     * @param countries Array of country codes to add
     */
    function addCountries(
        bytes32[] memory countries
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = 0; i < countries.length; i++) {
            if (countries[i] != bytes32(0) && !countryList[countries[i]]) {
                countryList[countries[i]] = true;
                emit CountryAdded(countries[i]);
            }
        }
    }

    /**
     * @dev Remove a single country from the list
     * @param country Country code to remove
     */
    function removeCountry(
        bytes32 country
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(countryList[country], "Country does not exist");

        countryList[country] = false;
        emit CountryRemoved(country);
    }

    /**
     * @dev Remove multiple countries from the list
     * @param countries Array of country codes to remove
     */
    function removeCountries(
        bytes32[] memory countries
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        for (uint256 i = 0; i < countries.length; i++) {
            if (countryList[countries[i]]) {
                countryList[countries[i]] = false;
                emit CountryRemoved(countries[i]);
            }
        }
    }

    /**
     * @dev Update the country list mode (whitelist or blacklist)
     * @param newMode New country list mode
     */
    function updateCountryListMode(
        CountryListType newMode
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        countryListMode = newMode;
        emit CountryListModeChanged(newMode);
    }

    /**
     * @dev Check if a country is in the list
     * @param country Country code to check
     * @return bool True if country is in the list
     */
    function isCountryInList(bytes32 country) public view returns (bool) {
        return countryList[country];
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

    // ==================== AccessControl Functions ====================

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
