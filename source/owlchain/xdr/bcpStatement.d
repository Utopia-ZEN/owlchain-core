module owlchain.xdr.bcpStatement;

import owlchain.xdr.type;
import owlchain.xdr.nodeID;
import owlchain.xdr.hash;
import owlchain.xdr.bcpBallot;
import owlchain.xdr.bcpStatementType;
import owlchain.xdr.bcpNomination;
import owlchain.xdr.xdrDataInputStream;
import owlchain.xdr.xdrDataOutputStream;

struct BCPStatement
{
    NodeID nodeID;
    uint64 slotIndex;
    BCPStatementPledges pledges;

    static void encode(XdrDataOutputStream stream, ref const BCPStatement encodedStatement)
    {
        NodeID.encode(stream, encodedStatement.nodeID);
        stream.writeUint64(encodedStatement.slotIndex);
        BCPStatementPledges.encode(stream, encodedStatement.pledges);
    }

    static BCPStatement decode(XdrDataInputStream stream)
    {
        BCPStatement decodedStatement;
        decodedStatement.nodeID = NodeID.decode(stream);
        decodedStatement.slotIndex = stream.readUint64();
        decodedStatement.pledges = BCPStatementPledges.decode(stream);
        return decodedStatement;
    }
}

struct BCPStatementPledges
{
    BCPStatementType type;
    BCPStatementPrepare prepare;
    BCPStatementConfirm confirm;
    BCPStatementExternalize externalize;
    BCPNomination nominate;

    static void encode(XdrDataOutputStream stream, ref const BCPStatementPledges encodedStatementPledges)
    {
        encodeBCPStatementType(stream, encodedStatementPledges.type);

        switch (encodedStatementPledges.type)
        {
        case BCPStatementType.BCP_ST_PREPARE:
            BCPStatementPrepare.encode(stream,
                    encodedStatementPledges.prepare);
            break;
        case BCPStatementType.BCP_ST_CONFIRM:
            BCPStatementConfirm.encode(stream,
                    encodedStatementPledges.confirm);
            break;
        case BCPStatementType.BCP_ST_EXTERNALIZE:
            BCPStatementExternalize.encode(stream,
                    encodedStatementPledges.externalize);
            break;
        case BCPStatementType.BCP_ST_NOMINATE:
            BCPNomination.encode(stream,
                    encodedStatementPledges.nominate);
            break;
        default:
        }
    }

    static BCPStatementPledges decode(XdrDataInputStream stream)
    {
        BCPStatementPledges decodedStatementPledges;

        decodedStatementPledges.type = decodeBCPStatementType(stream);

        switch (decodedStatementPledges.type)
        {
        case BCPStatementType.BCP_ST_PREPARE:
            decodedStatementPledges.prepare = BCPStatementPrepare.decode(stream);
            break;
        case BCPStatementType.BCP_ST_CONFIRM:
            decodedStatementPledges.confirm = BCPStatementConfirm.decode(stream);
            break;
        case BCPStatementType.BCP_ST_EXTERNALIZE:
            decodedStatementPledges.externalize = BCPStatementExternalize.decode(stream);
            break;
        case BCPStatementType.BCP_ST_NOMINATE:
            decodedStatementPledges.nominate = BCPNomination.decode(stream);
            break;
        default:
            break;
        }
        return decodedStatementPledges;
    }
}

struct BCPStatementPrepare
{
    Hash quorumSetHash;         //  D
    BCPBallot ballot;           //  b
    BCPBallot prepared;         //  p
    uint32 nC;                  //  p
    BCPBallot preparedPrime;    //  c.n
    uint32 nH;                  //  h.n

    static void encode(XdrDataOutputStream stream, ref const BCPStatementPrepare encodedStatementPrepare)
    {
        Hash.encode(stream, encodedStatementPrepare.quorumSetHash);
        BCPBallot.encode(stream, encodedStatementPrepare.ballot);
        BCPBallot.encode(stream, encodedStatementPrepare.prepared);
        BCPBallot.encode(stream, encodedStatementPrepare.preparedPrime);
        stream.writeUint32(encodedStatementPrepare.nC);
        stream.writeUint32(encodedStatementPrepare.nH);
    }

    static BCPStatementPrepare decode(XdrDataInputStream stream)
    {
        BCPStatementPrepare decodedStatementPrepare;
        decodedStatementPrepare.quorumSetHash = Hash.decode(stream);
        decodedStatementPrepare.ballot = BCPBallot.decode(stream);
        decodedStatementPrepare.prepared = BCPBallot.decode(stream);
        decodedStatementPrepare.preparedPrime = BCPBallot.decode(stream);
        decodedStatementPrepare.nC = stream.readUint32();
        decodedStatementPrepare.nH = stream.readUint32();
        return decodedStatementPrepare;
    }
}

struct BCPStatementConfirm
{
    BCPBallot ballot;           //  b
    uint32 nPrepared;           //  p.n
    uint32 nCommit;             //  c.n
    uint32 nH;                  //  h.n
    Hash quorumSetHash;         //  D

    static void encode(XdrDataOutputStream stream, ref const BCPStatementConfirm encodedStatementConfirm)
    {
        BCPBallot.encode(stream, encodedStatementConfirm.ballot);
        stream.writeUint32(encodedStatementConfirm.nPrepared);
        stream.writeUint32(encodedStatementConfirm.nCommit);
        stream.writeUint32(encodedStatementConfirm.nH);
        Hash.encode(stream, encodedStatementConfirm.quorumSetHash);
    }

    static BCPStatementConfirm decode(XdrDataInputStream stream)
    {
        BCPStatementConfirm decodedStatementConfirm;
        decodedStatementConfirm.ballot = BCPBallot.decode(stream);
        decodedStatementConfirm.nPrepared = stream.readUint32();
        decodedStatementConfirm.nCommit = stream.readUint32();
        decodedStatementConfirm.nH = stream.readUint32();
        decodedStatementConfirm.quorumSetHash = Hash.decode(stream);
        return decodedStatementConfirm;
    }

}

struct BCPStatementExternalize
{
    BCPBallot commit;           //  c
    uint32 nH;                  //  h.n
    Hash commitQuorumSetHash;   //  D

    static void encode(XdrDataOutputStream stream,
            ref const BCPStatementExternalize encodedStatementExternalize)
    {
        BCPBallot.encode(stream, encodedStatementExternalize.commit);
        stream.writeUint32(encodedStatementExternalize.nH);
        Hash.encode(stream, encodedStatementExternalize.commitQuorumSetHash);
    }

    static BCPStatementExternalize decode(XdrDataInputStream stream)
    {
        BCPStatementExternalize decodedStatementExternalize;
        decodedStatementExternalize.commit = BCPBallot.decode(stream);
        decodedStatementExternalize.nH = stream.readUint32();
        decodedStatementExternalize.commitQuorumSetHash = Hash.decode(stream);
        return decodedStatementExternalize;
    }
}
