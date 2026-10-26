This MAVlink subprotocol is concern with mission flight plan

## CLAIMS

- The protocol supports re-request of messages that have not arrived, which allows missions to be reliably transferred over a lossy link.

1. Plan type is irrelevant to promela, assume it is chosen beforehand (`MAV_MISSION_TYPE = MAV_MISSION_TYPE_MISSION`)
2. `MAV_CMD`: there are three types for navigatoin/speed change and condition. I do not think any of this is relevant now.
3. Plan payload message: I think it is irrelevant as well
4. (MissionPositional parameters) (x,y,z) -> maybe embedded just like score in CBBA? Note that they can be local

---

## PLAN UPLOAD

Detecting plan change through plan matching ids -> avoid expensive operation

IDs are generated when new things are uploaded

The sequence of send as below:

### GCS send

`MISSION_COUNT`'s field name has specific fields that are important to be modelled:

- `count`: count number of mission items in the seq
- `opaque_id`: to decide ip plan has changed to update (I can leave it out for single download or upload right now)
- `target_system`: somewhat essential when I start modeling multiple GCs or multiple drones

### Loop until seq = count - 1

**Drone response:**

`MISSION_send_INT`'s fields to be specified:

- `target_system`
- `seq`; information of the requested mission item (see `MISSION_ITEM_INT`)

**GCS send:**

`MISSION_ITEM_INT`'s field name:

- `target_system`
- `seq`
- `current` (0, 1): it is to highlight which item is executing right now. I think it is not important now, but later might be useful for checking some property

### Drone send (when receive item with seq = count - 1)

`MISSION_ACK`:

- `mission_type` got changed here, thus I am thinking whether it is necessary in the model. But right now, I will stay out of it.
- `target_system`
- `type` (possitive ack: 0 or error: non zero)
- `opaque_id` (as above)

---

At first, I assume there are only one - to - one gcs, drone, with no premature timeout, no error yet => All states are reachable:

```
State-vector 48 byte, depth reached 30, errors: 0
       98 states, stored
        4 states, matched
      102 transitions (= stored+matched)
        5 atomic steps
hash conflicts:         0 (resolved)
```

---

Now there is requirement:

## SAFETY

1. Plan items must be received in order. If an item is received out-of-sequence the expected item should be re-requested by the vehicle (the out-of-sequence item is dropped):

   ```promela
   assert(seqB[nb-1] == expectation[nb-1]);
   assert(seqA[na-1] == expectation[na-1]);
   ```

   No violation found.

2. it is always the case that both have the same sequence: While I was checking for:

   ```promela
   assert (seqA(na-1) == seqB(nb-1))
   ```

   I was wondering what if, while seq is incremented, the drone receive new message (thus I do not make `seq++` and `drove2gcs ! _, _` be atomic). /b If the system truely do not consider this a case, then a lot of bugs would come through. Therefore, I would recommend them to make sure bundle `seq++` with sending message as a transaction to avoid interleaving. Proof:

   ```
    8:    proc  2 (drone:1) upload.pml:37 Send MISSION_REQUEST_INT,0      -> queue 2 (drone2gcs)
    8:    proc  2 (drone:1) upload.pml:37 (state 6)       [drone2gcs!MISSION_REQUEST_INT,seq]
                  queue 1 (gcs2drone): 
                  queue 2 (drone2gcs): [MISSION_REQUEST_INT,0]
    9:    proc  2 (drone:1) upload.pml:37 (state 7)       [seqB[nb] = seq]
                  queue 1 (gcs2drone): 
                  queue 2 (drone2gcs): [MISSION_REQUEST_INT,0]
   10:    proc  1 (gcs:1) upload.pml:16 Recv MISSION_REQUEST_INT,0        <- queue 2 (drone2gcs)
   10:    proc  1 (gcs:1) upload.pml:16 (state 2) [drone2gcs?MISSION_REQUEST_INT,seq]
                  queue 1 (gcs2drone): 
                  queue 2 (drone2gcs): 
                  gcs(1):seq = 0
   ```

   => I will put them in atomic transaction from now on. Indeed, no error found.

