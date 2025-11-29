// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title RetirementCertificateNFT
 * @dev Optimized for Foundry - smaller structs
 */
contract RetirementCertificateNFT is ERC721URIStorage, Ownable, ReentrancyGuard {
    
    uint256 private _certificateIdCounter;
    IERC1155 public carbonCreditToken;
    
    struct RetirementInfo {
        address retiree;
        uint256 projectId;
        uint256 amountRetired;
        uint256 retirementDate;
        bytes32 retirementHash;
    }
    
    struct RetirementDetails {
        string retirementReason;
        string beneficiary;
        string metadataURI;
    }
    
    struct ProjectInfo {
        string projectName;
        string projectCategory;
        string country;
        uint256 vintageYear;
    }
    
    mapping(uint256 => RetirementInfo) public retirementInfo;
    mapping(uint256 => RetirementDetails) public retirementDetails;
    mapping(uint256 => ProjectInfo) public projectInfo;
    mapping(address => uint256[]) public retireeRetirements;
    mapping(uint256 => uint256) public projectRetirements;
    mapping(bytes32 => bool) public usedRetirementHashes;
    mapping(uint256 => mapping(address => uint256)) public retiredByUser;
    
    event CreditsRetired(
        uint256 indexed certificateId,
        address indexed retiree,
        uint256 indexed projectId,
        uint256 amount
    );
    
    event CertificateMinted(
        uint256 indexed certificateId,
        address indexed retiree
    );
    
    event RetirementReport(
        address indexed retiree,
        uint256 totalCount,
        uint256 totalCO2Retired,
        uint256[] certificateIds
    );

    constructor(address _carbonCreditToken) 
        ERC721("Carbon Credit Retirement Certificate", "CCRC")
        Ownable(msg.sender)
    {
        carbonCreditToken = IERC1155(_carbonCreditToken);
    }
    
    function retireCredits(
        uint256 _projectId,
        uint256 _amount,
        string memory _retirementReason,
        string memory _beneficiary,
        string memory _metadataURI
    ) external nonReentrant returns (uint256) {
        require(_amount > 0, "Amount must be greater than 0");
        require(
            carbonCreditToken.balanceOf(msg.sender, _projectId) >= _amount,
            "Insufficient balance"
        );
        
        bytes32 retirementHash = keccak256(
            abi.encodePacked(msg.sender, _projectId, _amount, block.timestamp, _certificateIdCounter)
        );
        
        require(!usedRetirementHashes[retirementHash], "Hash collision");
        usedRetirementHashes[retirementHash] = true;
        
        carbonCreditToken.safeTransferFrom(
            msg.sender,
            address(0x000000000000000000000000000000000000dEaD),
            _projectId,
            _amount,
            ""
        );
        
        _certificateIdCounter++;
        uint256 certId = _certificateIdCounter;
        
        retirementInfo[certId] = RetirementInfo({
            retiree: msg.sender,
            projectId: _projectId,
            amountRetired: _amount,
            retirementDate: block.timestamp,
            retirementHash: retirementHash
        });
        
        retirementDetails[certId] = RetirementDetails({
            retirementReason: _retirementReason,
            beneficiary: _beneficiary,
            metadataURI: _metadataURI
        });
        
        retireeRetirements[msg.sender].push(certId);
        projectRetirements[_projectId] += _amount;
        retiredByUser[_projectId][msg.sender] += _amount;
        
        _safeMint(msg.sender, certId);
        _setTokenURI(certId, _metadataURI);
        
        emit CreditsRetired(certId, msg.sender, _projectId, _amount);
        emit CertificateMinted(certId, msg.sender);

        (uint256 totalCount, uint256 totalCO2Retired, uint256[] memory certificateIds) = this.generateRetirementReport(msg.sender);
        emit RetirementReport(msg.sender, totalCount, totalCO2Retired, certificateIds);
        
        return certId;
    }
    
    function batchRetireCredits(
        uint256[] memory _projectIds,
        uint256[] memory _amounts,
        string memory _retirementReason,
        string memory _beneficiary,
        string memory _metadataURI
    ) external nonReentrant returns (uint256[] memory) {
        require(_projectIds.length == _amounts.length, "Array length mismatch");
        require(_projectIds.length > 0 && _projectIds.length <= 20, "Invalid array length");
        
        uint256[] memory certificateIds = new uint256[](_projectIds.length);
        
        for (uint256 i = 0; i < _projectIds.length; i++) {
            certificateIds[i] = _retireInternal(
                _projectIds[i],
                _amounts[i],
                _retirementReason,
                _beneficiary,
                _metadataURI
            );
        }

        (uint256 totalCount, uint256 totalCO2Retired, uint256[] memory allCertificateIds) = this.generateRetirementReport(msg.sender);
        emit RetirementReport(msg.sender, totalCount, totalCO2Retired, allCertificateIds);
        
        return certificateIds;
    }
    
    function _retireInternal(
        uint256 _projectId,
        uint256 _amount,
        string memory _retirementReason,
        string memory _beneficiary,
        string memory _metadataURI
    ) internal returns (uint256) {
        require(_amount > 0, "Amount must be greater than 0");
        
        bytes32 retirementHash = keccak256(
            abi.encodePacked(msg.sender, _projectId, _amount, block.timestamp, _certificateIdCounter)
        );
        
        require(!usedRetirementHashes[retirementHash], "Hash collision");
        usedRetirementHashes[retirementHash] = true;
        
        carbonCreditToken.safeTransferFrom(
            msg.sender,
            address(0x000000000000000000000000000000000000dEaD),
            _projectId,
            _amount,
            ""
        );
        
        _certificateIdCounter++;
        uint256 certId = _certificateIdCounter;
        
        retirementInfo[certId] = RetirementInfo({
            retiree: msg.sender,
            projectId: _projectId,
            amountRetired: _amount,
            retirementDate: block.timestamp,
            retirementHash: retirementHash
        });
        
        retirementDetails[certId] = RetirementDetails({
            retirementReason: _retirementReason,
            beneficiary: _beneficiary,
            metadataURI: _metadataURI
        });
        
        retireeRetirements[msg.sender].push(certId);
        projectRetirements[_projectId] += _amount;
        retiredByUser[_projectId][msg.sender] += _amount;
        
        _safeMint(msg.sender, certId);
        _setTokenURI(certId, _metadataURI);
        
        emit CreditsRetired(certId, msg.sender, _projectId, _amount);
        emit CertificateMinted(certId, msg.sender);
        
        return certId;
    }
    
    function updateProjectInfo(
        uint256 _projectId,
        string memory _projectName,
        string memory _projectCategory,
        string memory _country,
        uint256 _vintageYear
    ) external onlyOwner {
        projectInfo[_projectId] = ProjectInfo({
            projectName: _projectName,
            projectCategory: _projectCategory,
            country: _country,
            vintageYear: _vintageYear
        });
    }
    
    function getRetirementInfo(uint256 _certificateId) 
        external 
        view 
        returns (RetirementInfo memory) 
    {
        require(_ownerOf(_certificateId) != address(0), "Certificate does not exist");
        return retirementInfo[_certificateId];
    }
    
    function getRetirementDetails(uint256 _certificateId) 
        external 
        view 
        returns (RetirementDetails memory) 
    {
        require(_ownerOf(_certificateId) != address(0), "Certificate does not exist");
        return retirementDetails[_certificateId];
    }
    
    function getRetireeRetirements(address _retiree) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return retireeRetirements[_retiree];
    }
    
    function getProjectTotalRetired(uint256 _projectId) 
        external 
        view 
        returns (uint256) 
    {
        return projectRetirements[_projectId];
    }
    
    function getUserProjectRetirement(address _user, uint256 _projectId) 
        external 
        view 
        returns (uint256) 
    {
        return retiredByUser[_projectId][_user];
    }
    
    function verifyCertificate(uint256 _certificateId) 
        external 
        view 
        returns (
            bool isValid,
            address retiree,
            uint256 projectId,
            uint256 amount,
            uint256 date,
            bytes32 hash
        ) 
    {
        if (_ownerOf(_certificateId) == address(0)) {
            return (false, address(0), 0, 0, 0, bytes32(0));
        }
        
        RetirementInfo memory info = retirementInfo[_certificateId];
        
        return (true, info.retiree, info.projectId, info.amountRetired, info.retirementDate, info.retirementHash);
    }
    
    function generateRetirementReport(address _retiree)
        external
        view
        returns (uint256 totalCount, uint256 totalCO2Retired, uint256[] memory certificateIds)
    {
        certificateIds = retireeRetirements[_retiree];
        totalCount = certificateIds.length;
        
        for (uint256 i = 0; i < certificateIds.length; i++) {
            totalCO2Retired += retirementInfo[certificateIds[i]].amountRetired;
        }
        
        return (totalCount, totalCO2Retired, certificateIds);
    }
    
    function totalCertificates() external view returns (uint256) {
        return _certificateIdCounter;
    }
    
    function updateCarbonCreditToken(address _newToken) external onlyOwner {
        carbonCreditToken = IERC1155(_newToken);
    }
}