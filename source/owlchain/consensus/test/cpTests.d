module owlchain.consensus.tests.cpTests;

import std.stdio;
import std.conv;
import std.typecons;
import std.digest.sha;
import std.algorithm : canFind;

import owlchain.xdr.type;
import owlchain.xdr.hash;
import owlchain.xdr.envelope;
import owlchain.xdr.value;
import owlchain.xdr.publicKey;
import owlchain.xdr.nodeID;
import owlchain.xdr.quorumSet;
import owlchain.xdr.ballot;
import owlchain.xdr.statement;
import owlchain.xdr.statementType;

import owlchain.crypto.keyUtils;

import owlchain.consensus.consensusProtocol;
import owlchain.consensus.consensusProtocolDriver;
import owlchain.consensus.slot;
import owlchain.consensus.localNode;

import owlchain.xdr.xdrDataOutputStream;

import owlchain.utils.globalChecks;

import core.stdc.stdint;

alias PriorityLookupDelegate = uint64 delegate(ref const NodeID);
alias HashCalculatorDelegate = uint64 delegate(ref const Value);

class TestCP : ConsensusProtocolDriver
{
public:
    ConsensusProtocol mConsensusProtocol;

    PriorityLookupDelegate mPriorityLookup;
    HashCalculatorDelegate mHashValueCalculator;

    QuorumSet[Hash] mQuorumSets;
    Envelope[] mEnvs;
    Value[uint64] mExternalizedValues;
    Ballot[][uint64] mHeardFromQuorums;

    ValueSet mExpectedCandidates;
    Value mCompositeValue;

    this(SecretKey secretKey, ref QuorumSet qSetLocal, bool isValidator = true)
    {
        mConsensusProtocol = new ConsensusProtocol(this, secretKey, isValidator, qSetLocal);

        mPriorityLookup = (ref const NodeID n) {
            return (n.publicKey == secretKey.getPublicKey()) ? 1000 : 1;
        };

        mHashValueCalculator = (ref const Value v)
        {
            return 0;
        };

        auto localQSet = mConsensusProtocol.getLocalQuorumSet();
        //writefln("Local Node QuorumSetHash(TestCP) : %s", toHexString(sha256Of(xdr!QuorumSet.serialize(localQSet))));
        storeQuorumSet(cast(QuorumSet)localQSet);
    }

    override void
    signEnvelope(ref Envelope)
    {

    }

    override bool
    verifyEnvelope(ref Envelope envelope)
    {
        return true;
    }

    void
    storeQuorumSet(QuorumSet qSet)
    {
        Hash qSetHash = Hash(sha256Of(xdr!QuorumSet.serialize(qSet)));
        //writefln("%s", toHexString(qSetHash.hash));

        mQuorumSets[qSetHash] = qSet;
   /*
        foreach (Hash h, QuorumSet q; mQuorumSets)
        {
            writefln("%s %s", toHexString(h.hash), toHexString( sha256Of(xdr!QuorumSet.serialize(q)) ));
        }
        writefln("");
    */
    }

    override ConsensusProtocolDriver.ValidationLevel
    validateValue(uint64 slotIndex, ref Value value)
    {
        return ConsensusProtocolDriver.ValidationLevel.kFullyValidatedValue;
    }

    override void
    ballotDidHearFromQuorum(uint64 slotIndex, ref Ballot ballot)
    {
        auto p = (slotIndex in mHeardFromQuorums);
        if (p !is null)
        {
            Ballot[] v;
            v ~= ballot;
            mHeardFromQuorums[slotIndex] = v;
        } else
        {
            mHeardFromQuorums[slotIndex] ~= ballot;
        }
    }

    override void
    valueExternalized(uint64 slotIndex, ref Value value)
    {
        auto p = (slotIndex in mExternalizedValues);
        if (p !is null)
        {
            throw new Exception("Value already externalized");
        }
        mExternalizedValues[slotIndex] = value;
    }

