//SPDX-License-Identifier: Unlicensed

pragma solidity ^0.6.4;

import "@openzeppelin/contracts/utils/Strings.sol";


import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/SignedSafeMath.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "../structs/Decimal.sol";
import "../structs/Shape.sol";
import "../structs/Modulation.sol";
import "../structs/TinyBox.sol";
import "../structs/HSL.sol";

import "./SVGBuffer.sol";
import "./Random.sol";
import "./Utils.sol";
import "./Decimal.sol";
import "./Colors.sol";
import "./StringUtilsLib.sol";
import "../structs/Decimal.sol";

library SVG {
    using Math for uint256;
    using SafeMath for uint256;
    using SignedSafeMath for int256;
    using StringUtilsLib for *;
    using SVGBuffer for bytes;
    using Random for bytes32[];
    using DecimalUtils for *;
    using Utils for *;
    using Colors for *;
    using Strings for *;

    /**
     * @dev render a rectangle SVG tag
     * @param shape object
     */
    function _rect(TinyBox memory box, uint256 shapeIndex, Shape memory shape, ShapeModulation memory shapeMods, bool animated) internal view returns (string memory) {
        // empty buffer for the SVG markup
        bytes memory buffer = new bytes(8192);

        // build the rect tag
        buffer.append('<rect x="');
        buffer.append(shape.position[0].toString());
        buffer.append('" y="');
        buffer.append(shape.position[1].toString());
        buffer.append('" width="');
        buffer.append(shape.size[0].toString());
        buffer.append('" height="');
        buffer.append(shape.size[1].toString());
        buffer.append('" rx="');
        buffer.append(shapeMods.radius.toString());
        buffer.append('" transform-origin="');
        buffer.append(shapeMods.origin[0].toString());
        buffer.append(' ');
        buffer.append(shapeMods.origin[1].toString());
        buffer.append('" style="fill:');
        buffer.append(shape.color.toString());
        buffer.append(";fill-opacity:");
        buffer.append(shapeMods.opacity.toString());
        buffer.append('" transform="rotate(');
        buffer.append(shapeMods.rotation.toString());
        buffer.append(')translate(');
        buffer.append(shapeMods.offset[0].toString());
        buffer.append(' ');
        buffer.append(shapeMods.offset[1].toString());
        buffer.append(')skewX(');
        buffer.append(shapeMods.skew[0].toString());
        buffer.append(')skewY(');
        buffer.append(shapeMods.skew[1].toString());
        buffer.append(')scale(');
        buffer.append(shapeMods.scale[0].toString());
        buffer.append(' ');
        buffer.append(shapeMods.scale[1].toString());
        buffer.append(')">');
        buffer.append(animated ? _generateAnimation(box, shape, shapeIndex) : '');
        buffer.append('</rect>');
        return buffer.toString();
    }

    /**
     * @dev render an animate SVG tag
     */
    function _animate(string memory attribute, string memory values, string memory duration) internal pure returns (string memory) {
        return string(abi.encodePacked('<animate attributeName="', attribute, '" values="', values, '" dur="', duration, '" repeatCount="indefinite" />'));
    }

    /**
     * @dev render a animateTransform SVG tag
     */
    function _animateTransform(string memory attribute, string memory typeVal, string memory values, string memory duration) internal pure returns (string memory) {
        return string(abi.encodePacked('<animateTransform attributeName="', attribute, '" attributeType="XML" type="', typeVal, '" values="', values, '" dur="', duration, '" repeatCount="indefinite" />'));
    }

    /**
     * @dev render a animateTransform SVG tag
     */
    function _animateTransform(string memory attribute, string memory typeVal, string memory values, string memory keyTimes, string memory duration) internal pure returns (string memory) {
        return string(abi.encodePacked('<animateTransform attributeName="', attribute, '" attributeType="XML" type="', typeVal, '" values="', values, '" keyTimes="', keyTimes, '" dur="', duration, '" repeatCount="indefinite" />'));
    }

    /**
     * @dev render a animateTransform SVG tag
     */
    function _animateTransformSpline(string memory attribute, string memory typeVal, string memory values, string memory keySplines, string memory keyTimes, string memory duration) internal pure returns (string memory) {
        return string(abi.encodePacked('<animateTransform attributeName="', attribute, '" attributeType="XML" type="', typeVal, '" calcMode="spline" values="', values, '" keySplines="', keySplines, '" keyTimes="', keyTimes, '" dur="', duration, '" repeatCount="indefinite" />'));
    }
    
    /**
     * @dev render the header of the SVG markup
     * @return header string
     */
    function _generateHeader() internal pure returns (string memory) {
        string memory xmlVersion = '<?xml version="1.0" encoding="UTF-8"?>';
        string memory doctype = '<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">';
        string memory openingTag = '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="100%" height="100%" viewBox="0 0 2400 2400" style="stroke-width:0;background-color:#121212">';

        return string(abi.encodePacked(xmlVersion, doctype, openingTag));
    }

    /**
     * @dev render the header of the SVG markup
     * @return header string
     */
    function _generateBody(TinyBox memory box) internal pure returns (string memory) {
        string memory metadataTag = '<metadata>';
        string memory metadataEndTag = '</metadata>';
        string memory animationTag = '<animation>';
        string memory animationEndTag = '</animation>';
        string memory symbols = '<symbol id="quad3"><symbol id="quad2"><symbol id="quad1"><symbol id="quad0">';

        return string(abi.encodePacked(metadataTag, animationTag, uint256(box.animation).toString(), animationEndTag, metadataEndTag, symbols));
    }

    /**
     * @dev render the footer string for mirring effects
     * @param switches for each mirroring stage
     * @param mirrorPositions for generator settings
     * @param scale for each mirroring stage
     * @return footer string
     */
    function _generateFooter(
        bool[3] memory switches,
        Decimal[3] memory mirrorPositions,
        Decimal memory scale
    ) internal view returns (string memory) {
        bytes memory buffer = new bytes(8192);

        string[3] memory scales = ['-1 1', '-1 -1', '1 -1'];
        string[7] memory template = [
            '<g>',
            '<g transform="scale(',
            ') translate(',
            ')">',
            '<use xlink:href="#quad',
            '"/></g>',
            '</symbol>'
        ];

        for (uint256 s = 0; s < 3; s++) {
            // loop through mirroring effects
            buffer.append(template[6]);

            if (!switches[s]) {
                // turn off this level of mirroring
                // add a scale transform
                buffer.append(template[0]);
                // denote what quad the transform should be used for
                buffer.append(template[4]);
                
                if (s > 0)
                    buffer.append(Strings.toString(uint256(s + 1)));
                buffer.append(template[5]);
            } else {
                for (uint8 i = 0; i < 4; i++) {
                    // loop through transforms
                    if (i == 0) buffer.append(template[0]);
                    else {
                        buffer.append(template[1]);
                        buffer.append(scales[i - 1]);
                        buffer.append(template[2]);
                        string memory value = mirrorPositions[s].toString();
                        if (i <= 2) buffer.append('-');
                        buffer.append(i <= 2 ? value : '0');
                        buffer.append(' ');
                        if (i >= 2) buffer.append('-');
                        buffer.append(i >= 2 ? value : '0');
                        buffer.append(template[3]);
                    }
                    // denote what quad the transforms should be used for
                    buffer.append(template[4]);
                    buffer.append(Strings.toString(s));
                    buffer.append(template[5]);
                }
            }
        }
        // add final scaling
        buffer.append(template[6]);
        buffer.append(template[1]);
        buffer.append(scale.toString());
        buffer.append(' ');
        buffer.append(scale.toString());
        buffer.append(template[3]);
        buffer.append(template[4]);
        buffer.append('3');
        buffer.append(template[5]);
        buffer.append("</svg>");
        return buffer.toString();
    }

    

    /**
     * @dev select the animation
     * @param box object to base animation around
     * @param shapeIndex index of the shape to animate
     * @return mod struct of modulator values
     */
    function _generateAnimation(
        TinyBox memory box,
        Shape memory shape,
        uint256 shapeIndex
    ) internal view returns (string memory) {
        // empty buffer for the SVG markup
        bytes memory buffer = new bytes(8192);
        
        // select animation based on animation id
        uint256 animation = box.animation;
        if (animation == 0) {
            //Rounding corners
            buffer.append(_animate("rx","0;100;0","10s"));
            // BYPASS _animate
            //buffer.append('<animate attributeName="rx" values="0;100;0" dur="10s" repeatCount="indefinite" />');
        } else if (animation == 1) {
            // Spin
            buffer.append(_animateTransform(
                "transform",
                "rotate",
                "0 60 70 ; 90 60 70 ; 270 60 70 ; 360 60 70",
                "0 ; 0.1 ; 0.9 ; 1",
                "10s"
            ));
            // BYPASS _animateTransform
            //buffer.append('<animateTransform attributeName="transform" attributeType="XML" type="rotate" calcMode="spline" values="0 60 70 ; 270 60 70 ; 270 60 70 ; 360 60 70 ; 360 60 70" keyTimes="0 ; 0.55 ; 0.75 ; 0.9 ; 1" keySplines="0.5 0 0.75 1 ; 0.5 0 0.5 1 ; 0.5 0 0.75 1 ; 0.5 0 0.5 1" dur="10s" repeatCount="indefinite" />');
        } else if (animation == 2) {
            // squash n stretch
            uint256 div = 7;
            for (uint256 i = 0; i < 2; i++) {
                bytes memory values = new bytes(1000);
                uint256 size = uint256(shape.size[i]);
                values.append(size.toString());
                values.append(";");
                if (i==0) values.append(size.sub(size.div(div)).toString());
                else values.append(size.add(size.div(div)).toString());
                values.append(";");
                values.append(size.toString());
                values.append(";");
                if (i==0) values.append(size.add(size.div(div)).toString());
                else values.append(size.sub(size.div(div)).toString());
                values.append(";");
                values.append(size.toString());
                if (i==0) buffer.append(_animate("width",values.toString(),"10s"));
                else buffer.append(_animate("height",values.toString(),"10s"));
            }
        } else if (animation == 3) {
            // skew
            buffer.append(_animateTransform(
                "transform",
                "skewX",
                "0 ; 50 ; 0",
                "10s"
            ));
        } else if (animation == 4) {
            // jiggle
            bytes memory values = new bytes(10000);
            uint256 amp = 20;
            uint256 posX = uint256(shape.position[0]);
            uint256 posY = uint256(shape.position[1]);
            // values.append(posX.toString());
            // values.append(" ");
            // values.append(posY.toString());
            // values.append(";");
            // values.append(posX.sub(amp).toString());
            // values.append(" ");
            // values.append(posY.sub(amp).toString());
            // values.append(";");
            // values.append(posX.toString());
            // values.append(" ");
            // values.append(posY.toString());
            // values.append(";");
            // values.append(posX.add(amp).toString());
            // values.append(" ");
            // values.append(posY.add(amp).toString());
            // values.append(";");
            // values.append(posX.toString());
            // values.append(" ");
            // values.append(posY.toString());
            buffer.append(_animateTransform("transform","translate",values.toString(),"10s"));
        }  else if (animation == 5) {
            // snap spin
            buffer.append(_animateTransformSpline(
                "transform",
                "rotate",
                "0 200 200 ; 270 200 200 ; 270 200 200 ; 360 200 200 ; 360 200 200",
                "0.5 0 0.75 1 ; 0.5 0 0.5 1 ; 0.5 0 0.75 1 ; 0.5 0 0.5 1",
                "0 ; 0.55 ; 0.75 ; 0.9 ; 1",
                "10s"
            ));
        } else if (animation == 6) {
            // spread
            // TODO: use different hold points in values and times in keyTimes
            buffer.append(_animateTransformSpline(
                "transform",
                "rotate",
                "0 200 200 ; 270 200 200 ; 270 200 200 ; 360 200 200 ; 360 200 200",
                "0.5 0 0.75 1 ; 0.5 0 0.5 1 ; 0.5 0 0.75 1 ; 0.5 0 0.5 1",
                "0 ; 0.55 ; 0.75 ; 0.9 ; 1",
                "10s"
            ));
        } else if (animation == 7) {
            // drop
            bytes memory values = new bytes(10000);
            values.append(shape.position[0].toString());
            values.append(" ");
            values.append(shape.position[1].toString());
            values.append(" ; ");
            values.append(shape.position[0].toString());
            values.append(" ");
            values.append(shape.position[1].sub(500).toString());
            buffer.append(_animateTransformSpline(
                "transform",
                "translate",
                values.toString(),
                "0.2 0 0.5 1 ; 0.5 0 0.5 1",
                "0 ; 1",
                "10s"
            ));
        }

        return buffer.toString();
    }
}
