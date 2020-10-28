//SPDX-License-Identifier: Unlicensed

pragma solidity ^0.6.4;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/SignedSafeMath.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/SafeCast.sol";


import "./Utils.sol";
import "./SVGBuffer.sol";
import "../structs/Decimal.sol";

library DecimalUtils {
    using SafeMath for uint256;
    using SignedSafeMath for int256;
    using SVGBuffer for *;
    using Strings for *;
    using Utils for *;
    using SafeCast for *;

    // convert a Decimal to a string
    function toString(Decimal memory number) internal view returns (string memory) {
        bytes memory buffer = new bytes(8192);
        buffer.append(
            FixidityLib.fromFixed(
                number.value
            ).toString()
        );
        buffer.append(".");
        buffer.append(
            FixidityLib.fromFixed(
                FixidityLib.fractional(
                    FixidityLib.abs(number.value)
                ), 24 - number.decimals).toString()
        );
        return buffer.toString();
    }

    // add two decimals
    function add(Decimal memory a, Decimal memory b) internal pure returns (Decimal memory result) {
        // decide the order to add by decimal length
        (Decimal memory x, Decimal memory y) = a.decimals > b.decimals ? (a, b) : (b, a);
        // scale less precise value to match larger decimals
        int256 scaled = y.value.mul(int256(10)**(x.decimals - y.decimals));
        // add scaled values and return a new decimal
        return Decimal(scaled.add(x.value), x.decimals);
    }
}
