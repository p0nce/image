// Written in the D programming language.
/**
RGB the type.

Authors:    Manu Evans
Copyright:  Copyright (c) 2019, Manu Evans.
License:    $(WEB boost.org/LICENSE_1_0.txt, Boost License 1.0)
*/

module wg.color.rgb;

public import wg.color.rgb.colorspace;
public import wg.color.rgb.format;

import wg.color.xyz : XYZ;
import wg.util.traits : isFloatingPoint;
import wg.util.normint;

import std.typecons : tuple;
import std.meta : AliasSeq;

/**
Determine if T is an RGB color type.
*/
enum IsRGB(T) = is(T == RGB!fmt, string fmt);

/**
Get the canonical format string for an RGB type.
*/
template FormatString(T) if (is(T == RGB!fmt, string fmt))
{
    enum FormatString = makeFormatString(T.Format);
}

/**
RGB colour type.
*/
struct RGB(string format)
{
    /// make the format data available
    enum Format = parseRGBFormat(format);
    ///
    enum ColorSpace = parseRGBColorSpace(Format.colorSpace);

    ///
    alias ParentColor = XYZ;

    ///
    enum isOperable = (Format.flags & RGBFormatDescriptor.Flags.AllSameFormat) &&
                      (Format.flags & RGBFormatDescriptor.Flags.AllAligned) &&
                      (Format.flags & RGBFormatDescriptor.Flags.AllSameSize);

    static if (isOperable)
    {
        /// format can have hard members
        alias ComponentType = TypeFor!(Format.components[0].format, Format.components[0].bits, Format.components[0].fracBits);

        ///
        enum hasComponent(char c) = mixin("is(typeof(" ~ c ~ "))");

        /// the argument type used for construction and methods
        static if (isFloatingPoint!ComponentType)
            alias ArgType = ComponentType;
        else
            alias ArgType = ComponentType.IntType;

        /// mixin the color component struct members
        static foreach (c; Format.components)
            mixin(ComponentType.stringof ~ " " ~ ComponentName[c.type] ~ ';');

        /// Construct a color from RGB and optional alpha values.
        this(ArgType r, ArgType g, ArgType b, ArgType a = 0)
        {
            foreach (c; AliasSeq!('r','g','b','a'))
                mixin(componentExpression("this._ = ComponentType(_);", c));
            static if (hasComponent!'l')
                this.l = cast(ComponentType)toMonochrome!ColorSpace(cast(float)ComponentType(r), cast(float)ComponentType(g), cast(float)ComponentType(b));
        }

        /// Construct a color from a luminance and optional alpha value.
        this(ArgType l, ArgType a = 0)
        {
            foreach (c; AliasSeq!('l','r','g','b'))
                mixin(componentExpression("this._ = ComponentType(l);", c));
            static if (hasComponent!'a')
                this.a = ComponentType(a);
        }
    }
    else
    {
        /// format needs bit-unpacking; components are properties
        pragma(msg, "TODO: fabricate properties for the bitpacked members...");
    }

    /**
    Return the RGB tristimulus values as a tuple.
    These will always be ordered (R, G, B).
    Any color channels not present will be 0.
    */
    @property auto tristimulus() const
    {
        static if (hasComponent!'l')
            return tuple(l, l, l);
        else
        {
            static if (!hasComponent!'r')
                enum r = ComponentType(0);
            static if (!hasComponent!'g')
                enum g = ComponentType(0);
            static if (!hasComponent!'b')
                enum b = ComponentType(0);
            return tuple(r, g, b);
        }
    }

    ///
    unittest
    {
        // tristimulus returns tuple of R, G, B
        static assert(RGB!"bgr"(255, 128, 10).tristimulus == tuple(NormalizedInt!ubyte(255), NormalizedInt!ubyte(128), NormalizedInt!ubyte(10)));
    }

    /**
    Return the RGB tristimulus values + alpha as a tuple.
    These will always be ordered (R, G, B, A).
    */
    @property auto tristimulusWithAlpha() const
    {
        static if (!hasComponent!'a')
            enum a = ComponentType(0);
        return tuple(tristimulus.expand, a);
    }

    ///
    unittest
    {
        // tristimulusWithAlpha returns tuple of R, G, B, A
        static assert(RGB!"bgra"(255, 128, 10, 80).tristimulusWithAlpha == tuple(NormalizedInt!ubyte(255), NormalizedInt!ubyte(128), NormalizedInt!ubyte(10), NormalizedInt!ubyte(80)));
    }
}

///
unittest
{
    RGB!"rgba" pixel;

    static assert(is(typeof(pixel.r) == NormalizedInt!ubyte));
    static assert(is(typeof(pixel.g) == NormalizedInt!ubyte));
    static assert(is(typeof(pixel.b) == NormalizedInt!ubyte));
    static assert(is(typeof(pixel.a) == NormalizedInt!ubyte));

    RGB!"la_f32_f32" pixel2;

    static assert(is(typeof(pixel2.l) == float));
    static assert(is(typeof(pixel2.a) == float));
}

package(wg.color):

