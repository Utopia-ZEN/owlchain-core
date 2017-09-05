module owlchain.consensus.nominationProtocol;

import core.time;

import std.stdio;
import std.container;
import std.json;
import std.algorithm : canFind;
import std.algorithm : find;
import std.algorithm : isSorted;
import std.typecons;

import owlchain.xdr;

import owlchain.consensus.localNode;
import owlchain.consensus.slot;
import owlchain.consensus.bcp;
import owlchain.consensus.bcpDriver;

import owlchain.utils.globalChecks;
import owlchain.utils.uniqueStruct;

class NominationProtocol
{
private:
    Slot mSlot;
    int32 mRoundNumber;
    ValueSet mVotes; // X
    ValueSet mAccepted; // Y
    ValueSet mCandidates; // Z
    BCPEnvelope[NodeID] mLatestNominations; // N

    // last envelope emitted by this node
    UniqueStruct!BCPEnvelope mLastEnvelope;

    // nodes from quorum set that have the highest priority this round
    NodeIDSet mRoundLeaders;

    // true if 'nominate' was called
    bool mNominationStarted;

    // the latest (if any) candidate value
    Value mLatestCompositeCandidate;

    // the value from the previous slot
    Value mPreviousValue;

public:
    this(Slot slot)
    {
        mVotes = new ValueSet;
        mAccepted = new ValueSet;
        mCandidates = new ValueSet;

        mRoundLeaders = new NodeIDSet;

        mSlot = slot;
        mRoundNumber = 0;
        mNominationStarted = false;
    }

    ~this()
    {
        mVotes = null;
        mAccepted = null;
        mCandidates = null;
        mRoundLeaders = null;
        mSlot = null;
    }

    BCP.EnvelopeState processEnvelope(ref BCPEnvelope envelope)
    {
        auto st = &envelope.statement;
        auto nom = &st.pledges.nominate;

        BCP.EnvelopeState res = BCP.EnvelopeState.INVALID;

        if (isNewerStatement(st.nodeID, *nom))
        {
            if (isSane(*st))
            {
                recordEnvelope(envelope);
                res = BCP.EnvelopeState.VALID;

                if (mNominationStarted)
                {
                    // tracks if we should emit a new nomination message
                    bool modified = false;
                    bool newCandidates = false;

                    // attempts to promote some of the votes to accepted
                    foreach (int i, ref Value v; nom.votes)
                    {
                        // v is already accepted
                        if (!find(mAccepted[], v).empty)
                        {
                            continue;
                        }

                        if (mSlot.federatedAccept((ref BCPStatement st2) {
                                bool res;
                                auto nom2 = &st2.pledges.nominate;
                                res = (nom2.votes.canFind(v));
                                return res;
                            }, (ref BCPStatement st2) {
                                return NominationProtocol.acceptPredicate(v, st2);
                            }, mLatestNominations))
                        {
                            auto vl = validateValue(v);
                            if (vl == BCPDriver.ValidationLevel.kFullyValidatedValue)
                            {
                                mAccepted.insert(v);
                                mVotes.insert(v);
                                modified = true;
                            }
                            else
                            {
                                // the value made it pretty far:
                                // see if we can vote for a variation that
                                // we consider valid
                                Value toVote;
                                toVote = extractValidValue(v);
                                if (toVote.value.length != 0)
                                {
                                    if (mVotes.insert(toVote))
                                    {
                                        modified = true;
                                    }
                                }
                            }
                        }
                    }

                    // attempts to promote accepted values to candidates
                    foreach (ref Value a; mAccepted)
                    {
                        if (!find(mCandidates[], a).empty)
                        {
                            continue;
                        }

                        if (mSlot.federatedRatify((ref BCPStatement st) {
                                return NominationProtocol.acceptPredicate(a, st);
                            }, mLatestNominations))
                        {
                            mCandidates.insert(a);
                            newCandidates = true;
                        }
                    }

                    // only take round leader votes if we're still looking for
                    // candidates
                    if (mCandidates.empty && !find(mRoundLeaders[], st.nodeID).empty)
                    {
                        Value newVote = getNewValueFromNomination(*nom);
                        if (newVote.value.length != 0)
                        {
                            mVotes.insert(newVote);
                            modified = true;
                        }
                    }

                    if (modified)
                    {
                        emitNomination();
                    }

                    if (newCandidates)
                    {
                        mLatestCompositeCandidate = mSlot.getCPDriver()
                            .combineCandidates(mSlot.getSlotIndex(), mCandidates);
                        mSlot.getCPDriver().updatedCandidateValue(mSlot.getSlotIndex(),
                                mLatestCompositeCandidate);
                        mSlot.bumpState(mLatestCompositeCandidate, false);
                    }
                }
            }
            else
            {
                writeln("[DEBUG], BCP NominationProtocol: message didn't pass sanity check");
            }
        }
        return res;
    }

