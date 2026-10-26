// #define timeout true; //premature timeout enabled 

mtype = { MISSION_COUNT, MISSION_REQUEST_INT, MISSION_ITEM_INT, MISSION_ACK };


chan gcs2drone = [2] of { mtype, byte, byte }; //mtype, seq/counter, target
chan drone2gcs = [2] of  { mtype, byte, byte };
//to track the sequence order (1)
#define NPAIR  2
#define MAXSEQ 5
typedef SeqLog { byte s[MAXSEQ] };
SeqLog seqA[NPAIR], seqB[NPAIR];
byte na[NPAIR], nb[NPAIR];

init {
    byte n0, n1;
    select(n0 : 0 .. 4);
    select(n1 : 0 .. 4);
    atomic {
        run gcs(0, n0);
        run gcs(1, n1);
        run drone(0);
        run drone(1);

        run loss();
    }
}

proctype gcs(byte p; byte ctn) {
    byte seq;

    gcs2drone ! MISSION_COUNT, ctn, p;

    do
    :: drone2gcs ? MISSION_REQUEST_INT, seq, eval(p);
            ->
receive_gcs:
            atomic { gcs2drone ! MISSION_ITEM_INT, seq, p;
            if
            :: na[p] == 0 || seq != seqA[p].s[na[p]-1] -> //the fix for Note_2
                    assert(na[p] < MAXSEQ);
                    seqA[p].s[na[p]] = seq; na[p]++;
                    assert(seqA[p].s[na[p]-1] == seqB[p].s[nb[p]-1]); assert(seqA[p].s[na[p]-1] == na[p]-1);
            :: else -> skip
            fi }
    :: timeout
            -> gcs2drone ! MISSION_COUNT, ctn, p;
    :: drone2gcs ? MISSION_ACK, _ , eval(p)
            -> break
    od


}

proctype drone(byte p) {
    byte seq;
    byte ctn;

    gcs2drone ? MISSION_COUNT, ctn, eval(p);

    if
    :: ctn == 0 -> drone2gcs ! MISSION_ACK, 0, p; goto end; //0 is no error
    :: else -> atomic { drone2gcs ! MISSION_REQUEST_INT, seq, p; assert(nb[p] < MAXSEQ); seqB[p].s[nb[p]] = seq; nb[p]++; }
    fi

    do
    :: gcs2drone ? MISSION_ITEM_INT, seq, eval(p); assert(seqB[p].s[nb[p]-1] == nb[p]-1); //guard evaluation is always atomic in SPIN

            -> receive_drone: if
                :: seq < ctn - 1
                    ->
                    atomic {
                        seq++;
                        drone2gcs ! MISSION_REQUEST_INT, seq, p;
                        assert(nb[p] < MAXSEQ);
                        seqB[p].s[nb[p]] =seq;
                        nb[p]++; }

                :: seq == ctn - 1 -> drone2gcs ! MISSION_ACK, 0, p; break;
                fi
    :: timeout //Here we not yet considered pre-mature timeout
            -> drone2gcs ! MISSION_REQUEST_INT, seq, p
    od
end:
}

proctype loss() {
end:
    do
    :: gcs2drone ? _, _, _; //haven't taken into acount ACK being lost, but the protocol seems to do not care as ACK doesn't require a response
                                    //If so, this is questioning, what would happen if ACK loss? How they cope with that?
    :: drone2gcs ? _, _, _;
    od
}



#define fair ( (([]<> (nb[0] > na[0])) -> []<> gcs[1]@receive_gcs) \
            && (([]<> (nb[1] > na[1])) -> []<> gcs[2]@receive_gcs) \
            && (([]<> (na[1] >= nb[1])) -> []<> drone[1]@receive_drone) \
            && (([]<> (na[0] >= nb[0])) -> []<> drone[0]@receive_drone))

// ltl smaller {
//     fair -> [] (na[0] <= nb[0] && na[1] <= nb[1]);
// }

// ltl input {
//     fair -> [] ((nb[0] > na[0] -> <> (na[0] >= nb[0])) && (nb[1] > na[1] -> <> (na[1] >= nb[1])));
// }

// ltl fair_liveness {
//     (    ([]<> (len(gcs2drone) > 0) -> []<> drone@receive_drone)
//       && ([]<> (len(drone2gcs) > 0) -> []<> gcs@receive_gcs) )
//     ->
//     [] (na <= nb)
// }