3. It is always the case that na <= nb (this is because drone is the one who send and incrment seq first, then gcs follows):

   ```promela
   [] (na <= nb);
   ```

   No violation (maybe because there is yet premature timeout)

## LIVENESS

3. Fairness assumption: if gcs ( or drone) send a message infinitely often, then gcs ( or drone ) should receive the message infinitely often
4. It should never be the case that drone and gcs wait for each other messages indefinitely (leading to deadlock) (I would not demonstrate this due to Note(a)).
5. Any data input by drone will eventually input by gcs (seq):

   ```promela
   [] (seqB[nb] -> <> seqA[na]);
   ```

   No violation occur

Moreover in my opinion, when we have already checked one property, and can be certain it is resolved or will never happen (such as property 4, where timeout and fairness solve it), we should leave it out of the verification to avoid state space explosion.

---

**Note_1:** Regarding 3 and 4, I have another question. Which one is more robust:

- a. If A is infinitely often enabled, it should send infinitely often. (this is because if A can keep sending, which mean it either receive message infinitely often or timeout infinitely often).
- b. If A sent message infinitely often, it should receive message from B infinitely often.

-> Are a and b two different things? Which one is more practical? (One thing I do know, enable deactivates partial order reduction).

**Note_2:** We have not considered the case where there are duplicate messages, and the protocol haven't considered the case where gcs `MISSION_ITEM_INT` message got lost. If so, violation would happen:
(Line 38 would fix this)