    override QuorumSetPtr
    getQSet(ref Hash qSetHash)
    {
        auto p = (qSetHash in mQuorumSets);
        if (p !is null)
        {
            return refCounted(mQuorumSets[qSetHash]);
        }
        RefCounted!(QuorumSet, RefCountedAutoInitialize.no) qSet;
        return qSet;
    }

    override void
    emitEnvelope(ref Envelope envelope)
    {
        mEnvs ~= envelope;
    }

    // used to test BallotProtocol and bypass nomination
    bool
    bumpState(uint64 slotIndex, ref Value v)
    {
        return mConsensusProtocol.getSlot(slotIndex, true).bumpState(v, true);
    }

    bool
    nominate(uint64 slotIndex, ref Value value, bool timedout)
    {
        return mConsensusProtocol.getSlot(slotIndex, true).nominate(value, value, timedout);
    }

    // only used by nomination protocol
    override Value
    combineCandidates(uint64 slotIndex, ref ValueSet candidates)
    {
        if (!(candidates == mExpectedCandidates))
        {
            writefln("REQUIRE : candidates != mExpectedCandidates");
        }
        if (!(mCompositeValue.value.length != 0))
        {
            writefln("REQUIRE : mCompositeValue empty");
        }

        return mCompositeValue;
    }

    // override the internal hashing scheme in order to make tests
    // more predictable.
    override uint64
    computeHashNode(uint64 slotIndex, ref Value prev, bool isPriority, int roundNumber, ref NodeID nodeID)
    {
        uint64 res;
        if (isPriority)
        {
            res = mPriorityLookup(nodeID);
        }
        else
        {
            res = 0;
        }
        return res;
    }

    // override the value hashing, to make tests more predictable.
    override uint64
    computeValueHash(uint64 slotIndex, ref Value prev, int roundNumber, ref Value value)
    {
        return mHashValueCalculator(value);
    }

    override void
    setupTimer(uint64 slotIndex, int timerID, long timeout, void delegate() cb)
    {
    }

    ref const(Value)
    getLatestCompositeCandidate(uint64 slotIndex)
    {
        return mConsensusProtocol.getSlot(slotIndex, true).getLatestCompositeCandidate();
    }

    void
    receiveEnvelope(ref Envelope envelope)
    {
        mConsensusProtocol.receiveEnvelope(envelope);
    }

    Slot
    getSlot(uint64 index)
    {
        return mConsensusProtocol.getSlot(index, false);
    }

    Envelope []
    getEntireState(uint64 index)
    {
        auto v = mConsensusProtocol.getSlot(index, false).getEntireCurrentState();
        return v;
    }

    Envelope
    getCurrentEnvelope(uint64 index, ref NodeID id)
    {
        Envelope [] envelopes = getEntireState(index);
        for (int idx = 0; idx < envelopes.length; idx++)
        {
            if (envelopes[idx].statement.nodeID == id) return envelopes[idx];
        }
        throw new Exception("not found");
    }
}

static Envelope
makeEnvelope(ref SecretKey secretKey, uint64 slotIndex,
             ref Statement statement)
{
    Envelope envelope;
    envelope.statement = statement;
    envelope.statement.nodeID = NodeID(secretKey.getPublicKey());
    envelope.statement.slotIndex = slotIndex;

    envelope.signature = secretKey.sign(xdr!Statement.serialize(envelope.statement));

    return envelope;
}

static Envelope
makeExternalize(ref SecretKey secretKey, ref Hash qSetHash,
                uint64 slotIndex, ref Ballot commitBallot, uint32 nH)
{
    Statement st;
    st.pledges.type = StatementType.CP_ST_EXTERNALIZE;
    auto ext = &st.pledges.externalize;
    ext.commit = commitBallot;
    ext.nH = nH;
    ext.commitQuorumSetHash = qSetHash;

    return makeEnvelope(secretKey, slotIndex, st);
}

