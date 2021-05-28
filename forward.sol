pragma solidity ^0.4.24;

library libutil {
    function address_index(address _value, address[] _array)
        internal
        pure
        returns (uint256 i)
    {
        // Find the index of the value in the array
        for (i = 0; i < _array.length; i++) {
            if (_value == _array[i]) return i;
        }
    }

    function address_exist(address _value, address[] _array)
        internal
        pure
        returns (bool)
    {
        // Have found the value in array
        for (uint256 i = 0; i < _array.length; i++) {
            if (_value == _array[i]) return true;
        }
        // Not in
        return false;
    }

    function address_remove(address _value, address[] storage _array)
        internal
        returns (bool)
    {
        uint256 _index = address_index(_value, _array);
        // Not found
        if (_index >= _array.length) return false;

        // Move the last element to the index of array
        _array[_index] = _array[_array.length - 1];

        // Also delete the last element
        delete _array[_array.length - 1];
        _array.length--;
        return true;
    }

    function remove(uint256 _value, uint256[] storage _array)
        internal
        returns (bool)
    {
        uint256 _index = index(_value, _array);
        // Not found
        if (_index >= _array.length) return false;

        // Move the last element to the index of array
        _array[_index] = _array[_array.length - 1];

        // Also delete the last element
        delete _array[_array.length - 1];
        _array.length--;
        return true;
    }

    function index(uint256 _value, uint256[] _array)
        internal
        pure
        returns (uint256 i)
    {
        // Find the index of the value in the array
        for (i = 0; i < _array.length; i++) {
            if (_value == _array[i]) return i;
        }
    }

    function exist(uint256 _value, uint256[] _array)
        internal
        pure
        returns (bool)
    {
        // Have found the value in array
        for (uint256 i = 0; i < _array.length; i++) {
            if (_value == _array[i]) return true;
        }
        // Not in
        return false;
    }

    function isNull(uint256[] _array) internal pure returns (bool) {
        if (_array.length == 0) return true;
        for (uint256 i = 0; i < _array.length; i++) {
            if (0 != _array[i]) return false;
        }

        return true;
    }
}

library element {
    /* operation type :
        0. noop
        1. add member
        2. del member
        3. set majority
        4. call something
    */
    enum OperationType {Noop, AddMember, DelMember, SetMajority, CallContract}

    /* proposal status :
        0. Processing
        1. already agreed
        2. already declined
    */
    enum ProposalStatus {Processing, Agreed, Declined}

    struct VoterList {
        address[] agreed_address;
        address[] declined_address;
    }

    struct OperationInfo {
        address target_address;
        uint256 favorite_num;
        bytes byte_code;
    }

    struct VoteInfo {
        ProposalStatus status;
        OperationInfo op_info;
        address[] agreed_address;
        address[] declined_address;
    }

    struct VoteManager {
        uint256[] idxs;
        mapping(uint256 => VoteInfo) idx_infos;
    }
}