// trim the `^gamma` from colorspace id strings
private const(char)[] exGamma(return scope const(char)[] cs)
{
    foreach (i; 0 .. cs.length)
        if (cs[i] == '^')
            return cs[0 .. i];
    return cs;
}

To convertColorImpl(To, string format)(RGB!format color) if (is(To == RGB!fmt, string fmt))
{
    alias From = typeof(color);

    auto src = color.tristimulusWithAlpha;

    static if (From.ColorSpace.id[] == To.ColorSpace.id[])
    {
        // color space is the same, just do type conversion
        static if (To.isOperable)
        {
            alias CT = To.ComponentType;
            return To(cast(CT)src[0], cast(CT)src[1], cast(CT)src[2], cast(CT)src[3]);
        }
        else
        {
            // each component does something different...
            static assert(false, "TODO: inoperable (compressed) RGB types");
        }
    }
    else
    {
        // unpack the working values
        // TODO: this could surely be done with a lookup table!
        float r = cast(float)src[0];
        float g = cast(float)src[1];
        float b = cast(float)src[2];

        static if (From.ColorSpace.gamma[] != "1")
        {
            alias FromGamma = GammaFuncPair!(From.ColorSpace.gamma);
            r = FromGamma.toLinear(r);
            g = FromGamma.toLinear(g);
            b = FromGamma.toLinear(b);
        }
        static if (exGamma(From.ColorSpace.id)[] != exGamma(To.ColorSpace.id)[])
        {
            import wg.util.math : multiply;

            // TODO: we should do better chromatic adaptation...

            enum mat = multiply(From.ColorSpace.rgbToXyz, To.ColorSpace.xyzToRgb);
            float[3] v = multiply(mat, [r, g, b]);
            r = v[0]; g = v[1]; b = v[2];
        }
        static if (To.ColorSpace.gamma[] != "1")
        {
            alias ToGamma = GammaFuncPair!(To.ColorSpace.gamma);
            r = ToGamma.toGamma(r);
            g = ToGamma.toGamma(g);
            b = ToGamma.toGamma(b);
        }

        // convert and return the output
        static if (To.isOperable)
        {
            alias CT = To.ComponentType;
            return To(cast(CT)r, cast(CT)g, cast(CT)b, cast(CT)src[3]);
        }
        else
        {
            // each component does something different...
            static assert(false, "TODO: inoperable (compressed) RGB types");
        }
    }
}
unittest
{
    import wg.color : RGBA8;

    // test RGB format conversions
    alias UnsignedRGB = RGB!("rgb");
    alias SignedRGBX = RGB!("rgbx_s8_s8_s8_s8");
    alias FloatRGBA = RGB!("rgba_f32_f32_f32_f32");

    static assert(convertColorImpl!(UnsignedRGB)(SignedRGBX(0x20,0x30,-10)) == UnsignedRGB(0x40,0x60,0));
    static assert(convertColorImpl!(UnsignedRGB)(FloatRGBA(1,0.5,0,1)) == UnsignedRGB(0xFF,0x80,0));
    static assert(convertColorImpl!(FloatRGBA)(UnsignedRGB(0xFF,0x80,0)) == FloatRGBA(1,float(0x80)/float(0xFF),0,0));
    static assert(convertColorImpl!(FloatRGBA)(SignedRGBX(127,-127,-128)) == FloatRGBA(1,-1,-1,0));

    static assert(convertColorImpl!(UnsignedRGB)(convertColorImpl!(FloatRGBA)(UnsignedRGB(0xFF,0x80,0))) == UnsignedRGB(0xFF,0x80,0));

    // test greyscale conversion
    alias UnsignedL = RGB!"l";
    static assert(convertColorImpl!(UnsignedL)(UnsignedRGB(0xFF,0x20,0x40)) == UnsignedL(82));

    // test linear conversion
    alias lRGBA = RGB!("rgba_16_16_16_16_sRGB^1");
    static assert(convertColorImpl!(lRGBA)(RGBA8(0xFF, 0x80, 0x02, 0x40)) == lRGBA(0xFFFF, 0x3742, 0x0028, 0x4040));

    // test gamma conversion
    alias gRGBA = RGB!("rgba_s8_s8_s8_s8_sRGB^2.2");
    static assert(convertColorImpl!(gRGBA)(RGBA8(0xFF, 0x80, 0x01, 0xFF)) == gRGBA(0x7F, 0x3F, 0x03, 0x7F));
}

To convertColorImpl(To, string format)(RGB!format color) if (is(To == XYZ))
{
    import wg.util.math : multiply;

    alias Src = typeof(color);
    alias CS = Src.ColorSpace;

    // unpack the working values
    // TODO: this could surely be done with a lookup table!
    auto rgb = color.tristimulus;
    float r = cast(float)rgb[0];
    float g = cast(float)rgb[1];
    float b = cast(float)rgb[2];

    static if (CS.gamma[] != "1")
    {
        alias Gamma = GammaFuncPair!(CS.gamma);
        r = Gamma.toLinear(r);
        g = Gamma.toLinear(g);
        b = Gamma.toLinear(b);
    }

    // transform to XYZ
    float[3] v = multiply(CS.rgbToXyz, [r, g, b]);
    return To(v[0], v[1], v[2]);
}
unittest
{
    // TODO: needs approx ==
}