static Envelope
makeConfirm(ref SecretKey secretKey, ref Hash qSetHash, uint64 slotIndex,
            uint32 prepareCounter, ref Ballot b, uint32 nC, uint32 nH)
{
    Statement st;
    st.pledges.type = StatementType.CP_ST_CONFIRM;
    auto con = &st.pledges.confirm;
    con.ballot = b;
    con.nPrepared = prepareCounter;
    con.nCommit = nC;
    con.nH = nH;
    con.quorumSetHash = qSetHash;

    return makeEnvelope(secretKey, slotIndex, st);
}

static Envelope
makePrepare(ref SecretKey secretKey, ref Hash qSetHash, uint64 slotIndex,
            ref Ballot  ballot, Ballot* prepared = null,
            uint32 nC = 0, uint32 nH = 0, Ballot* preparedPrime = null)
{
    Statement st;
    st.pledges.type = StatementType.CP_ST_PREPARE;
    auto p = &st.pledges.prepare;
    p.ballot = ballot;
    p.quorumSetHash = qSetHash;
    if (prepared)
    {
        p.prepared = *prepared;
    }

    p.nC = nC;
    p.nH = nH;

    if (preparedPrime)
    {
        p.preparedPrime = *preparedPrime;
    }

    return makeEnvelope(secretKey, slotIndex, st);
}

static Envelope
makeNominate(ref SecretKey secretKey, ref Hash qSetHash, uint64 slotIndex,
             Value[] votes, Value[] accepted)
{
    import std.algorithm;

    alias comp = (x, y) => x.value < y.value;
    votes.sort!(comp).release;
    accepted.sort!(comp).release;

    Statement st;
    st.pledges.type = StatementType.CP_ST_NOMINATE;
    auto nom = &st.pledges.nominate;
    nom.quorumSetHash = qSetHash;

    int idx;
    for (idx = 0; idx < votes.length; idx++)
    {
        nom.votes ~= (votes[idx]);
    }
    for (idx = 0; idx < accepted.length; idx++)
    {
        nom.accepted ~= (accepted[idx]);
    }
    return makeEnvelope(secretKey, slotIndex, st);
}

void
verifyPrepare(ref Envelope actual, ref SecretKey secretKey,
              ref Hash qSetHash, uint64 slotIndex, ref Ballot  ballot,
              Ballot* prepared = null, uint32 nC = 0, uint32 nH = 0,
              Ballot* preparedPrime = null)
{
    auto exp = makePrepare(secretKey, qSetHash, slotIndex, ballot, prepared, nC,
                           nH, preparedPrime);
    REQUIRE(exp.statement == actual.statement);
}

void
verifyConfirm(ref Envelope actual, ref SecretKey secretKey,
              ref Hash qSetHash, uint64 slotIndex, uint32 nPrepared,
              ref Ballot  b, uint32 nC, uint32 nH)
{
    auto exp =
        makeConfirm(secretKey, qSetHash, slotIndex, nPrepared, b, nC, nH);
    REQUIRE(exp.statement == actual.statement);
}

void
verifyExternalize(ref Envelope actual, ref SecretKey secretKey,
                  ref Hash qSetHash, uint64 slotIndex,
                  ref Ballot  commit, uint32 nH)
{
    auto exp = makeExternalize(secretKey, qSetHash, slotIndex, commit, nH);
    REQUIRE(exp.statement == actual.statement);
}

void
verifyNominate(ref Envelope actual, ref SecretKey secretKey,
               ref Hash qSetHash, uint64 slotIndex, Value[] votes,
               Value[] accepted)
{
    auto exp = makeNominate(secretKey, qSetHash, slotIndex, votes, accepted);
    REQUIRE(exp.statement == actual.statement);
}

class ConsensusProtocolTest
{
private:

    Hash [int] mValueHash;
    Value [int] mValue;

    Hash [int] mHash;
    SecretKey [int] mSecretKey;
    PublicKey [int] mKey;
    NodeID [int] mNodeID;

