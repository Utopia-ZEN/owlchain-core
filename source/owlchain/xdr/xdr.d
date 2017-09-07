module owlchain.xdr.xdr;

import owlchain.xdr.type;
import owlchain.xdr.xdrDataInputStream;
import owlchain.xdr.xdrDataOutputStream;
import std.traits;

template xdr(T)
{
    ubyte[] serialize(ref const T from)
    {
        XdrDataOutputStream stream = new XdrDataOutputStream();
        T.encode(stream, from);
        return stream.data;
    }
    void serialize(XdrDataOutputStream stream, ref const T from)
    {
        T.encode(stream, from);
    }
    string print(ref const T from)
    {
        import std.digest.sha;
        XdrDataOutputStream stream = new XdrDataOutputStream();
        T.encode(stream, from);
        return toHexString(stream.data)[0 .. 9];
    }
    void decode(XdrDataInputStream stream, ref T[] to)
    {
        int size = stream.readInt();
        to.length = size;
        for (int i = 0; i < size; i++)
        {
            to[i] = T.decode(stream);
        }
    }
    void decode(XdrDataInputStream stream, ref T to)
    {
        to = T.decode(stream);
    }
    XdrDataInputStream decode(ref ubyte[] source, ref T[] to)
    {
        XdrDataInputStream stream = new XdrDataInputStream(source);
        int size = stream.readInt();
        to.length = size;
        for (int i = 0; i < size; i++)
        {
            to[i] = T.decode(stream);
        }
        return stream;
    }
    XdrDataInputStream decode(ref ubyte[] source, ref T to)
    {
        XdrDataInputStream stream = new XdrDataInputStream(source);
        to = T.decode(stream);
        return stream;
    }
}

template xdr2(T, U)
{
    void convert(ref T from, ref U to)
    {
        XdrDataOutputStream ostream = new XdrDataOutputStream();
        T.encode(ostream, from);
        XdrDataInputStream istream = new XdrDataInputStream(ostream.data);
        to = U.decode(istream);
    }
}
