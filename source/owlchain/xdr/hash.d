module owlchain.xdr.hash;

import owlchain.xdr.type;
import owlchain.xdr.xdrDataInputStream;
import owlchain.xdr.xdrDataOutputStream;

struct Hash
{
    ubyte[] hash;

    static Hash opCall(ubyte[] v)
    {
        Hash h;
        h.hash = v.dup;
        return h;
    }


    static Hash opCall(const ubyte[] v)
    {
        Hash h;
        h.hash = v.dup;
        return h;
    }

    static Hash opCall(Hash s)
    {
        Hash t;
        t.hash = s.hash.dup;
        return t;
    }

    static Hash opCall(ref Hash s)
    {
        Hash t;
        t.hash = s.hash.dup;
        return t;
    }

    static Hash opCall(ref const Hash s)
    {
        Hash t;
        t.hash = s.hash.dup;
        return t;
    }

    ref Hash opAssign(Hash s)
    {
        hash = s.hash.dup;
        return this;
    }

    ref Hash opAssign(ref Hash s)
    {
        hash = s.hash.dup;
        return this;
    }

    ref Hash opAssign(ref const Hash s)
    {
        hash = s.hash.dup;
        return this;
    }

    static void encode(XdrDataOutputStream stream, ref const Hash encodedHash)
    {
        stream.write(encodedHash.hash);
    }

    static Hash decode(XdrDataInputStream stream)
    {
        Hash decodedHash;
        ubyte[] temp;
        temp.length = 32;
        stream.read(temp);
        decodedHash.hash = temp;
        return decodedHash;
    }
}