    static Value[] getStatementValues(ref BCPStatement st)
    {
        Value[] res;
        applyAll(st.pledges.nominate, (ref Value v) { res ~= v; });
        return res;
    }

    // attempts to nominate a value for consensus
    bool nominate(ref Value value, ref Value previousValue, bool timedout)
    {
        //if (Logging::logDebug("BCP"))
        //writefln("[DEBUG], BCP NominationProtocol.nominate %s", mSlot.getCP().getValueString(value));

        bool updated = false;

        if (timedout && !mNominationStarted)
        {
            writefln("[DEBUG], BCP NominationProtocol.nominate (TIMED OUT)");
            return false;
        }

        mNominationStarted = true;

        mPreviousValue = previousValue;

        mRoundNumber++;
        updateRoundLeaders();

        Value nominatingValue;

        if (!find(mRoundLeaders[], mSlot.getLocalNode().getNodeID()).empty)
        {
            if (mVotes.insert(value))
            {
                updated = true;
            }
            nominatingValue = value;
        }
        else
        {
            foreach (ref NodeID leader; mRoundLeaders)
            {
                auto pValue = (leader in mLatestNominations);
                if (pValue !is null)
                {
                    nominatingValue = getNewValueFromNomination(
                            mLatestNominations[leader].statement.pledges.nominate);
                    if (nominatingValue.value.length != 0)
                    {
                        mVotes.insert(nominatingValue);
                        updated = true;
                    }
                }
            }
        }

        Duration timeout = mSlot.getCPDriver().computeTimeout(mRoundNumber);

        mSlot.getCPDriver().nominatingValue(mSlot.getSlotIndex(), nominatingValue);

        Slot* slot = &mSlot;
        mSlot.getCPDriver().setupTimer(mSlot.getSlotIndex(), Slot.NOMINATION_TIMER, timeout, () {
            slot.nominate(value, previousValue, true);
        });

        if (updated)
        {
            emitNomination();
        }
        else
        {
            writefln("[DEBUG], BCP NominationProtocol.nominate (SKIPPED)");
        }

        return updated;
    }

    // stops the nomination protocol
    void stopNomination()
    {
        mNominationStarted = false;
    }

    ref Value getLatestCompositeCandidate()
    {
        return mLatestCompositeCandidate;
    }

    void dumpInfo(ref JSONValue ret)
    {
        import std.utf;

        JSONValue[string] nomStateObject;
        JSONValue nomState = nomStateObject;
        nomState.object["roundnumber"] = JSONValue(mRoundNumber);
        nomState.object["started"] = JSONValue(mNominationStarted);

        JSONValue[] state_X;
        nomState.object["X"] = state_X;
        foreach (ref Value v; mVotes)
        {
            nomState["X"].array ~= JSONValue(toUTF8(mSlot.getCP().getValueString(v)));
        }

        JSONValue[] state_Y;
        nomState.object["Y"] = state_Y;
        foreach (ref Value v; mAccepted)
        {
            nomState["Y"].array ~= JSONValue(toUTF8(mSlot.getCP().getValueString(v)));
        }

        JSONValue[] state_Z;
        nomState.object["Z"] = state_Z;
        foreach (ref Value v; mCandidates)
        {
            nomState["Z"].array ~= JSONValue(toUTF8(mSlot.getCP().getValueString(v)));
        }
        ret.object["nomination"] = nomState;
    }

    BCPEnvelope* getLastMessageSend()
    {
        if (mLastEnvelope)
            return cast(BCPEnvelope*) mLastEnvelope;
        else
            return null;
    }

