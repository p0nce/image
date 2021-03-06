// Written in the D programming language.
/**
Image transformations.

Authors:    Manu Evans
Copyright:  Copyright (c) 2019, Manu Evans.
License:    $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/

module wg.image.transform;

import wg.image;
import wg.image.imagebuffer;

///
enum isImageBuffer(T) = is(T == ImageBuffer) || is(T == Image!U, U);

// it's possible to do certain loss-less and opaque transforms on images

///
Image crop(Image)(ref Image image, uint left, uint right, uint top, uint bottom) if (isImageBuffer!Image)
{
    assert(left % image.blockWidth == 0 && right % image.blockHeight == 0 &&
           top % image.blockWidth == 0 && bottom % image.blockHeight == 0);
    assert((image.bitsPerBlock & 7) == 0);
    assert(right >= left && bottom >= top);

    size_t t = top / image.blockHeight;
    size_t l = left / image.blockWidth;

    Image r = image;
    r.data += t*image.rowPitch + l*image.bitsPerBlock / 8;
    r.width = right - left;
    r.height = bottom - top;
    return r;
}

/// strip all metadata from an image buffer
Image stripMetadata(Image)(ref Image image) if (isImageBuffer!Image)
{
    Image r = image;

    // TODO: must find and keep the allocation metadata!
    r.metadata = null;
    return r;
}

// TODO: flip (in-place support?)
// TODO: flip (not in-place, buffer)
// TODO: rotation (requires destination image buffer, with matching format)

/// Map image elements 
auto map(Img, Fn)(auto ref Img image, auto ref Fn mapFunc)
{
    static struct Map
    {
        alias width = image.width;
        alias height = image.height;

        auto at(uint x, uint y) const
        {
            return mapFunc(image.at(x, y));
        }

    private:
        Img image;
        Fn mapFunc;
    }

    return Map(image);
}

/// Convert image format
auto convert(TargetFormat, Img)(auto ref Img image) if (isImage!Img && isValidPixelType!TargetFormat)
{
    import wg.color : convertColor;

    return image.map((ElementType!Img1 e) => e.convertColor!TargetFormat());
}

/// Convert image format
auto convert(TargetFormat)(auto ref ImageBuffer image) if (isValidPixelType!TargetFormat)
{
    import wg.color : convertColor;
    import wg.color.rgb : RGB;
    import wg.color.rgb.colorspace : RGBColorSpace, parseRGBColorSpace;
    import wg.color.rgb.convert : unpackRgbColor;
    import wg.color.rgb.format : RGBFormatDescriptor, parseRGBFormat, makeFormatString;
    import wg.image.format;

    // TODO: check if image is already the target format (and use a pass-through path)

    static struct DynamicConv
    {
        alias ConvertFunc = TargetFormat function(const(void)*, ref const(RGBFormatDescriptor) rgbDesc);

        this()(auto ref ImageBuffer image)
        {
            this.image = image;

            assert((image.bitsPerBlock & 7) == 0);
            elementBytes = image.bitsPerBlock / 8;

            const(char)[] format = image.format;
            switch(getFormatFamily(format))
            {
                case "rgb":
                    rgbFormat = parseRGBFormat(format);

                    static if (is(TargetFormat == RGB!targetFmt, string targetFmt))
                    {
                        if (rgbFormat.colorSpace[] == TargetFormat.Format.colorSpace[])
                        {
                            // make the unpack format string
                            static if (TargetFormat.Format.colorSpace[] != "sRGB")
                            {
                                // we need to inject the target colourspace into our desired format
                                enum unpackDesc = (RGBFormatDescriptor desc) {
                                    desc.colorSpace = TargetFormat.Format.colorSpace;
                                    return desc;
                                }(parseRGBFormat("rgba_f32_f32_f32_f32"));
                                enum string unpackFormat = makeFormatString(unpackDesc);
                            }
                            else
                                enum string unpackFormat = "rgba_f32_f32_f32_f32";

                            alias UnpackType = RGB!unpackFormat;

                            convFun = (const(void)* e, ref const(RGBFormatDescriptor) desc) {
                                float[4] unpack = unpackRgbColor(e[0 .. desc.bits/8], desc);
                                return UnpackType(unpack[0], unpack[1], unpack[2], unpack[3]).convertColor!TargetFormat();
                            };
                            break;
                        }
                        else
                        {
                            RGBColorSpace cs = parseRGBColorSpace(rgbFormat.colorSpace);

                            if (cs.red   == TargetFormat.ColorSpace.red   &&
                                cs.green == TargetFormat.ColorSpace.green &&
                                cs.blue  == TargetFormat.ColorSpace.blue  &&
                                cs.white == TargetFormat.ColorSpace.white)
                            {
                                // same colourspace, only gamma transformation
                                //convFun = ...
                                assert(false);
                            }
                        }
                    }

                    // unpack to linear
                    // convert to XYZ

                    assert(false);
                    //                    break;
                case "xyz":
                    import wg.color.xyz;
                    if (format == XYZ.stringof)
                        convFun = (const(void)* e, ref const(RGBFormatDescriptor)) => (*cast(const(XYZ)*)e).convertColor!TargetFormat();
                    else if (format == xyY.stringof)
                        convFun = (const(void)* e, ref const(RGBFormatDescriptor)) => (*cast(const(xyY)*)e).convertColor!TargetFormat();
                    else
                        assert(false, "Unknown XYZ format!");
                    break;
                default:
                    assert(false, "TODO: source format not supported: " ~ format);
            }
        }

        @property uint width() const { return image.width; }
        @property uint height() const { return image.height; }

        auto at(uint x, uint y) const
        {
            assert(x < width && y < height);

            size_t offset = y*image.rowPitch + x*elementBytes;
            return convFun(image.data + offset, rgbFormat);
        }

        ImageBuffer image;
        size_t elementBytes;
        ConvertFunc convFun;
        RGBFormatDescriptor rgbFormat;
    }

    return DynamicConv(image);
}