```
spin -t0 -p -g -l -s upload.pml

  1:	proc  0 (:init::1) upload.pml:17 (state 1)	[n0 = 0]
		:init:(0):n0 = 0
  2:	proc  0 (:init::1) upload.pml:18 (state 9)	[n1 = 1]
		:init:(0):n1 = 1
Starting gcs with pid 1
  3:	proc  0 (:init::1) upload.pml:20 (state 15)	[(run gcs(0,n0))]
Starting gcs with pid 2
  4:	proc  0 (:init::1) upload.pml:21 (state 16)	[(run gcs(1,n1))]
Starting drone with pid 3
  5:	proc  0 (:init::1) upload.pml:22 (state 17)	[(run drone(0))]
Starting drone with pid 4
  6:	proc  0 (:init::1) upload.pml:23 (state 18)	[(run drone(1))]
Starting loss with pid 5
  7:	proc  0 (:init::1) upload.pml:25 (state 19)	[(run loss())]
  8:	proc  2 (gcs:1) upload.pml:32 Send MISSION_COUNT,1,1	-> queue 1 (gcs2drone)
  8:	proc  2 (gcs:1) upload.pml:32 (state 1)	[gcs2drone!MISSION_COUNT,ctn,p]
		queue 1 (gcs2drone): [MISSION_COUNT,1,1]
  9:	proc  5 (loss:1) upload.pml:87 (state 1)	[gcs2drone?_,_,_]
		queue 1 (gcs2drone): 
 10:	proc  1 (gcs:1) upload.pml:32 Send MISSION_COUNT,0,0	-> queue 1 (gcs2drone)
 10:	proc  1 (gcs:1) upload.pml:32 (state 1)	[gcs2drone!MISSION_COUNT,ctn,p]
		queue 1 (gcs2drone): [MISSION_COUNT,0,0]
 11:	proc  5 (loss:1) upload.pml:87 (state 1)	[gcs2drone?_,_,_]
		queue 1 (gcs2drone): 
 12:	proc  2 (gcs:1) upload.pml:43 (state 10)	[(timeout)]
		queue 1 (gcs2drone): 
 13:	proc  2 (gcs:1) upload.pml:44 Send MISSION_COUNT,1,1	-> queue 1 (gcs2drone)
 13:	proc  2 (gcs:1) upload.pml:44 (state 11)	[gcs2drone!MISSION_COUNT,ctn,p]
		queue 1 (gcs2drone): [MISSION_COUNT,1,1]
 14:	proc  4 (drone:1) upload.pml:56 (state 1)	[gcs2drone?MISSION_COUNT,ctn,eval(p)]
		queue 1 (gcs2drone): 
		drone(4):ctn = 1
 15:	proc  4 (drone:1) upload.pml:60 (state 5)	[else]
		queue 1 (gcs2drone): 
 16:	proc  4 (drone:1) upload.pml:60 Send MISSION_REQUEST_INT,0,1	-> queue 2 (drone2gcs)
 16:	proc  4 (drone:1) upload.pml:60 (state 6)	[drone2gcs!MISSION_REQUEST_INT,seq,p]
		queue 1 (gcs2drone): 
		queue 2 (drone2gcs): [MISSION_REQUEST_INT,0,1]
 16:	proc  4 (drone:1) upload.pml:60 (state 7)	[assert((nb[p]<5))]
		queue 1 (gcs2drone): 
		queue 2 (drone2gcs): [MISSION_REQUEST_INT,0,1]
 16:	proc  4 (drone:1) upload.pml:60 (state 8)	[seqB[p].s[nb[p]] = seq]
		queue 1 (gcs2drone): 
		queue 2 (drone2gcs): [MISSION_REQUEST_INT,0,1]
 16:	proc  4 (drone:1) upload.pml:60 (state 9)	[nb[p] = (nb[p]+1)]
		queue 1 (gcs2drone): 
		queue 2 (drone2gcs): [MISSION_REQUEST_INT,0,1]
		nb[0] = 0
		nb[1] = 1
 17:	proc  5 (loss:1) upload.pml:89 (state 2)	[drone2gcs?_,_,_]
		queue 1 (gcs2drone): 
		queue 2 (drone2gcs): 
 18:	proc  1 (gcs:1) upload.pml:43 (state 10)	[(timeout)]
		queue 1 (gcs2drone): 
		queue 2 (drone2gcs): 
 19:	proc  1 (gcs:1) upload.pml:44 Send MISSION_COUNT,0,0	-> queue 1 (gcs2drone)
 19:	proc  1 (gcs:1) upload.pml:44 (state 11)	[gcs2drone!MISSION_COUNT,ctn,p]
		queue 1 (gcs2drone): [MISSION_COUNT,0,0]
		queue 2 (drone2gcs): 
 20:	proc  3 (drone:1) upload.pml:56 (state 1)	[gcs2drone?MISSION_COUNT,ctn,eval(p)]
		queue 1 (gcs2drone): 
		queue 2 (drone2gcs): 
		drone(3):ctn = 0
 21:	proc  3 (drone:1) upload.pml:59 (state 2)	[((ctn==0))]
		queue 1 (gcs2drone): 
		queue 2 (drone2gcs): 
 22:	proc  3 (drone:1) upload.pml:59 Send MISSION_ACK,0,0	-> queue 2 (drone2gcs)
 22:	proc  3 (drone:1) upload.pml:59 (state 3)	[drone2gcs!MISSION_ACK,0,p]
		queue 1 (gcs2drone): 
		queue 2 (drone2gcs): [MISSION_ACK,0,0]
 23:	proc  3 (drone:1) upload.pml:82 (state 32) <valid end state>	[(1)]
		queue 1 (gcs2drone): 
		queue 2 (drone2gcs): [MISSION_ACK,0,0]
 24:	proc  5 (loss:1) upload.pml:89 (state 2)	[drone2gcs?_,_,_]
		queue 1 (gcs2drone): 
		queue 2 (drone2gcs): 
 25:	proc  4 (drone:1) upload.pml:78 (state 27)	[(timeout)]
		queue 1 (gcs2drone): 
		queue 2 (drone2gcs): 
 26:	proc  4 (drone:1) upload.pml:79 Send MISSION_REQUEST_INT,0,1	-> queue 2 (drone2gcs)
 26:	proc  4 (drone:1) upload.pml:79 (state 28)	[drone2gcs!MISSION_REQUEST_INT,seq,p]
		queue 1 (gcs2drone): 
		queue 2 (drone2gcs): [MISSION_REQUEST_INT,0,1]
 27:	proc  2 (gcs:1) upload.pml:35 (state 2)	[drone2gcs?MISSION_REQUEST_INT,seq,eval(p)]
		queue 1 (gcs2drone): 
		queue 2 (drone2gcs): 
		gcs(2):seq = 0
 28:	proc  2 (gcs:1) upload.pml:38 Send MISSION_ITEM_INT,0,1	-> queue 1 (gcs2drone)
 28:	proc  2 (gcs:1) upload.pml:38 (state 3)	[gcs2drone!MISSION_ITEM_INT,seq,p]
		queue 1 (gcs2drone): [MISSION_ITEM_INT,0,1]
		queue 2 (drone2gcs): 
 28:	proc  2 (gcs:1) upload.pml:39 (state 4)	[assert((na[p]<5))]
		queue 1 (gcs2drone): [MISSION_ITEM_INT,0,1]
		queue 2 (drone2gcs): 
 28:	proc  2 (gcs:1) upload.pml:40 (state 5)	[seqA[p].s[na[p]] = seq]
		queue 1 (gcs2drone): [MISSION_ITEM_INT,0,1]
		queue 2 (drone2gcs): 
 28:	proc  2 (gcs:1) upload.pml:40 (state 6)	[na[p] = (na[p]+1)]
		queue 1 (gcs2drone): [MISSION_ITEM_INT,0,1]
		queue 2 (drone2gcs): 
		na[0] = 0
		na[1] = 1
 28:	proc  2 (gcs:1) upload.pml:41 (state 7)	[assert((seqA[p].s[(na[p]-1)]==seqB[p].s[(nb[p]-1)]))]
		queue 1 (gcs2drone): [MISSION_ITEM_INT,0,1]
		queue 2 (drone2gcs): 
		na[0] = 0
		na[1] = 1
 28:	proc  2 (gcs:1) upload.pml:41 (state 8)	[assert((seqA[p].s[(na[p]-1)]==(na[p]-1)))]
		queue 1 (gcs2drone): [MISSION_ITEM_INT,0,1]
		queue 2 (drone2gcs): 
		na[0] = 0
		na[1] = 1
 29:	proc  5 (loss:1) upload.pml:87 (state 1)	[gcs2drone?_,_,_]
		queue 1 (gcs2drone): 
		queue 2 (drone2gcs): 
 30:	proc  4 (drone:1) upload.pml:78 (state 27)	[(timeout)]
		queue 1 (gcs2drone): 
		queue 2 (drone2gcs): 
 31:	proc  4 (drone:1) upload.pml:79 Send MISSION_REQUEST_INT,0,1	-> queue 2 (drone2gcs)
 31:	proc  4 (drone:1) upload.pml:79 (state 28)	[drone2gcs!MISSION_REQUEST_INT,seq,p]
		queue 1 (gcs2drone): 
		queue 2 (drone2gcs): [MISSION_REQUEST_INT,0,1]
 32:	proc  2 (gcs:1) upload.pml:35 (state 2)	[drone2gcs?MISSION_REQUEST_INT,seq,eval(p)]
		queue 1 (gcs2drone): 
		queue 2 (drone2gcs): 
		gcs(2):seq = 0
 33:	proc  2 (gcs:1) upload.pml:38 Send MISSION_ITEM_INT,0,1	-> queue 1 (gcs2drone)
 33:	proc  2 (gcs:1) upload.pml:38 (state 3)	[gcs2drone!MISSION_ITEM_INT,seq,p]
		queue 1 (gcs2drone): [MISSION_ITEM_INT,0,1]
		queue 2 (drone2gcs): 
 33:	proc  2 (gcs:1) upload.pml:39 (state 4)	[assert((na[p]<5))]
		queue 1 (gcs2drone): [MISSION_ITEM_INT,0,1]
		queue 2 (drone2gcs): 
 33:	proc  2 (gcs:1) upload.pml:40 (state 5)	[seqA[p].s[na[p]] = seq]
		queue 1 (gcs2drone): [MISSION_ITEM_INT,0,1]
		queue 2 (drone2gcs): 
 33:	proc  2 (gcs:1) upload.pml:40 (state 6)	[na[p] = (na[p]+1)]
		queue 1 (gcs2drone): [MISSION_ITEM_INT,0,1]
		queue 2 (drone2gcs): 
		na[0] = 0
		na[1] = 2
 33:	proc  2 (gcs:1) upload.pml:41 (state 7)	[assert((seqA[p].s[(na[p]-1)]==seqB[p].s[(nb[p]-1)]))]
		queue 1 (gcs2drone): [MISSION_ITEM_INT,0,1]
		queue 2 (drone2gcs): 
		na[0] = 0
		na[1] = 2
spin: upload.pml:41, Error: assertion violated
spin: text of failed assertion: assert((seqA[p].s[(na[p]-1)]==(na[p]-1)))
 33:	proc  2 (gcs:1) upload.pml:41 (state 8)	[assert((seqA[p].s[(na[p]-1)]==(na[p]-1)))]
		queue 1 (gcs2drone): [MISSION_ITEM_INT,0,1]
		queue 2 (drone2gcs): 
		na[0] = 0
		na[1] = 2
spin: trail ends after 33 steps
#processes: 6
		queue 1 (gcs2drone): [MISSION_ITEM_INT,0,1]
		queue 2 (drone2gcs): 
		seqA[0].s[0] = 0
		seqA[0].s[1] = 0
		seqA[0].s[2] = 0
		seqA[0].s[3] = 0
		seqA[0].s[4] = 0
		seqA[1].s[0] = 0
		seqA[1].s[1] = 0
		seqA[1].s[2] = 0
		seqA[1].s[3] = 0
		seqA[1].s[4] = 0
		seqB[0].s[0] = 0
		seqB[0].s[1] = 0
		seqB[0].s[2] = 0
		seqB[0].s[3] = 0
		seqB[0].s[4] = 0
		seqB[1].s[0] = 0
		seqB[1].s[1] = 0
		seqB[1].s[2] = 0
		seqB[1].s[3] = 0
		seqB[1].s[4] = 0
		na[0] = 0
		na[1] = 2
		nb[0] = 0
		nb[1] = 1
 33:	proc  5 (loss:1) upload.pml:86 (state 3) <valid end state>
 33:	proc  4 (drone:1) upload.pml:63 (state 29)
		drone(4):ctn = 1
		drone(4):seq = 0
		drone(4):p = 1
 33:	proc  3 (drone:1) upload.pml:82 (state 33) <valid end state>
		drone(3):ctn = 0
		drone(3):seq = 0
		drone(3):p = 0
 33:	proc  2 (gcs:1) upload.pml:34 (state 14)
		gcs(2):seq = 0
		gcs(2):ctn = 1
		gcs(2):p = 1
 33:	proc  1 (gcs:1) upload.pml:34 (state 14)
		gcs(1):seq = 0
		gcs(1):ctn = 0
		gcs(1):p = 0
 33:	proc  0 (:init::1) upload.pml:27 (state 21) <valid end state>
		:init:(0):n1 = 1
		:init:(0):n0 = 0
6 processes created
```

(interesting case to interpret)