    void CREATE_VALUE(int i)
    {
        Hash h;
        h = Hash(sha256Of("SEED_VALUE_HASH_" ~  to!string(i, 10)));
        mValueHash[i] = h;

        Value v;
        v.value = xdr!Hash.serialize(h);
        mValue[i] = v;
    }

    void SIMULATION_CREATE_NODE(int i)
    {
        uint256 seed = sha256Of("NODE_SEED_" ~  to!string(i, 10));
        mSecretKey[i] = SecretKey.fromSeed(seed);
        mKey[i] = mSecretKey[i].getPublicKey();
        mNodeID[i] = NodeID(mKey[i]);
    }

public :
    this()
    {

    }

    void prepare()
    {
        for (int i = 0; i <= 3; i++)
        {
            CREATE_VALUE(i);
        }
    }

    void test1()
    {
        TEST_CASE("vblocking and quorum", "[scp]");
        {
            SIMULATION_CREATE_NODE(0);
            SIMULATION_CREATE_NODE(1);
            SIMULATION_CREATE_NODE(2);
            SIMULATION_CREATE_NODE(3);

            //  number of validator is 4
            //  threshold is 3
            QuorumSet qSet;
            qSet.threshold = 3;
            qSet.validators ~= mNodeID[0].publicKey;
            qSet.validators ~= mNodeID[1].publicKey;
            qSet.validators ~= mNodeID[2].publicKey;
            qSet.validators ~= mNodeID[3].publicKey;

            NodeID[] nodeSet;
            nodeSet ~= (mNodeID[0]);

            //  nodeSet size is 1
            REQUIRE(LocalNode.isQuorumSlice(qSet, nodeSet) == false);
            REQUIRE(LocalNode.isVBlocking(qSet, nodeSet) == false);

            nodeSet ~= (mNodeID[2]);

            //  nodeSet size is 2
            REQUIRE(LocalNode.isQuorumSlice(qSet, nodeSet) == false);
            REQUIRE(LocalNode.isVBlocking(qSet, nodeSet) == true);

            nodeSet ~= (mNodeID[3]);

            //  nodeSet size is 3
            REQUIRE(LocalNode.isQuorumSlice(qSet, nodeSet) == true);
            REQUIRE(LocalNode.isVBlocking(qSet, nodeSet) == true);

            nodeSet ~= (mNodeID[1]);

            //  nodeSet size is 4
            REQUIRE(LocalNode.isQuorumSlice(qSet, nodeSet) == true);
            REQUIRE(LocalNode.isVBlocking(qSet, nodeSet) == true);
        }

        TEST_CASE("v-blocking distance", "[scp]");
        {
            SIMULATION_CREATE_NODE(0);
            SIMULATION_CREATE_NODE(1);
            SIMULATION_CREATE_NODE(2);
            SIMULATION_CREATE_NODE(3);
            SIMULATION_CREATE_NODE(4);
            SIMULATION_CREATE_NODE(5);
            SIMULATION_CREATE_NODE(6);
            SIMULATION_CREATE_NODE(7);

            QuorumSet qSet;
            qSet.threshold = 2;
            qSet.validators ~= (mNodeID[0].publicKey);
            qSet.validators ~= (mNodeID[1].publicKey);
            qSet.validators ~= (mNodeID[2].publicKey);

            auto check = (ref QuorumSet qSetCheck, ref NodeIDSet s, int expected)
            {
                auto r = LocalNode.findClosestVBlocking(qSetCheck, s, null);
                REQUIRE(expected == r.length);
            };

            NodeIDSet good = new NodeIDSet;

            good.insert(mNodeID[0]); //1 + V - T = 4 - 2 = 2;
            // already v-blocking
            check(qSet, good, 0);

            good.insert(mNodeID[1]);
            // either v0 or v1
            check(qSet, good, 1);

            good.insert(mNodeID[2]);
            // any 2 of v0..v2
            check(qSet, good, 2);

            QuorumSet qSubSet1;
            qSubSet1.threshold = 1;
            qSubSet1.validators ~= (mNodeID[3].publicKey);
            qSubSet1.validators ~= (mNodeID[4].publicKey);
            qSubSet1.validators ~= (mNodeID[5].publicKey);
            qSet.innerSets ~= (qSubSet1);

            good.insert(mNodeID[3]);
            // any 3 of v0..v3
            check(qSet, good, 3);

            good.insert(mNodeID[4]);
            // v0..v2
            check(qSet, good, 3);

            qSet.threshold = 1;  //1 + V - T = 1 + 4 - 1 = 4;
            // v0..v4
            check(qSet, good, 5);

            good.insert(mNodeID[5]);
            // v0..v5
            check(qSet, good, 6);

            QuorumSet qSubSet2;
            qSubSet2.threshold = 2;
            qSubSet2.validators ~= (mNodeID[6].publicKey);
            qSubSet2.validators ~= (mNodeID[7].publicKey);

            qSet.innerSets ~= (qSubSet2);
            // v0..v5
            check(qSet, good, 6);

            good.insert(mNodeID[6]);
            // v0..v5
            check(qSet, good, 6);

            good.insert(mNodeID[7]);
            // v0..v5 and one of 6,7
            check(qSet, good, 7);

            qSet.threshold = 4;
            // v6, v7
            check(qSet, good, 2);

            qSet.threshold = 3;
            // v0..v2
            check(qSet, good, 3);

            qSet.threshold = 2;
            // v0..v2 and one of v6,v7
            check(qSet, good, 4);
        }
    }