    void setStateFromEnvelope(ref BCPEnvelope e)
    {
        if (mNominationStarted)
        {
            throw new Exception("Cannot set state after nomination is started");
        }
        recordEnvelope(e);

        int i;
        for (i = 0; i < e.statement.pledges.nominate.accepted.length; i++)
        {
            mAccepted.insert(e.statement.pledges.nominate.accepted[i]);
        }
        for (i = 0; i < e.statement.pledges.nominate.votes.length; i++)
        {
            mVotes.insert(e.statement.pledges.nominate.votes[i]);
        }

        mLastEnvelope = cast(UniqueStruct!BCPEnvelope)(new BCPEnvelope(e.statement, e.signature));
    }

    BCPEnvelope[] getCurrentState()
    {
        BCPEnvelope[] res;
        res.reserve(mLatestNominations.length);
        foreach (ref const NodeID n, ref BCPEnvelope e; mLatestNominations)
        {
            // only return messages for self if the slot is fully validated
            if (!(n == mSlot.getCP().getLocalNodeID()) || mSlot.isFullyValidated())
            {
                res ~= e;
            }
        }
        return res;
    }

private:
    bool isNewerStatement(ref NodeID nodeID, ref BCPNomination st)
    {
        bool res = false;

        auto pValue = (nodeID in mLatestNominations);
        if (pValue !is null)
        {
            res = isNewerStatement(mLatestNominations[nodeID].statement.pledges.nominate, st);
        }
        else
        {
            res = true;
        }

        return res;
    }

    // returns true if 'p' is a subset of 'v'
    // also sets 'notEqual' if p and v differ
    // note: p and v must be sorted
    static bool isSubsetHelper(ref Value[] p, ref Value[] v, ref bool notEqual)
    {
        bool res;
        if (p.length <= v.length)
        {

            res = true;
            /*
            for (int i = 0; i < p.length; i++)
            {
                if (!v.canFind(p[i])) {
                    res = false;
                    break;
                }
            }
            */
            if (p.length > 0)
            {
                if (res)
                {
                    if (!v.canFind(p[0]))
                    {
                        res = false;
                    }
                }
                if (res)
                {
                    if (!v.canFind(p[$ - 1]))
                    {
                        res = false;
                    }
                }
            }

            if (res)
            {
                notEqual = p.length != v.length;
            }
            else
            {
                notEqual = true;
            }
        }
        else
        {
            notEqual = true;
            res = false;
        }
        return res;
    }

    BCPDriver.ValidationLevel validateValue(ref Value v)
    {
        return mSlot.getCPDriver().validateValue(mSlot.getSlotIndex(), v);
    }

    Value extractValidValue(ref Value value)
    {
        return mSlot.getCPDriver().extractValidValue(mSlot.getSlotIndex(), value);
    }

    static bool isNewerStatement(ref BCPNomination oldst, ref BCPNomination st)
    {
        bool res = false;
        bool grows;
        bool g = false;

        if (isSubsetHelper(oldst.votes, st.votes, g))
        {
            grows = g;
            if (isSubsetHelper(oldst.accepted, st.accepted, g))
            {
                grows = grows || g;
                res = grows; //  true only if one of the sets grew
            }
        }

        return res;
    }

    bool isSane(ref BCPStatement st)
    {
        auto nom = &(st.pledges.nominate);
        bool res = (nom.votes.length + nom.accepted.length) != 0;

        res = res && isSorted!"a.value < b.value"(nom.votes);
        res = res && isSorted!"a.value < b.value"(nom.accepted);

        return res;
    }

    void recordEnvelope(ref BCPEnvelope env)
    {
        auto st = &env.statement;
        mLatestNominations[st.nodeID] = env;
        mSlot.recordStatement(env.statement);
    }

