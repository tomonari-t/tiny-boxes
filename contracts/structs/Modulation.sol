//SPDX-License-Identifier: Unlicensed
pragma solidity ^0.6.4;

struct Modulation {
    uint256 color;
    uint256 opacity;
    uint256 hatch;
    uint256 stack;
    uint8[4] spacing;
    uint8[4] sizeRange;
    uint8[2] position;
    uint8[2] size;
    uint8[3] mirror;
}