To convertColorImpl(To)(XYZ color) if(is(To == RGB!fmt, string fmt))
{
    import wg.util.math : multiply;

    alias CS = To.ColorSpace;

    float[3] v = multiply(CS.xyzToRgb, [ color.X, color.Y, color.Z ]);

    static if (CS.gamma[] != "1")
    {
        alias Gamma = GammaFuncPair!(CS.gamma);
        v[0] = Gamma.toGamma(v[0]);
        v[1] = Gamma.toGamma(v[1]);
        v[2] = Gamma.toGamma(v[2]);
    }

    static if (To.isOperable)
    {
        alias CT = To.ComponentType;
        return To(cast(CT)v[0], cast(CT)v[1], cast(CT)v[2]);
    }
    else
    {
        // each component does something different...
        static assert(false, "TODO: inoperable (compressed) RGB types");
    }
}
unittest
{
    // TODO: needs approx ==
}

void registerRGB()
{
    import wg.image.format : registerImageFormatFamily;
    import wg.image.imagebuffer : ImageBuffer;

    static bool getImageParams(const(char)[] format, uint width, uint height, out ImageBuffer image) nothrow @nogc @safe
    {
        import wg.color.rgb.format;

        RGBFormatDescriptor desc;
        RGBFormatDescriptor.ComponentDesc[6] components;

        string error = parseRGBFormat(format, desc, components);

        if (error)
            return false;

        image.width = width;
        image.height = height;
        image.bitsPerBlock = desc.bits;
        image.rowPitch = (width*desc.bits + 7) / 8;

        return true;
    }

    registerImageFormatFamily("rgb", &getImageParams);
}


private:

enum char[] ComponentName = [ 'r', 'g', 'b', 'a', 'l', 'e', 'x' ];

template TypeFor(RGBFormatDescriptor.Format format, size_t bits, size_t frac)
{
    static if (format == RGBFormatDescriptor.Format.NormInt || format == RGBFormatDescriptor.Format.SignedNormInt)
        alias TypeFor = NormalizedInt!(IntForSize!(bits, format == RGBFormatDescriptor.Format.SignedNormInt));
    else static if (format == RGBFormatDescriptor.Format.FloatingPoint)
        alias TypeFor = FloatForSize!bits;
    else static if (format == RGBFormatDescriptor.Format.UnsignedInt || format == RGBFormatDescriptor.Format.SignedInt)
        alias TypeFor = IntForSize!(bits, format == RGBFormatDescriptor.Format.SignedInt);
    else static if (format == RGBFormatDescriptor.Format.FixedPoint || format == RGBFormatDescriptor.Format.SignedFixedPoint)
        alias TypeFor = FixedPoint!(IntForSize!(bits, format == RGBFormatDescriptor.Format.SignedFixedPoint), frac);
    else static if (format == RGBFormatDescriptor.Format.Exponent || format == RGBFormatDescriptor.Format.Mantissa)
        alias TypeFor = IntForSize!(bits, false);
    else
        static assert("Invalid format and bits!");
}

template IntForSize(size_t size, bool signed)
{
    static if (size == 8)
    {
        static if (signed)
            alias IntForSize = byte;
        else
            alias IntForSize = ubyte;
    }
    else static if (size == 16)
    {
        static if (signed)
            alias IntForSize = short;
        else
            alias IntForSize = ushort;
    }
    else static if (size == 32)
    {
        static if (signed)
            alias IntForSize = int;
        else
            alias IntForSize = uint;
    }
    else static if (size == 64)
    {
        static if (signed)
            alias IntForSize = long;
        else
            alias IntForSize = ulong;
    }
    else
        static assert("Invalid size!");
}

template FloatForSize(size_t size)
{
    static if (size == 16)
        alias FloatForSize = float16;
    else static if (size == 32)
        alias FloatForSize = float;
    else static if (size == 64)
        alias FloatForSize = double;
    else
        static assert("Invalid size!");
}

// TODO: need a fixed point type
struct FixedPoint(I, int frac)
{
    alias IntType = I;

    alias asFloat this;

    float asFloat() const { assert(false); }
    void asFloat(float f) { assert(false); }

    private I val;
}

// TODO: need a float16 type
struct float16
{
    alias asFloat this;

    float asFloat() const { assert(false); }
    void asFloat(float f) { assert(false); }

    private ushort f;
}

// build mixin code to perform expresions per-element
string componentExpression(string expression, char component, string op = null)
{
    char[256] buffer;
    size_t o = 0;
    foreach (i; 0 .. expression.length)
    {
        if (expression[i] == '_')
            buffer[o++] = component;
        else if (expression[i] == '#')
        {
            buffer[o .. o + op.length] = op[];
            o += op.length;
        }
        else
            buffer[o++] = expression[i];
    }
    return "static if (hasComponent!'" ~ component ~ "')\n\t" ~ buffer[0 .. o].idup;
}