contract Forward {
    // Majority number of members
    uint256 majority;
    // All total number of members
    uint256 total;
    // Incremental index
    uint256 index;
    // All members store here
    mapping(address => bool) members;
    // Index to operation type
    mapping(uint256 => element.OperationType) index_types;
    //How many user vote for address's foward call with same params.
    element.VoteManager bytecode_manager;
    //Manager modifing memberes
    element.VoteManager add_member_manager;
    element.VoteManager del_member_manager;
    element.VoteManager majority_manager;

    /*  Dup event
        id is the universe id for every request 
        user is the msg.sender that send duplicated 

       duptype=1 for add member, dst is the member's address proposaled to add
       duptype=2 for delete member, dst is the member's address proposaled to delete
       duptype=3 for set majority, detail is the proposal majority num
       duptype=4 for set call someting, dst is target contract,detail is bytecode
    */
    event Dup(uint256 indexed id, address indexed user);
    event CallProposal(uint256 indexed id, address indexed, bytes);
    event Called(uint256 indexed id, address indexed, bytes);
    event CallDeclined(uint256 indexed id, address indexed, bytes);
    event AddMemberProposal(uint256 indexed id, address indexed);
    event MemberAdded(uint256 indexed id, address indexed);
    event MemberAddDeclined(uint256 indexed id, address indexed);
    event DelMemberProposal(uint256 indexed id, address indexed);
    event MemberDeled(uint256 indexed id, address indexed);
    event MemberDelDeclined(uint256 indexed id, address indexed);
    event MajorityProposal(uint256 indexed id, uint256 indexed);
    event MajorityChanged(uint256 indexed id, uint256 indexed);
    event MajorityChangDeclined(uint256 indexed id, uint256 indexed);

    event ProposalDeled(uint256 indexed id);
    event ProposalClosed(uint256 indexed id, uint256 indexed);

    constructor() public {
        members[msg.sender] = true;
        majority = 1;
        total = 1;
        index = 1;
    }

    modifier onlyMember {
        require(members[msg.sender] == true, "only member");
        _;
    }

    function is_member(address _user) external view returns (bool) {
        return members[_user];
    }

    function get_majority() external view returns (uint256) {
        return majority;
    }

    function get_total_num() external view returns (uint256) {
        return total;
    }

    function get_type_by_id(uint256 _id) external view returns (uint256) {
        return uint256(index_types[_id]);
    }

    function internal_delete(uint256 _id, element.VoteManager storage _manager)
        internal
    {
        delete _manager.idx_infos[_id].agreed_address;
        delete _manager.idx_infos[_id].declined_address;
        delete _manager.idx_infos[_id];
        libutil.remove(_id, _manager.idxs);
        delete index_types[_id];
        emit ProposalDeled(_id);
    }

    function internal_check_delete(
        uint256 _id,
        element.VoteManager storage _manager
    ) internal {
        if (
            _manager.idx_infos[_id].status != element.ProposalStatus.Processing
        ) {
            internal_delete(_id, _manager);
        }
    }

    function internal_revoke(uint256 _id, element.VoteManager storage _manager)
        internal
    {
        if (
            !libutil.exist(_id, _manager.idxs) ||
            _manager.idx_infos[_id].status != element.ProposalStatus.Processing
        ) {
            return;
        }
        bool a =
            libutil.address_remove(
                msg.sender,
                _manager.idx_infos[_id].agreed_address
            );
        bool b =
            libutil.address_remove(
                msg.sender,
                _manager.idx_infos[_id].declined_address
            );
        if (a || b) {
            if (
                _manager.idx_infos[_id].agreed_address.length +
                    _manager.idx_infos[_id].declined_address.length ==
                0
            ) {
                internal_delete(_id, _manager);
                emit ProposalDeled(_id);
            }
        }
    }

    function revoke_by_index(uint256 _id) external onlyMember {
        element.OperationType ty = index_types[_id];
        if (ty == element.OperationType.AddMember) {
            internal_revoke(_id, add_member_manager);
        } else if (ty == element.OperationType.DelMember) {
            internal_revoke(_id, del_member_manager);
        } else if (ty == element.OperationType.SetMajority) {
            internal_revoke(_id, majority_manager);
        } else if (ty == element.OperationType.CallContract) {
            internal_revoke(_id, bytecode_manager);
        }
    }

    function get_info_by_index(uint256 _id) external view returns (bytes) {
        element.OperationType ty = index_types[_id];
        if (ty == element.OperationType.AddMember) {
            return
                abi.encode(
                    uint256(ty),
                    add_member_manager.idx_infos[_id].status,
                    add_member_manager.idx_infos[_id].agreed_address,
                    add_member_manager.idx_infos[_id].declined_address,
                    add_member_manager.idx_infos[_id].op_info.target_address
                );
        } else if (ty == element.OperationType.DelMember) {
            return
                abi.encode(
                    uint256(ty),
                    del_member_manager.idx_infos[_id].status,
                    del_member_manager.idx_infos[_id].agreed_address,
                    del_member_manager.idx_infos[_id].declined_address,
                    del_member_manager.idx_infos[_id].op_info.target_address
                );
        } else if (ty == element.OperationType.SetMajority) {
            return
                abi.encode(
                    uint256(ty),
                    majority_manager.idx_infos[_id].status,
                    majority_manager.idx_infos[_id].agreed_address,
                    majority_manager.idx_infos[_id].declined_address,
                    majority_manager.idx_infos[_id].op_info.favorite_num
                );
        } else if (ty == element.OperationType.CallContract) {
            return
                abi.encode(
                    uint256(ty),
                    bytecode_manager.idx_infos[_id].status,
                    bytecode_manager.idx_infos[_id].agreed_address,
                    bytecode_manager.idx_infos[_id].declined_address,
                    bytecode_manager.idx_infos[_id].op_info.target_address,
                    bytecode_manager.idx_infos[_id].op_info.byte_code
                );
        }
    }

    function delete_by_index(uint256 _id) external onlyMember {
        element.OperationType ty = index_types[_id];
        if (ty == element.OperationType.AddMember) {
            internal_check_delete(_id, add_member_manager);
        } else if (ty == element.OperationType.DelMember) {
            internal_check_delete(_id, del_member_manager);
        } else if (ty == element.OperationType.SetMajority) {
            internal_check_delete(_id, majority_manager);
        } else if (ty == element.OperationType.CallContract) {
            internal_check_delete(_id, bytecode_manager);
        }
    }

    function add_one_list(address _voter, address[] storage _addrs)
        internal
        returns (uint256)
    {
        for (uint256 j = 0; j < _addrs.length; j++) {
            // Already sent
            if (_addrs[j] == _voter) {
                return 0;
            }
        }
        _addrs.push(_voter);
        return _addrs.length;
    }

    function add_voter_list(
        bool _pro_con_flag,
        address _voter,
        element.VoteInfo storage _vinfo
    ) internal returns (uint256, uint256) {
        uint256 agree_count;
        uint256 decline_count;
        if (_pro_con_flag) {
            agree_count = add_one_list(_voter, _vinfo.agreed_address);
        } else {
            decline_count = add_one_list(_voter, _vinfo.declined_address);
        }
        return (agree_count, decline_count);
    }

    function check_vote_info(
        element.OperationType _op_type,
        element.OperationInfo _oinfo,
        element.OperationInfo storage _saved_info
    ) internal view returns (bool) {
        if (
            _op_type == element.OperationType.AddMember ||
            _op_type == element.OperationType.DelMember
        ) {
            if (_oinfo.target_address == _saved_info.target_address) {
                return true;
            }
        } else if (_op_type == element.OperationType.SetMajority) {
            if (_oinfo.favorite_num == _saved_info.favorite_num) {
                return true;
            }
        } else if (_op_type == element.OperationType.CallContract) {
            if (
                _oinfo.target_address == _saved_info.target_address &&
                keccak256(_oinfo.byte_code) == keccak256(_saved_info.byte_code)
            ) {
                return true;
            }
        }
        return false;
    }

    /// @return (founded index,agreed array len, declined array len)
    function commom_function(
        element.VoteManager storage _manager,
        element.OperationType _op_type,
        bool _pro_con_flag,
        element.OperationInfo memory _op_info
    )
        internal
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        uint256 agree_count = 0;
        uint256 decline_count = 0;
        uint256 found_id = 0;
        uint256[] memory idxs = _manager.idxs;

        for (uint256 i = 0; i < idxs.length; i++) {
            element.VoteInfo storage vinfo = _manager.idx_infos[idxs[i]];
            if (check_vote_info(_op_type, _op_info, vinfo.op_info)) {
                if (vinfo.status != element.ProposalStatus.Processing) {
                    emit ProposalClosed(idxs[i], uint256(vinfo.status));
                    return (uint256(-1), 0, 0);
                }

                (agree_count, decline_count) = add_voter_list(
                    _pro_con_flag,
                    msg.sender,
                    vinfo
                );
                // agree or decline dup
                if (agree_count + decline_count == 0) {
                    emit Dup(idxs[i], msg.sender);
                    return (0, 0, 0);
                }
                found_id = idxs[i];
            }
        }

        // first proposal
        if (agree_count + decline_count == 0) {
            _manager.idxs.push(index);
            _manager.idx_infos[index].op_info = _op_info;
            _manager.idx_infos[index].status = element
                .ProposalStatus
                .Processing;
            (agree_count, decline_count) = add_voter_list(
                _pro_con_flag,
                msg.sender,
                _manager.idx_infos[index]
            );
            found_id = index;
            index_types[found_id] = _op_type;
            index++;
        }

        if (agree_count == majority) {
            _manager.idx_infos[found_id].status = element.ProposalStatus.Agreed;
        } else if (decline_count == majority) {
            _manager.idx_infos[found_id].status = element
                .ProposalStatus
                .Declined;
        }
        return (found_id, agree_count, decline_count);
    }

    /// pro_cons_flag: true: agree , false: decline
    /// _user : address wanted be add
    function add_member(bool pro_cons_flag, address _user) public onlyMember {
        if (members[_user]) {
            return;
        }
        uint256 found_id;
        uint256 agree_count;
        uint256 decline_count;
        element.OperationInfo memory op;
        op.target_address = _user;

        (found_id, agree_count, decline_count) = commom_function(
            add_member_manager,
            element.OperationType.AddMember,
            pro_cons_flag,
            op
        );

        if (found_id == uint256(-1)) {
            return;
        }

        if (agree_count == 1) {
            emit AddMemberProposal(found_id, _user);
        }

        if (agree_count == majority) {
            members[_user] = true;
            total += 1;
            emit MemberAdded(found_id, _user);
        } else if (decline_count == majority) {
            emit MemberAddDeclined(found_id, _user);
        }
    }

    /// pro_cons_flag: true: agree , false: decline
    /// _user : address wanted be del
    function del_member(bool pro_cons_flag, address _user) public onlyMember {
        require(majority < total && total > 1, "Majority should <= total num");
        if (!members[_user]) {
            return;
        }
        uint256 found_id;
        uint256 agree_count;
        uint256 decline_count;
        element.OperationInfo memory op;
        op.target_address = _user;

        (found_id, agree_count, decline_count) = commom_function(
            del_member_manager,
            element.OperationType.DelMember,
            pro_cons_flag,
            op
        );

        if (found_id == uint256(-1)) {
            return;
        }

        if (agree_count == 1) {
            emit DelMemberProposal(found_id, _user);
        }

        if (agree_count == majority) {
            delete members[_user];
            total -= 1;
            emit MemberDeled(found_id, _user);
        } else if (decline_count == majority) {
            emit MemberDelDeclined(found_id, _user);
        }
    }

    /// pro_cons_flag: true: agree , false: decline
    /// _num : majority wanted be set
    function set_majority(bool pro_cons_flag, uint256 _num) public onlyMember {
        require(_num <= total && _num > 0, "majority must less than total num");
        if (majority == _num) {
            return;
        }
        uint256 found_id;
        uint256 agree_count;
        uint256 decline_count;
        element.OperationInfo memory op;
        op.favorite_num = _num;

        (found_id, agree_count, decline_count) = commom_function(
            majority_manager,
            element.OperationType.SetMajority,
            pro_cons_flag,
            op
        );

        if (found_id == uint256(-1)) {
            return;
        }

        if (agree_count == 1) {
            emit MajorityProposal(found_id, _num);
        }

        if (agree_count == majority) {
            majority = _num;
            emit MajorityChanged(found_id, _num);
        } else if (decline_count == majority) {
            emit MajorityChangDeclined(found_id, _num);
        }
    }

    /// pro_cons_flag: true: agree , false: decline
    /// _target : target address tobe call
    /// bytes : forward call content
    function fcall(
        bool pro_cons_flag,
        address _target,
        bytes
    ) external onlyMember {
        uint256 found_id;
        uint256 agree_count;
        uint256 decline_count;
        // bytes format: offset + size + content
        bytes memory rdata;

        assembly {
            rdata := mload(0x40)
            // set new free space's offset
            mstore(
                0x40,
                add(
                    rdata,
                    and(
                        add(add(sub(calldatasize, 0x44), 0x40), 0x1f),
                        not(0x1f)
                    )
                )
            )
            mstore(rdata, sub(calldatasize, 0x44))
            calldatacopy(add(rdata, 0x20), 0x44, sub(calldatasize, 0x44))
        }

        element.OperationInfo memory op;
        op.target_address = _target;
        op.byte_code = rdata;

        (found_id, agree_count, decline_count) = commom_function(
            bytecode_manager,
            element.OperationType.CallContract,
            pro_cons_flag,
            op
        );

        emit CallDeclined(0xff, _target, rdata);

        if (found_id == uint256(-1)) {
            return;
        }

        if (agree_count == 1) {
            emit CallProposal(found_id, _target, rdata);
        }

        if (agree_count == majority) {
            emit Called(found_id, _target, rdata);
            assembly {
                let ptr := mload(0x40)
                calldatacopy(ptr, 0x44, sub(calldatasize, 0x44))
                switch call(
                    gas,
                    _target,
                    0,
                    ptr,
                    sub(calldatasize, 0x44),
                    ptr,
                    0
                )
                    case 0 {
                        revert(0, 0)
                    }
            }
        } else if (decline_count == majority) {
            emit CallDeclined(found_id, _target, rdata);
        }
    }
}
