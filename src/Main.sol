// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title CarbonCreditToken
 * @dev Optimized for Foundry - reduced struct sizes to avoid stack too deep
 */
contract CarbonCreditToken is ERC1155, AccessControl, ReentrancyGuard {
    
    bytes32 public constant REGISTRY_ROLE = keccak256("REGISTRY_ROLE");
    bytes32 public constant AUDITOR_ROLE = keccak256("AUDITOR_ROLE");
    bytes32 public constant CONSULTANT_ROLE = keccak256("CONSULTANT_ROLE");
    
    uint256 private _projectIdCounter;
    
    enum ProjectCategory {
        RenewableEnergy,
        Reforestation,
        EnergyEfficiency,
        WasteManagement,
        OceanConservation,
        SoilCarbon,
        Other
    }
    
    enum GasType {
        CO2,
        Methane,
        CO,
        N2O,
        Other
    }
    
    enum ProjectStatus {
        Submitted,
        UnderAudit,
        Approved,
        Rejected,
        Active,
        Completed
    }
    
    // Split into smaller structs to avoid stack too deep
    struct ProjectBasicInfo {
        uint256 projectId;
        string projectName;
        address projectDeveloper;
        address consultant;
        address auditor;
        ProjectCategory category;
        GasType primaryGasType;
    }
    
    struct ProjectDetails {
        string country;
        string registry;
        uint256 vintageYear;
        ProjectStatus status;
        uint256 createdAt;
        uint256 approvedAt;
    }
    
    struct ProjectCredits {
        uint256 totalCreditsIssued;
        uint256 totalCreditsRetired;
        string verificationDocHash;
        string monitoringReportHash;
    }
    
    // Mappings
    mapping(uint256 => ProjectBasicInfo) public projectBasicInfo;
    mapping(uint256 => ProjectDetails) public projectDetails;
    mapping(uint256 => ProjectCredits) public projectCredits;
    mapping(uint256 => bool) public projectExists;
    mapping(address => uint256[]) public developerProjects;
    mapping(address => uint256) private _totalUserBalance;
    mapping(uint256 => address[]) public projectAuditors;

    // Events
    event ProjectSubmitted(
        uint256 indexed projectId,
        address indexed developer,
        string projectName,
        ProjectCategory category
    );
    
    event ProjectApproved(
        uint256 indexed projectId,
        address indexed auditor,
        uint256 approvedAt
    );
    
    event ProjectRejected(
        uint256 indexed projectId,
        address indexed auditor,
        string reason
    );
    
    // Modified to match Backend expectation: CreditMinted(address indexed to, uint256 amount, uint256 projectId)
    event CreditMinted(
        address indexed to,
        uint256 amount,
        uint256 projectId
    );
    
    event AuditorAssigned(
        uint256 indexed projectId,
        address indexed auditor
    );
    
    event VerificationHashUpdated(
        uint256 indexed projectId,
        string verificationHash
    );

    // Backend compatibility event
    event Transfer(address indexed from, address indexed to, uint256 value);
    
    constructor(string memory uri) ERC1155(uri) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(REGISTRY_ROLE, msg.sender);
    }
    
    function submitProject(
        string memory _projectName,
        ProjectCategory _category,
        GasType _primaryGasType,
        string memory _country,
        string memory _registry,
        address _consultant,
        string memory _verificationDocHash,
        uint256 _vintageYear
    ) external returns (uint256) {
        _projectIdCounter++;
        uint256 newProjectId = _projectIdCounter;
        
        projectBasicInfo[newProjectId] = ProjectBasicInfo({
            projectId: newProjectId,
            projectName: _projectName,
            projectDeveloper: msg.sender,
            consultant: _consultant,
            auditor: address(0),
            category: _category,
            primaryGasType: _primaryGasType
        });
        
        projectDetails[newProjectId] = ProjectDetails({
            country: _country,
            registry: _registry,
            vintageYear: _vintageYear,
            status: ProjectStatus.Submitted,
            createdAt: block.timestamp,
            approvedAt: 0
        });
        
        projectCredits[newProjectId] = ProjectCredits({
            totalCreditsIssued: 0,
            totalCreditsRetired: 0,
            verificationDocHash: _verificationDocHash,
            monitoringReportHash: ""
        });
        
        projectExists[newProjectId] = true;
        developerProjects[msg.sender].push(newProjectId);
        
        emit ProjectSubmitted(newProjectId, msg.sender, _projectName, _category);
        
        return newProjectId;
    }
    
    function assignAuditor(uint256 _projectId, address _auditor) 
        external 
        onlyRole(REGISTRY_ROLE) 
    {
        require(projectExists[_projectId], "Project does not exist");
        require(hasRole(AUDITOR_ROLE, _auditor), "Address is not an auditor");
        
        projectBasicInfo[_projectId].auditor = _auditor;
        projectDetails[_projectId].status = ProjectStatus.UnderAudit;
        projectAuditors[_projectId].push(_auditor);
        
        emit AuditorAssigned(_projectId, _auditor);
    }
    
    function submitVerificationHash(
        uint256 _projectId,
        string memory _verificationHash
    ) external onlyRole(AUDITOR_ROLE) {
        require(projectExists[_projectId], "Project does not exist");
        require(
            projectBasicInfo[_projectId].auditor == msg.sender,
            "Not assigned auditor"
        );
        
        projectCredits[_projectId].verificationDocHash = _verificationHash;
        
        emit VerificationHashUpdated(_projectId, _verificationHash);
    }
    
    function approveProject(uint256 _projectId) 
        external 
        onlyRole(REGISTRY_ROLE) 
    {
        require(projectExists[_projectId], "Project does not exist");
        require(
            projectDetails[_projectId].status == ProjectStatus.UnderAudit,
            "Project not under audit"
        );
        
        projectDetails[_projectId].status = ProjectStatus.Approved;
        projectDetails[_projectId].approvedAt = block.timestamp;
        
        emit ProjectApproved(_projectId, projectBasicInfo[_projectId].auditor, block.timestamp);
    }
    
    function rejectProject(uint256 _projectId, string memory _reason) 
        external 
        onlyRole(REGISTRY_ROLE) 
    {
        require(projectExists[_projectId], "Project does not exist");
        
        projectDetails[_projectId].status = ProjectStatus.Rejected;
        
        emit ProjectRejected(_projectId, projectBasicInfo[_projectId].auditor, _reason);
    }
    
    function mintCredits(
        uint256 _projectId,
        uint256 _amount,
        string memory _monitoringReportHash
    ) external onlyRole(REGISTRY_ROLE) nonReentrant {
        require(projectExists[_projectId], "Project does not exist");
        ProjectStatus status = projectDetails[_projectId].status;
        require(
            status == ProjectStatus.Approved || status == ProjectStatus.Active,
            "Project not approved"
        );
        require(_amount > 0, "Amount must be greater than 0");
        
        address developer = projectBasicInfo[_projectId].projectDeveloper;
        
        _mint(developer, _projectId, _amount, "");
        
        projectCredits[_projectId].totalCreditsIssued += _amount;
        projectCredits[_projectId].monitoringReportHash = _monitoringReportHash;
        projectDetails[_projectId].status = ProjectStatus.Active;
        
        emit CreditMinted(developer, _amount, _projectId);
    }
    
    function updateRetiredCredits(uint256 _projectId, uint256 _amount) 
        external 
    {
        require(projectExists[_projectId], "Project does not exist");
        projectCredits[_projectId].totalCreditsRetired += _amount;
    }
    
    // View functions - return data in chunks
    function getProjectBasicInfo(uint256 _projectId) 
        external 
        view 
        returns (ProjectBasicInfo memory) 
    {
        require(projectExists[_projectId], "Project does not exist");
        return projectBasicInfo[_projectId];
    }
    
    // Renamed from getProjectDetails to avoid conflict with backend expectation
    function getProjectDetailsStruct(uint256 _projectId) 
        external 
        view 
        returns (ProjectDetails memory) 
    {
        require(projectExists[_projectId], "Project does not exist");
        return projectDetails[_projectId];
    }

    // Backend compatibility function
    function getProjectDetails(uint256 _projectId)
        external
        view
        returns (string memory name, string memory location, uint256 credits)
    {
        require(projectExists[_projectId], "Project does not exist");
        name = projectBasicInfo[_projectId].projectName;
        location = projectDetails[_projectId].country;
        credits = projectCredits[_projectId].totalCreditsIssued;
    }
    
    function getProjectCredits(uint256 _projectId) 
        external 
        view 
        returns (ProjectCredits memory) 
    {
        require(projectExists[_projectId], "Project does not exist");
        return projectCredits[_projectId];
    }
    
    function getDeveloperProjects(address _developer) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return developerProjects[_developer];
    }
    
    function getProjectAuditors(uint256 _projectId)
        external
        view
        returns (address[] memory)
    {
        return projectAuditors[_projectId];
    }
    
    function getTotalProjects() external view returns (uint256) {
        return _projectIdCounter;
    }
    
    function addRegistry(address _registry) external onlyRole(DEFAULT_ADMIN_ROLE) {
        grantRole(REGISTRY_ROLE, _registry);
    }
    
    function addAuditor(address _auditor) external onlyRole(DEFAULT_ADMIN_ROLE) {
        grantRole(AUDITOR_ROLE, _auditor);
    }
    
    function addConsultant(address _consultant) external onlyRole(DEFAULT_ADMIN_ROLE) {
        grantRole(CONSULTANT_ROLE, _consultant);
    }
    
    function removeRegistry(address _registry) external onlyRole(DEFAULT_ADMIN_ROLE) {
        revokeRole(REGISTRY_ROLE, _registry);
    }
    
    function removeAuditor(address _auditor) external onlyRole(DEFAULT_ADMIN_ROLE) {
        revokeRole(AUDITOR_ROLE, _auditor);
    }
    
    function updateProjectStatus(uint256 _projectId, ProjectStatus _newStatus)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(projectExists[_projectId], "Project does not exist");
        projectDetails[_projectId].status = _newStatus;
    }
    
    function setURI(string memory newuri) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setURI(newuri);
    }
    
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC1155, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    // Override _update to track total user balance for backend compatibility
    function _update(address from, address to, uint256[] memory ids, uint256[] memory values)
        internal
        override(ERC1155)
    {
        super._update(from, to, ids, values);

        for (uint256 i = 0; i < ids.length; ++i) {
            uint256 value = values[i];
            if (from != address(0)) {
                _totalUserBalance[from] -= value;
            }
            if (to != address(0)) {
                _totalUserBalance[to] += value;
            }
            
            // Emit legacy Transfer event for backend compatibility
            emit Transfer(from, to, value);
        }
    }

    // Backend compatibility function for total balance
    function balanceOf(address owner) public view returns (uint256) {
        return _totalUserBalance[owner];
    }
}