    alias genEnvelope = Envelope delegate (ref SecretKey sk);

    static genEnvelope
    makePrepareGen(ref Hash qSetHash, ref Ballot ballot,
                       Ballot* prepared = null, uint32 nC = 0, uint32 nH = 0,
                       Ballot* preparedPrime = null)
    {
        return delegate(ref SecretKey sk) {
            return makePrepare(sk, qSetHash, 0, ballot, prepared, nC, nH, preparedPrime);
        };
    }

    static genEnvelope
    makeConfirmGen(ref Hash qSetHash, uint32 prepareCounter, ref Ballot b, uint32 nC, uint32 nH)
    {
        return delegate(ref SecretKey sk) {
            return makeConfirm(sk, qSetHash, 0, prepareCounter, b, nC, nH);
        };
    }

    static genEnvelope
    makeExternalizeGen(ref Hash qSetHash, ref Ballot commitBallot, uint32 nH)
    {
        return delegate(ref SecretKey sk) {
            return makeExternalize(sk, qSetHash, 0, commitBallot, nH);
        };
    }

    void test2()
    {
        TEST_CASE("ballot protocol core5", "[scp][ballotprotocol]");
        {
            SIMULATION_CREATE_NODE(0);
            SIMULATION_CREATE_NODE(1);
            SIMULATION_CREATE_NODE(2);
            SIMULATION_CREATE_NODE(3);
            SIMULATION_CREATE_NODE(4);

            // we need 5 nodes to avoid sharing various thresholds:
            // v-blocking set size: 2 = 1 + 5 - 4 = 2; 
            // threshold: 4 = 3 + self or 4 others ; 1 + 5 - 2 = 4
            QuorumSet qSet;
            qSet.threshold = 4;
            qSet.validators ~= (mNodeID[0].publicKey);
            qSet.validators ~= (mNodeID[1].publicKey);
            qSet.validators ~= (mNodeID[2].publicKey);
            qSet.validators ~= (mNodeID[3].publicKey);
            qSet.validators ~= (mNodeID[4].publicKey);

            Hash qSetHash;
            qSetHash = Hash(sha256Of(xdr!QuorumSet.serialize(qSet)));
            //writefln("Local Node QuorumSetHash : %s", toHexString(qSetHash.hash));

            TestCP cp = new TestCP(mSecretKey[0], qSet);
            cp.storeQuorumSet(qSet);

            Hash qSetHash0;
            qSetHash0 = cast(Hash)cp.mConsensusProtocol.getLocalNode().getQuorumSetHash();

            REQUIRE(mValue[0].value < mValue[1].value);

            writefln("[INFO], ConsensusProtocol");
            writefln("[INFO], ConsensusProtocol BEGIN TEST");

            SECTION("bumpState x");
            {
                REQUIRE(cp.bumpState(0, mValue[0]));
                REQUIRE(cp.mEnvs.length == 1);

                Ballot expectedBallot = Ballot(1, mValue[0]);

                verifyPrepare(cp.mEnvs[0], mSecretKey[0], qSetHash0, 0, expectedBallot);
            }
        }
    }

