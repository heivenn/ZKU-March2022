// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.4.16 <0.9.0;

/// @title Storage for an unsigned integer
/// @dev Stores and retrieves a number from a variable
contract HelloWorld {
    uint number;

    /**
     * @dev Store value in variable
     * @param num value to store
     */
    function set(uint num) public {
        number = num;
    }

    /**
     * @dev Return value 
     * @return value of 'number'
     */
    function get() public view returns (uint){
        return number;
    }
}