    void emitNomination()
    {
        BCPStatement st;
        st.nodeID = mSlot.getLocalNode().getNodeID();
        st.pledges.type = BCPStatementType.BCP_ST_NOMINATE;
        auto nom = &st.pledges.nominate;

        st.pledges.nominate.quorumSetHash = mSlot.getLocalNode().getQuorumSetHash();

        int i;
        foreach (ref Value v; mVotes)
        {
            nom.votes ~= v;
        }

        foreach (ref Value a; mAccepted)
        {
            nom.accepted ~= a;
        }

        BCPEnvelope envelope = mSlot.createEnvelope(st);

        if (mSlot.processEnvelope(envelope, true) == BCP.EnvelopeState.VALID)
        {
            if (!mLastEnvelope || isNewerStatement(mLastEnvelope.statement.pledges.nominate,
                    st.pledges.nominate))
            {
                mLastEnvelope = cast(UniqueStruct!BCPEnvelope)(new BCPEnvelope(envelope.statement,
                        envelope.signature));
                if (mSlot.isFullyValidated())
                {
                    mSlot.getCPDriver().emitEnvelope(envelope);
                }
            }
        }
        else
        {
            // there is a bug in the application if it queued up
            // a statement for itself that it considers invalid
            throw new Exception("moved to a bad state (nomination)");
        }
    }

    // returns true if v is in the accepted list from the statement
    static bool acceptPredicate(ref Value v, ref BCPStatement st)
    {
        bool res;
        res = st.pledges.nominate.accepted.canFind(v);
        return res;
    }

    // applies 'processor' to all values from the passed in nomination
    static void applyAll(ref BCPNomination nom, void delegate(ref Value) processor)
    {
        int i;
        for (i = 0; i < nom.votes.length; i++)
        {
            processor(nom.votes[i]);
        }
        for (i = 0; i < nom.accepted.length; i++)
        {
            processor(nom.accepted[i]);
        }
    }

    // updates the set of nodes that have priority over the others
    void updateRoundLeaders()
    {
        mRoundLeaders.clear();
        uint64 topPriority = 0;
        BCPQuorumSet myQSet = mSlot.getLocalNode().getQuorumSet();

        LocalNode.forAllNodes(myQSet, (ref NodeID cur) {
            uint64 w = getNodePriority(cur, myQSet);
            if (w > topPriority)
            {
                topPriority = w;
                mRoundLeaders.clear();
            }
            if (w == topPriority && w > 0)
            {
                mRoundLeaders.insert(cur);
            }
        });

        writefln("[DEBUG], BCP updateRoundLeaders: %d", mRoundLeaders.length);
        //if (Logging::logDebug("BCP"))
        foreach (ref NodeID n; mRoundLeaders)
        {
            writefln("[DEBUG], BCP leader: %s",
                    mSlot.getCPDriver().toShortString(n));
        }
    }

    // computes Gi(isPriority?P:N, prevValue, mRoundNumber, nodeID)
    // from the paper
    uint64 hashNode(bool isPriority, ref NodeID nodeID)
    {
        dbgAssert(mPreviousValue.value.length != 0);
        return mSlot.getCPDriver().computeHashNode(mSlot.getSlotIndex(),
                mPreviousValue, isPriority, mRoundNumber, nodeID);
    }

    // computes Gi(K, prevValue, mRoundNumber, value)
    uint64 hashValue(ref Value value)
    {
        dbgAssert(mPreviousValue.value.length != 0);
        return mSlot.getCPDriver().computeValueHash(mSlot.getSlotIndex(),
                mPreviousValue, mRoundNumber, value);
    }

    uint64 getNodePriority(ref NodeID nodeID, ref BCPQuorumSet qset)
    {
        uint64 res;
        uint64 w = LocalNode.getNodeWeight(nodeID, qset);

        if (hashNode(false, nodeID) < w)
        {
            res = hashNode(true, nodeID);
        }
        else
        {
            res = 0;
        }
        return res;
    }

    // returns the highest value that we don't have yet, that we should
    // vote for, extracted from a nomination.
    // returns the empty value if no new value was found
    Value getNewValueFromNomination(ref BCPNomination nom)
    {
        // pick the highest value we don't have from the leader
        // sorted using hashValue.
        Value newVote;
        uint64 newHash = 0;

        applyAll(nom, (ref Value value) {
            Value valueToNominate;
            auto vl = validateValue(value);
            if (vl == BCPDriver.ValidationLevel.kFullyValidatedValue)
            {
                valueToNominate = value;
            }
            else
            {
                valueToNominate = extractValidValue(value);
            }

            if (valueToNominate.value.length != 0)
            {
                if (find(mVotes[], valueToNominate).empty)
                {
                    uint64 curHash = hashValue(valueToNominate);
                    if (curHash >= newHash)
                    {
                        newHash = curHash;
                        newVote = valueToNominate;
                    }
                }
            }
        });
        return newVote;
    }

}