    void test3()
    {
        SIMULATION_CREATE_NODE(0);
        SIMULATION_CREATE_NODE(1);
        SIMULATION_CREATE_NODE(2);
        SIMULATION_CREATE_NODE(3);
        SIMULATION_CREATE_NODE(4);

        // we need 5 nodes to avoid sharing various thresholds:
        // v-blocking set size: 2
        // threshold: 4
        QuorumSet qSet;
        qSet.threshold = 4;
        qSet.validators ~= (mNodeID[0].publicKey);
        qSet.validators ~= (mNodeID[1].publicKey);
        qSet.validators ~= (mNodeID[2].publicKey);
        qSet.validators ~= (mNodeID[3].publicKey);
        qSet.validators ~= (mNodeID[4].publicKey);

        Hash qSetHash;
        qSetHash = Hash(sha256Of(xdr!QuorumSet.serialize(qSet)));
        TestCP cp = new TestCP(mSecretKey[0], qSet);
        //writefln("Local Node QuorumSetHash : %s", toHexString(qSetHash.hash));
        cp.storeQuorumSet(qSet);

        Hash qSetHash0;
        qSetHash0 = cast(Hash)cp.mConsensusProtocol.getLocalNode().getQuorumSetHash();

        REQUIRE(mValue[0].value < mValue[1].value);

        auto recvVBlockingChecks = (genEnvelope gen, bool withChecks)
        {
            Envelope e1 = gen(mSecretKey[0]);
            Envelope e2 = gen(mSecretKey[1]);

            // nothing should happen with first message
            size_t i = cp.mEnvs.length;
            cp.receiveEnvelope(e1);
            if (withChecks)
            {
                REQUIRE(cp.mEnvs.length == i);
            }
            i++;
            cp.receiveEnvelope(e2);
            if (withChecks)
            {
                REQUIRE(cp.mEnvs.length == i);
            }
        };

        auto recvVBlocking = (genEnvelope gen)
        {
            recvVBlockingChecks(gen, true);
        };

        auto recvQuorumChecks = (genEnvelope gen, bool withChecks, bool delayedQuorum)
        {
            Envelope e1 = gen(mSecretKey[1]);
            Envelope e2 = gen(mSecretKey[2]);
            Envelope e3 = gen(mSecretKey[3]);
            Envelope e4 = gen(mSecretKey[4]);

            cp.receiveEnvelope(e1);
            writefln("cp.mEnvs.length : %d", cp.mEnvs.length);

            cp.receiveEnvelope(e2);
            writefln("cp.mEnvs.length : %d", cp.mEnvs.length);

            size_t i = cp.mEnvs.length + 1;

            cp.receiveEnvelope(e3);
            writefln("cp.mEnvs.length : %d", cp.mEnvs.length);

            if (withChecks && !delayedQuorum)
            {
                REQUIRE(cp.mEnvs.length == i);
            }

            // nothing happens with an extra vote (unless we're in delayedQuorum)
            cp.receiveEnvelope(e4);
            writefln("cp.mEnvs.length : %d", cp.mEnvs.length);
            if (withChecks && delayedQuorum)
            {
                REQUIRE(cp.mEnvs.length == i);
            }

        };

        auto recvQuorum = (genEnvelope gen)
        {
            recvQuorumChecks(gen, true, false);
        };

        auto nodesAllPledgeToCommit = ()
        {
            Ballot b = Ballot(1, mValue[0]);
            Envelope prepare1 = makePrepare(mSecretKey[1], qSetHash, 0, b);
            Envelope prepare2 = makePrepare(mSecretKey[2], qSetHash, 0, b);
            Envelope prepare3 = makePrepare(mSecretKey[3], qSetHash, 0, b);
            Envelope prepare4 = makePrepare(mSecretKey[4], qSetHash, 0, b);

            REQUIRE(cp.bumpState(0, mValue[0]));
            REQUIRE(cp.mEnvs.length == 1);

            verifyPrepare(cp.mEnvs[0], mSecretKey[0], qSetHash0, 0, b);

            cp.receiveEnvelope(prepare1);
            REQUIRE(cp.mEnvs.length == 1);
            REQUIRE(cp.mHeardFromQuorums[0].length == 0);

            cp.receiveEnvelope(prepare2);
            REQUIRE(cp.mEnvs.length == 1);
            REQUIRE(cp.mHeardFromQuorums[0].length == 0);

            cp.receiveEnvelope(prepare3);
            REQUIRE(cp.mEnvs.length == 2);
            REQUIRE(cp.mHeardFromQuorums[0].length == 1);
            REQUIRE(cp.mHeardFromQuorums[0][0] == b);

            // We have a quorum including us
            verifyPrepare(cp.mEnvs[1], mSecretKey[0], qSetHash0, 0, b, &b);

            cp.receiveEnvelope(prepare4);
            REQUIRE(cp.mEnvs.length == 2);

            Envelope prepared1 = makePrepare(mSecretKey[1], qSetHash, 0, b, &b);
            Envelope prepared2 = makePrepare(mSecretKey[2], qSetHash, 0, b, &b);
            Envelope prepared3 = makePrepare(mSecretKey[3], qSetHash, 0, b, &b);
            Envelope prepared4 = makePrepare(mSecretKey[4], qSetHash, 0, b, &b);

            cp.receiveEnvelope(prepared4);
            cp.receiveEnvelope(prepared3);
            REQUIRE(cp.mEnvs.length == 2);

            cp.receiveEnvelope(prepared2);
            REQUIRE(cp.mEnvs.length == 3);

            // confirms prepared
            verifyPrepare(cp.mEnvs[2], mSecretKey[0], qSetHash0, 0, b, &b, b.counter, b.counter);

            // extra statement doesn't do anything
            cp.receiveEnvelope(prepared1);
            REQUIRE(cp.mEnvs.length == 3);
        };

        SECTION("start <1,x>");
        {
            Value aValue = mValue[0];
            Value bValue = mValue[1];

            Ballot A1 = Ballot(1, aValue);
            Ballot B1 = Ballot(1, bValue);

            Ballot A2 = A1;
            A2.counter++;

            Ballot A3 = A2;
            A3.counter++;

            Ballot A4 = A3;
            A4.counter++;

            Ballot A5 = A4;
            A5.counter++;

            Ballot AInf = Ballot(UINT32_MAX, aValue);
            Ballot BInf = Ballot(UINT32_MAX, bValue);

            Ballot B2 = B1;
            B2.counter++;

            Ballot B3 = B2;
            B3.counter++;

            REQUIRE(cp.bumpState(0, aValue));
            REQUIRE(cp.mEnvs.length == 1);

            SECTION("prepared A1");
            {
                recvQuorum(makePrepareGen(qSetHash, A1));
                REQUIRE(cp.mEnvs.length == 2);
                writefln("cp.mEnvs.length : %d", cp.mEnvs.length);
                verifyPrepare(cp.mEnvs[1], mSecretKey[0], qSetHash0, 0, A1, &A1);

            }
        }
    }

    void test()
    {
        //test1();
        //test2();
        test3();
    }
}
