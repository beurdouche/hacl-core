module LowStar.Monotonic.Buffer64

module P = FStar.Preorder
module G = FStar.Ghost
module U64 = FStar.UInt64
module Seq = FStar.Seq

module HS = FStar.HyperStack
module HST = FStar.HyperStack.ST

module LMB = LowStar.Monotonic.Buffer

private let srel_to_lsrel (#a:Type0) (len:nat) (pre:srel a) :P.preorder (Seq.lseq a len) = fun s1 s2 -> pre s1 s2

(*
 * Counterpart of compatible_sub from the fsti but using sequences
 *
 * The patterns are guarded tightly, the proof of transitivity gets quite flaky otherwise
 * The cost is that we have to additional asserts as triggers
 *)
let compatible_sub_preorder (#a:Type0)
  (len:nat) (rel:srel a) (i:nat) (j:nat{i <= j /\ j <= len}) (sub_rel:srel a)
  = (forall (s1 s2:Seq.seq a). {:pattern (rel s1 s2); (sub_rel (Seq.slice s1 i j) (Seq.slice s2 i j))}
                         (Seq.length s1 == len /\ Seq.length s2 == len /\ rel s1 s2) ==>
		         (sub_rel (Seq.slice s1 i j) (Seq.slice s2 i j))) /\
    (forall (s s2:Seq.seq a). {:pattern (sub_rel (Seq.slice s i j) s2); (rel s (Seq.replace_subseq s i j s2))}
                        (Seq.length s == len /\ Seq.length s2 == j - i /\ sub_rel (Seq.slice s i j) s2) ==>
  		        (rel s (Seq.replace_subseq s i j s2)))

(*
 * Reflexivity of the compatibility relation
 *)
let lemma_seq_sub_compatilibity_is_reflexive (#a:Type0) (len:nat) (rel:srel a)
  :Lemma (compatible_sub_preorder len rel 0 len rel)
  = assert (forall (s1 s2:Seq.seq a). Seq.length s1 == Seq.length s2 ==>
                                 Seq.equal (Seq.replace_subseq s1 0 (Seq.length s1) s2) s2)

(*
 * Transitivity of the compatibility relation
 *
 * i2 and j2 are relative offsets within [i1, j1) (i.e. assuming i1 = 0)
 *)
let lemma_seq_sub_compatibility_is_transitive (#a:Type0)
  (len:nat) (rel:srel a) (i1 j1:nat) (rel1:srel a) (i2 j2:nat) (rel2:srel a)
  :Lemma (requires (i1 <= j1 /\ j1 <= len /\ i2 <= j2 /\ j2 <= j1 - i1 /\
                    compatible_sub_preorder len rel i1 j1 rel1 /\
                    compatible_sub_preorder (j1 - i1) rel1 i2 j2 rel2))
	 (ensures  (compatible_sub_preorder len rel (i1 + i2) (i1 + j2) rel2))
  = let t1 (s1 s2:Seq.seq a) = Seq.length s1 == len /\ Seq.length s2 == len /\ rel s1 s2 in
    let t2 (s1 s2:Seq.seq a) = t1 s1 s2 /\ rel2 (Seq.slice s1 (i1 + i2) (i1 + j2)) (Seq.slice s2 (i1 + i2) (i1 + j2)) in

    let aux0 (s1 s2:Seq.seq a) :Lemma (t1 s1 s2 ==> t2 s1 s2)
      = Classical.arrow_to_impl #(t1 s1 s2) #(t2 s1 s2)
          (fun _ ->
           assert (rel1 (Seq.slice s1 i1 j1) (Seq.slice s2 i1 j1));
	   assert (rel2 (Seq.slice (Seq.slice s1 i1 j1) i2 j2) (Seq.slice (Seq.slice s2 i1 j1) i2 j2));
	   assert (Seq.equal (Seq.slice (Seq.slice s1 i1 j1) i2 j2) (Seq.slice s1 (i1 + i2) (i1 + j2)));
	   assert (Seq.equal (Seq.slice (Seq.slice s2 i1 j1) i2 j2) (Seq.slice s2 (i1 + i2) (i1 + j2))))
    in


    let t1 (s s2:Seq.seq a) = Seq.length s == len /\ Seq.length s2 == j2 - i2 /\
                              rel2 (Seq.slice s (i1 + i2) (i1 + j2)) s2 in
    let t2 (s s2:Seq.seq a) = t1 s s2 /\ rel s (Seq.replace_subseq s (i1 + i2) (i1 + j2) s2) in
    let aux1 (s s2:Seq.seq a) :Lemma (t1 s s2 ==> t2 s s2)
      = Classical.arrow_to_impl #(t1 s s2) #(t2 s s2)
          (fun _ ->
           assert (Seq.equal (Seq.slice s (i1 + i2) (i1 + j2)) (Seq.slice (Seq.slice s i1 j1) i2 j2));
           assert (rel1 (Seq.slice s i1 j1) (Seq.replace_subseq (Seq.slice s i1 j1) i2 j2 s2));
	   assert (rel s (Seq.replace_subseq s i1 j1 (Seq.replace_subseq (Seq.slice s i1 j1) i2 j2 s2)));
	   assert (Seq.equal (Seq.replace_subseq s i1 j1 (Seq.replace_subseq (Seq.slice s i1 j1) i2 j2 s2))
	                     (Seq.replace_subseq s (i1 + i2) (i1 + j2) s2)))
    in

    Classical.forall_intro_2 aux0; Classical.forall_intro_2 aux1

noeq type mbuffer (a:Type0) (rrel:srel a) (rel:srel a) :Type0 =
  | Null
  | Buffer:
    max_length:U64.t ->
    content:HST.mreference (Seq.lseq a (U64.v max_length)) (srel_to_lsrel (U64.v max_length) rrel) ->
    idx:U64.t ->
    length:U64.t{U64.v idx + U64.v length <= U64.v max_length} ->
    compatible:squash (compatible_sub_preorder (U64.v max_length) rrel
                                               (U64.v idx) (U64.v idx + U64.v length) rel) ->  //proof of compatibility
    mbuffer a rrel rel

let g_is_null #_ #_ #_ b = Null? b

let mnull #_ #_ #_ = Null

let null_unique #_ #_ #_ _ = ()

let unused_in #_ #_ #_ b h =
  match b with
  | Null -> False
  | Buffer _ content _ _ _ -> content `HS.unused_in` h

let live #_ #_ #_ h b =
  match b with
  | Null -> True
  | Buffer _ content _ _ _ -> h `HS.contains` content

let live_null _ _ _ _ = ()

let live_not_unused_in #_ #_ #_ _ _ = ()

let lemma_live_equal_mem_domains #_ #_ #_ _ _ _ = ()

let frameOf #_ #_ #_ b = if Null? b then HS.root else HS.frameOf (Buffer?.content b)

let as_addr #_ #_ #_  b = if g_is_null b then 0 else HS.as_addr (Buffer?.content b)

let unused_in_equiv #_ #_ #_ b h =
  if g_is_null b then Heap.not_addr_unused_in_nullptr (Map.sel (HS.get_hmap h) HS.root) else ()

let live_region_frameOf #_ #_ #_ _ _ = ()

let len #_ #_ #_ b =
  match b with
  | Null -> 0UL
  | Buffer _ _ _ len _ -> len

let len_null a _ _ = ()

let as_seq #_ #_ #_ h b =
  match b with
  | Null -> Seq.empty
  | Buffer max_len content idx len _ ->
    Seq.slice (HS.sel h content) (U64.v idx) (U64.v idx + U64.v len)

let length_as_seq #_ #_ #_ _ _ = ()

let mgsub #a #rrel #rel sub_rel b i len =
  match b with
  | Null -> Null
  | Buffer max_len content idx length () ->
    lemma_seq_sub_compatibility_is_transitive (U64.v max_len) rrel
                                              (U64.v idx) (U64.v idx + U64.v length) rel
		         	              (U64.v i) (U64.v i + U64.v len) sub_rel;
    Buffer max_len content (U64.add idx i) len ()

let live_gsub #_ #_ #_ _ _ _ _ _ = ()

let gsub_is_null #_ #_ #_ _ _ _ _ = ()

let len_gsub #_ #_ #_ _ _ _ _ = ()

let frameOf_gsub #_ #_ #_ _ _ _ _ = ()

let as_addr_gsub #_ #_ #_ _ _ _ _ = ()

let mgsub_inj #_ #_ #_ _ _ _ _ _ _ _ _ = ()

#push-options "--z3rlimit 20"
let gsub_gsub #_ #_ #rel b i1 len1 sub_rel1 i2 len2 sub_rel2 =
  lemma_seq_sub_compatibility_is_transitive (length b) rel (U64.v i1) (U64.v i1 + U64.v len1) sub_rel1
                                            (U64.v i2) (U64.v i2 + U64.v len2) sub_rel2
#pop-options

/// A buffer ``b`` is equal to its "largest" sub-buffer, at index 0 and
/// length ``len b``.

let gsub_zero_length #_ #_ #rel b = lemma_seq_sub_compatilibity_is_reflexive (length b) rel

let as_seq_gsub #_ #_ #_ h b i len _ =
  match b with
  | Null -> ()
  | Buffer _ content idx len0 _ ->
    Seq.slice_slice (HS.sel h content) (U64.v idx) (U64.v idx + U64.v len0) (U64.v i) (U64.v i + U64.v len)

(* Untyped view of buffers, used only to implement the generic modifies clause. DO NOT USE in client code. *)

friend LowStar.Monotonic.Buffer

let ubuffer_of_buffer' (#a:Type0) (#rrel:srel a) (#rel:srel a) (b:mbuffer a rrel rel)
  :Tot (LMB.ubuffer (frameOf b) (as_addr b))
  = if Null? b
    then
      Ghost.hide ({
        LMB.b_max_length = 0;
        LMB.b_offset = 0;
        LMB.b_length = 0;
        LMB.b_is_mm = false;
      })
    else
      Ghost.hide ({
        LMB.b_max_length = U64.v (Buffer?.max_length b);
        LMB.b_offset = U64.v (Buffer?.idx b);
        LMB.b_length = U64.v (Buffer?.length b);
        LMB.b_is_mm = HS.is_mm (Buffer?.content b);
    })

let ubuffer_preserved'
  (#r: HS.rid)
  (#a: nat)
  (b: LMB.ubuffer r a)
  (h h' : HS.mem)
: GTot Type0
= forall (t':Type0) (rrel rel:srel t') (b':mbuffer t' rrel rel) .
  (frameOf b' == r /\ as_addr b' == a /\ ubuffer_of_buffer' b' == b /\ live h b') ==>
  (live h' b' /\ Seq.equal (as_seq h' b') (as_seq h b'))

val ubuffer_of_buffer (#a:Type0) (#rrel:srel a) (#rel:srel a) (b:mbuffer a rrel rel) :Tot (LMB.ubuffer (frameOf b) (as_addr b))
let ubuffer_of_buffer #_ #_ #_ b = ubuffer_of_buffer' b

val ubuffer_preserved_elim (#a:Type0) (#rrel:srel a) (#rel:srel a) (b:mbuffer a rrel rel) (h h':HS.mem)
  :Lemma (requires (LMB.ubuffer_preserved #(frameOf b) #(as_addr b) (ubuffer_of_buffer b) h h' /\ live h b))
         (ensures (live h' b /\ as_seq h b == as_seq h' b))
let ubuffer_preserved_elim #a #rrel #rel b h h' = admit()

let unused_in_ubuffer_preserved (#a:Type0) (#rrel:srel a) (#rel:srel a)
  (b:mbuffer a rrel rel) (h h':HS.mem)
  : Lemma (requires (b `unused_in` h))
          (ensures (LMB.ubuffer_preserved #(frameOf b) #(as_addr b) (ubuffer_of_buffer b) h h'))
  = Classical.move_requires (fun b -> live_not_unused_in h b) b;
    live_null a rrel rel h;
    null_unique b;
    unused_in_equiv b h;
    LMB.addr_unused_in_ubuffer_preserved #(frameOf b) #(as_addr b) (ubuffer_of_buffer b) h h'

val liveness_preservation_intro (#a:Type0) (#rrel:srel a) (#rel:srel a)
  (h h':HS.mem) (b:mbuffer a rrel rel)
  (f: (
    (t':Type0) ->
    (pre: Preorder.preorder t') ->
    (r: HS.mreference t' pre) ->
    Lemma
    (requires (HS.frameOf r == frameOf b /\ HS.as_addr r == as_addr b /\ h `HS.contains` r))
    (ensures (h' `HS.contains` r))
  ))
  :Lemma (requires (live h b)) (ensures (live h' b))
let liveness_preservation_intro #_ #_ #_ _ _ b f =
  if Null? b
  then ()
  else f _ _ (Buffer?.content b)

let modifies_1_preserves_mreferences (#a:Type0) (#rrel:srel a) (#rel:srel a) (b:mbuffer a rrel rel) (h1 h2:HS.mem)
  :GTot Type0
  = forall (a':Type) (pre:Preorder.preorder a') (r':HS.mreference  a' pre).
      ((frameOf b <> HS.frameOf r' \/ as_addr b <> HS.as_addr r') /\ h1 `HS.contains` r') ==>
      (h2 `HS.contains` r' /\ HS.sel h1 r' == HS.sel h2 r')

let modifies_1_preserves_ubuffers (#a:Type0) (#rrel:srel a) (#rel:srel a) (b:mbuffer a rrel rel) (h1 h2:HS.mem)
  : GTot Type0
  = forall (b':LMB.ubuffer (frameOf b) (as_addr b)).
      (LMB.ubuffer_disjoint #(frameOf b) #(as_addr b) (ubuffer_of_buffer b) b') ==> LMB.ubuffer_preserved #(frameOf b) #(as_addr b) b' h1 h2

let modifies_1_preserves_livenesses (#a:Type0) (#rrel:srel a) (#rel:srel a) (b:mbuffer a rrel rel) (h1 h2:HS.mem)
  : GTot Type0
  = forall (a':Type) (pre:Preorder.preorder a') (r':HS.mreference  a' pre). h1 `HS.contains` r' ==> h2 `HS.contains` r'

let modifies_1' (#a:Type0) (#rrel:srel a) (#rel:srel a) (b:mbuffer a rrel rel) (h1 h2:HS.mem)
  : GTot Type0
  = LMB.modifies_0_preserves_regions h1 h2 /\
    modifies_1_preserves_mreferences b h1 h2 /\
    modifies_1_preserves_livenesses b h1 h2 /\
    LMB.modifies_0_preserves_not_unused_in h1 h2 /\
    modifies_1_preserves_ubuffers b h1 h2

val modifies_1 (#a:Type0) (#rrel:srel a) (#rel:srel a) (b:mbuffer a rrel rel) (h1 h2:HS.mem) :GTot Type0
let modifies_1 = modifies_1'

val modifies_1_live_region (#a:Type0) (#rrel:srel a) (#rel:srel a) (b:mbuffer a rrel rel) (h1 h2:HS.mem) (r:HS.rid)
  :Lemma (requires (modifies_1 b h1 h2 /\ HS.live_region h1 r)) (ensures (HS.live_region h2 r))
let modifies_1_live_region #_ #_ #_ _ _ _ _ = ()

val modifies_1_liveness
  (#a:Type0) (#rrel:srel a) (#rel:srel a) (b:mbuffer a rrel rel) (h1 h2:HS.mem)
  (#a':Type0) (#pre:Preorder.preorder a') (r':HS.mreference a' pre)
  :Lemma (requires (modifies_1 b h1 h2 /\ h1 `HS.contains` r')) (ensures (h2 `HS.contains` r'))
let modifies_1_liveness #_ #_ #_ _ _ _ #_ #_ _ = ()

val modifies_1_unused_in (#a:Type0) (#rrel:srel a) (#rel:srel a) (b:mbuffer a rrel rel) (h1 h2:HS.mem) (r:HS.rid) (n:nat)
  :Lemma (requires (modifies_1 b h1 h2 /\
                    HS.live_region h1 r /\ HS.live_region h2 r /\
                    n `Heap.addr_unused_in` (HS.get_hmap h2 `Map.sel` r)))
         (ensures (n `Heap.addr_unused_in` (HS.get_hmap h1 `Map.sel` r)))
let modifies_1_unused_in #_ #_ #_ _ _ _ _ _ = ()

val modifies_1_mreference
  (#a:Type0) (#rrel:srel a) (#rel:srel a) (b:mbuffer a rrel rel) (h1 h2:HS.mem)
  (#a':Type0) (#pre:Preorder.preorder a') (r': HS.mreference a' pre)
  : Lemma (requires (modifies_1 b h1 h2 /\ (frameOf b <> HS.frameOf r' \/ as_addr b <> HS.as_addr r') /\ h1 `HS.contains` r'))
          (ensures (h2 `HS.contains` r' /\ h1 `HS.sel` r' == h2 `HS.sel` r'))
let modifies_1_mreference #_ #_ #_ _ _ _ #_ #_ _ = ()

val modifies_1_ubuffer (#a:Type0) (#rrel:srel a) (#rel:srel a)
  (b:mbuffer a rrel rel) (h1 h2:HS.mem) (b':LMB.ubuffer (frameOf b) (as_addr b))
  : Lemma (requires (modifies_1 b h1 h2 /\ LMB.ubuffer_disjoint #(frameOf b) #(as_addr b) (ubuffer_of_buffer b) b'))
          (ensures  (LMB.ubuffer_preserved #(frameOf b) #(as_addr b) b' h1 h2))
let modifies_1_ubuffer #_ #_ #_ _ _ _ _ = ()

val modifies_1_null (#a:Type0) (#rrel:srel a) (#rel:srel a)
  (b:mbuffer a rrel rel) (h1 h2:HS.mem)
  : Lemma (requires (modifies_1 b h1 h2 /\ g_is_null b))
          (ensures  (LMB.modifies_0 h1 h2))
let modifies_1_null #_ #_ #_ _ _ _ = ()

let modifies_addr_of_preserves_not_unused_in (#a:Type0) (#rrel:srel a) (#rel:srel a) (b:mbuffer a rrel rel) (h1 h2:HS.mem)
  :GTot Type0
  = forall (r: HS.rid) (n: nat) .
      ((r <> frameOf b \/ n <> as_addr b) /\
       HS.live_region h1 r /\ HS.live_region h2 r /\
       n `Heap.addr_unused_in` (HS.get_hmap h2 `Map.sel` r)) ==>
      (n `Heap.addr_unused_in` (HS.get_hmap h1 `Map.sel` r))

let modifies_addr_of' (#a:Type0) (#rrel:srel a) (#rel:srel a) (b:mbuffer a rrel rel) (h1 h2:HS.mem) :GTot Type0 =
  LMB.modifies_0_preserves_regions h1 h2 /\
  modifies_1_preserves_mreferences b h1 h2 /\
  modifies_addr_of_preserves_not_unused_in b h1 h2

val modifies_addr_of (#a:Type0) (#rrel:srel a) (#rel:srel a) (b:mbuffer a rrel rel) (h1 h2:HS.mem) :GTot Type0
let modifies_addr_of = modifies_addr_of'

val modifies_addr_of_live_region (#a:Type0) (#rrel:srel a) (#rel:srel a)
  (b:mbuffer a rrel rel) (h1 h2:HS.mem) (r:HS.rid)
  :Lemma (requires (modifies_addr_of b h1 h2 /\ HS.live_region h1 r))
         (ensures (HS.live_region h2 r))
let modifies_addr_of_live_region #_ #_ #_ _ _ _ _ = ()

val modifies_addr_of_mreference (#a:Type0) (#rrel:srel a) (#rel:srel a)
  (b:mbuffer a rrel rel) (h1 h2:HS.mem)
  (#a':Type0) (#pre:Preorder.preorder a') (r':HS.mreference a' pre)
  : Lemma (requires (modifies_addr_of b h1 h2 /\ (frameOf b <> HS.frameOf r' \/ as_addr b <> HS.as_addr r') /\ h1 `HS.contains` r'))
          (ensures (h2 `HS.contains` r' /\ h1 `HS.sel` r' == h2 `HS.sel` r'))
let modifies_addr_of_mreference #_ #_ #_ _ _ _ #_ #_ _ = ()

val modifies_addr_of_unused_in (#a:Type0) (#rrel:srel a) (#rel:srel a)
  (b:mbuffer a rrel rel) (h1 h2:HS.mem) (r:HS.rid) (n:nat)
  : Lemma (requires (modifies_addr_of b h1 h2 /\
                     (r <> frameOf b \/ n <> as_addr b) /\
                     HS.live_region h1 r /\ HS.live_region h2 r /\
                     n `Heap.addr_unused_in` (HS.get_hmap h2 `Map.sel` r)))
          (ensures (n `Heap.addr_unused_in` (HS.get_hmap h1 `Map.sel` r)))
let modifies_addr_of_unused_in #_ #_ #_ _ _ _ _ _ = ()

module MG = FStar.ModifiesGen

let loc_buffer #a #rrel #rel b =
  if g_is_null b then MG.loc_none
  else MG.loc_of_aloc #_ #_ #(frameOf b) #(as_addr b) (ubuffer_of_buffer b)

let loc_buffer_null _ _ _ = ()

val loc_includes_buffer (#a:Type0) (#rrel1:srel a) (#rrel2:srel a) (#rel1:srel a) (#rel2:srel a)
  (b1:mbuffer a rrel1 rel1) (b2:mbuffer a rrel2 rel2)
  :Lemma (requires (frameOf b1 == frameOf b2 /\ as_addr b1 == as_addr b2 /\
                    LMB.ubuffer_includes0 #(frameOf b1) #(frameOf b2) #(as_addr b1) #(as_addr b2) (ubuffer_of_buffer b1) (ubuffer_of_buffer b2)))
         (ensures  (LMB.loc_includes (loc_buffer b1) (loc_buffer b2)))
let loc_includes_buffer  #t #_ #_ #_ #_ b1 b2 =
  let t1 = LMB.ubuffer (frameOf b1) (as_addr b1) in
  MG.loc_includes_aloc #_ #LMB.cls #(frameOf b1) #(as_addr b1) (ubuffer_of_buffer b1) (ubuffer_of_buffer b2 <: t1)

let loc_includes_gsub_buffer_r l #_ #_ #_ b i len sub_rel =
  let b' = mgsub sub_rel b i len in
  loc_includes_buffer b b';
  LMB.loc_includes_trans l (loc_buffer b) (loc_buffer b')

let loc_includes_gsub_buffer_l #_ #_ #rel b i1 len1 sub_rel1 i2 len2 sub_rel2 =
  let b1 = mgsub sub_rel1 b i1 len1 in
  let b2 = mgsub sub_rel2 b i2 len2 in
  loc_includes_buffer b1 b2

#push-options "--z3rlimit 20"
let loc_includes_as_seq #_ #rrel1 #rrel2 #_ #_ h1 h2 larger smaller =
  if Null? smaller then () else
  if Null? larger then begin
    MG.loc_includes_none_elim (loc_buffer smaller);
    MG.loc_of_aloc_not_none #_ #LMB.cls #(frameOf smaller) #(as_addr smaller) (ubuffer_of_buffer smaller)
  end else begin
    MG.loc_includes_aloc_elim #_ #LMB.cls #(frameOf larger) #(frameOf smaller) #(as_addr larger) #(as_addr smaller) (ubuffer_of_buffer larger) (ubuffer_of_buffer smaller);
    assume (rrel1 == rrel2);  //TODO: we should be able to prove this somehow in HS?
    let ul = Ghost.reveal (ubuffer_of_buffer larger) in
    let us = Ghost.reveal (ubuffer_of_buffer smaller) in
    assert (as_seq h1 smaller == Seq.slice (as_seq h1 larger) (us.LMB.b_offset - ul.LMB.b_offset) (us.LMB.b_offset - ul.LMB.b_offset + length smaller));
    assert (as_seq h2 smaller == Seq.slice (as_seq h2 larger) (us.LMB.b_offset - ul.LMB.b_offset) (us.LMB.b_offset - ul.LMB.b_offset + length smaller))
  end
#pop-options

let loc_includes_addresses_buffer #_ #_ #_ preserve_liveness r s p =
  MG.loc_includes_addresses_aloc #_ #LMB.cls preserve_liveness r s #(as_addr p) (ubuffer_of_buffer p)

let loc_includes_region_buffer #_ #_ #_ preserve_liveness s b =
  MG.loc_includes_region_aloc #_ #LMB.cls preserve_liveness s #(frameOf b) #(as_addr b) (ubuffer_of_buffer b)

val loc_disjoint_buffer (#a1 #a2:Type0) (#rrel1 #rel1:srel a1) (#rrel2 #rel2:srel a2)
  (b1:mbuffer a1 rrel1 rel1) (b2:mbuffer a2 rrel2 rel2)
  :Lemma (requires ((frameOf b1 == frameOf b2 /\ as_addr b1 == as_addr b2) ==>
                    LMB.ubuffer_disjoint0 #(frameOf b1) #(frameOf b2) #(as_addr b1) #(as_addr b2) (ubuffer_of_buffer b1) (ubuffer_of_buffer b2)))
         (ensures (LMB.loc_disjoint (loc_buffer b1) (loc_buffer b2)))
let loc_disjoint_buffer #_ #_ #_ #_ #_ #_ b1 b2 =
  MG.loc_disjoint_aloc_intro #_ #LMB.cls #(frameOf b1) #(as_addr b1) #(frameOf b2) #(as_addr b2) (ubuffer_of_buffer b1) (ubuffer_of_buffer b2)

let loc_disjoint_gsub_buffer #_ #_ #_ b i1 len1 sub_rel1 i2 len2 sub_rel2 =
  loc_disjoint_buffer (mgsub sub_rel1 b i1 len1) (mgsub sub_rel2 b i2 len2)

let modifies_buffer_elim #_ #_ #_ b p h h' =
  if g_is_null b
  then
    assert (as_seq h b `Seq.equal` as_seq h' b)
  else begin
    MG.modifies_aloc_elim #_ #LMB.cls #(frameOf b) #(as_addr b) (ubuffer_of_buffer b) p h h' ;
    ubuffer_preserved_elim b h h'
  end

let address_liveness_insensitive_buffer #_ #_ #_ b =
  MG.loc_includes_address_liveness_insensitive_locs_aloc #_ #LMB.cls #(frameOf b) #(as_addr b) (ubuffer_of_buffer b)

let address_liveness_insensitive_addresses =
  MG.loc_includes_address_liveness_insensitive_locs_addresses LMB.cls

let region_liveness_insensitive_buffer #_ #_ #_ b =
  MG.loc_includes_region_liveness_insensitive_locs_loc_of_aloc #_ LMB.cls #(frameOf b) #(as_addr b) (ubuffer_of_buffer b)

let region_liveness_insensitive_addresses =
  MG.loc_includes_region_liveness_insensitive_locs_loc_addresses LMB.cls

let region_liveness_insensitive_regions =
  MG.loc_includes_region_liveness_insensitive_locs_loc_regions LMB.cls

let region_liveness_insensitive_address_liveness_insensitive =
  MG.loc_includes_region_liveness_insensitive_locs_address_liveness_insensitive_locs LMB.cls

let modifies_liveness_insensitive_buffer l1 l2 h h' #_ #_ #_ x =
  if g_is_null x then ()
  else
    liveness_preservation_intro h h' x (fun t' pre r ->
      MG.modifies_preserves_liveness_strong l1 l2 h h' r (ubuffer_of_buffer x))

let modifies_liveness_insensitive_region_buffer l1 l2 h h' #_ #_ #_ x =
  if g_is_null x then ()
  else MG.modifies_preserves_region_liveness_aloc l1 l2 h h' #(frameOf x) #(as_addr x) (ubuffer_of_buffer x)

val modifies_1_modifies
  (#a:Type0)(#rrel #rel:srel a)
  (b:mbuffer a rrel rel) (h1 h2:HS.mem)
  :Lemma (requires (modifies_1 b h1 h2))
         (ensures  (LMB.modifies (loc_buffer b) h1 h2))
let modifies_1_modifies #t #_ #_ b h1 h2 =
  if g_is_null b
  then begin
    modifies_1_null b h1 h2;
    LMB.modifies_0_modifies h1 h2
  end else
   MG.modifies_intro (loc_buffer b) h1 h2
    (fun r -> modifies_1_live_region b h1 h2 r)
    (fun t pre p ->
      LMB.loc_disjoint_sym (LMB.loc_mreference p) (loc_buffer b);
      MG.loc_disjoint_aloc_addresses_elim #_ #LMB.cls #(frameOf b) #(as_addr b) (ubuffer_of_buffer b) true (HS.frameOf p) (Set.singleton (HS.as_addr p));
      modifies_1_mreference b h1 h2 p
    )
    (fun t pre p ->
      modifies_1_liveness b h1 h2 p
    )
    (fun r n ->
      modifies_1_unused_in b h1 h2 r n
    )
    (fun r' a' b' ->
      LMB.loc_disjoint_sym (MG.loc_of_aloc b') (loc_buffer b);
      MG.loc_disjoint_aloc_elim #_ #LMB.cls #(frameOf b) #(as_addr b)  #r' #a' (ubuffer_of_buffer b)  b';
      if frameOf b = r' && as_addr b = a'
      then
        modifies_1_ubuffer #t b h1 h2 b'
      else
        LMB.same_mreference_ubuffer_preserved #r' #a' b' h1 h2
          (fun a_ pre_ r_ -> modifies_1_mreference b h1 h2 r_)
    )

val modifies_addr_of_modifies
  (#a:Type0) (#rrel #rel:srel a)
  (b:mbuffer a rrel rel) (h1 h2:HS.mem)
  :Lemma (requires (modifies_addr_of b h1 h2))
         (ensures  (LMB.modifies (loc_addr_of_buffer b) h1 h2))
let modifies_addr_of_modifies #t #_ #_ b h1 h2 =
  MG.modifies_address_intro #_ #LMB.cls (frameOf b) (as_addr b) h1 h2
    (fun r -> modifies_addr_of_live_region b h1 h2 r)
    (fun t pre p ->
      modifies_addr_of_mreference b h1 h2 p
    )
    (fun r n ->
      modifies_addr_of_unused_in b h1 h2 r n
    )

let does_not_contain_addr = MG.does_not_contain_addr

let not_live_region_does_not_contain_addr = MG.not_live_region_does_not_contain_addr

let unused_in_does_not_contain_addr = MG.unused_in_does_not_contain_addr

let addr_unused_in_does_not_contain_addr = MG.addr_unused_in_does_not_contain_addr

let loc_unused_in_not_unused_in_disjoint =
  MG.loc_unused_in_not_unused_in_disjoint LMB.cls

let not_live_region_loc_not_unused_in_disjoint = MG.not_live_region_loc_not_unused_in_disjoint LMB.cls

let live_loc_not_unused_in #_ #_ #_ b h =
  unused_in_equiv b h;
  Classical.move_requires (MG.does_not_contain_addr_addr_unused_in h) (frameOf b, as_addr b);
  MG.loc_addresses_not_unused_in LMB.cls (frameOf b) (Set.singleton (as_addr b)) h;
  ()

let unused_in_loc_unused_in #_ #_ #_ b h =
  unused_in_equiv b h;
  Classical.move_requires (MG.addr_unused_in_does_not_contain_addr h) (frameOf b, as_addr b);
  MG.loc_addresses_unused_in LMB.cls (frameOf b) (Set.singleton (as_addr b)) h;
  ()

let modifies_inert_liveness_insensitive_buffer_weak = modifies_liveness_insensitive_buffer_weak

let modifies_inert_liveness_insensitive_region_buffer_weak = modifies_liveness_insensitive_region_buffer_weak

let disjoint_neq #_ #_ #_ #_ #_ #_ b1 b2 =
  if frameOf b1 = frameOf b2 && as_addr b1 = as_addr b2 then
    MG.loc_disjoint_aloc_elim #_ #LMB.cls #(frameOf b1) #(as_addr b1) #(frameOf b2) #(as_addr b2) (ubuffer_of_buffer b1) (ubuffer_of_buffer b2)
  else ()

let includes_live #a #rrel #rel1 #rel2 h larger smaller =
  if Null? larger || Null? smaller then ()
  else
    MG.loc_includes_aloc_elim #_ #LMB.cls #(frameOf larger) #(frameOf smaller) #(as_addr larger) #(as_addr smaller) (ubuffer_of_buffer larger) (ubuffer_of_buffer smaller)

let includes_frameOf_as_addr #_ #_ #_ #_ #_ #_ larger smaller =
  if Null? larger || Null? smaller then ()
  else
    MG.loc_includes_aloc_elim #_ #LMB.cls #(frameOf larger) #(frameOf smaller) #(as_addr larger) #(as_addr smaller) (ubuffer_of_buffer larger) (ubuffer_of_buffer smaller)

let pointer_distinct_sel_disjoint #a #_ #_ #_ #_ b1 b2 h =
  if frameOf b1 = frameOf b2 && as_addr b1 = as_addr b2
  then begin
    HS.mreference_distinct_sel_disjoint h (Buffer?.content b1) (Buffer?.content b2);
    loc_disjoint_buffer b1 b2
  end
  else
    loc_disjoint_buffer b1 b2

let is_null #_ #_ #_ b = Null? b

let msub #a #rrel #rel sub_rel b i len =
  match b with
  | Null -> Null
  | Buffer max_len content i0 len0 () ->
    lemma_seq_sub_compatibility_is_transitive (U64.v max_len) rrel (U64.v i0) (U64.v i0 + U64.v len0) rel
                                              (U64.v i) (U64.v i + U64.v len) sub_rel;
    Buffer max_len content (U64.add i0 i) len ()

let moffset #a #rrel #rel sub_rel b i =
  match b with
  | Null -> Null
  | Buffer max_len content i0 len () ->
    lemma_seq_sub_compatibility_is_transitive (U64.v max_len) rrel (U64.v i0) (U64.v i0 + U64.v len) rel
                                              (U64.v i) (U64.v i + U64.v (U64.sub len i)) sub_rel;
    Buffer max_len content (U64.add i0 i) (U64.sub len i) ()

let index #_ #_ #_ b i =
  let open HST in
  let s = ! (Buffer?.content b) in
  Seq.index s (U64.v (Buffer?.idx b) + U64.v i)

let g_upd_seq #_ #_ #_ b s h =
  if Seq.length s = 0 then h
  else
    let s0 = HS.sel h (Buffer?.content b) in
    let Buffer _ content idx length () = b in
    HS.upd h (Buffer?.content b) (Seq.replace_subseq s0 (U64.v idx) (U64.v idx + U64.v length) s)

let lemma_g_upd_with_same_seq #_ #_ #_ b h =
  if Null? b then ()
  else
    let open FStar.UInt64 in
    let Buffer _ content idx length () = b in
    let s = HS.sel h content in
    assert (Seq.equal (Seq.replace_subseq s (v idx) (v idx + v length) (Seq.slice s (v idx) (v idx + v length))) s);
    HS.lemma_heap_equality_upd_with_sel h (Buffer?.content b)

#push-options "--z3rlimit 48"
let g_upd_seq_as_seq #_ #_ #_ b s h =
  let h' = g_upd_seq b s h in
  if g_is_null b then assert (Seq.equal s Seq.empty)
  else begin
    assert (Seq.equal (as_seq h' b) s);
    // prove modifies_1_preserves_ubuffers
    Heap.lemma_distinct_addrs_distinct_preorders ();
    Heap.lemma_distinct_addrs_distinct_mm ();
    Seq.lemma_equal_instances_implies_equal_types ();
    modifies_1_modifies b h h'
  end
#pop-options

let upd' #_ #_ #_ b i v =
  let open HST in
  let Buffer max_length content idx len () = b in
  let s0 = !content in
  let sb0 = Seq.slice s0 (U64.v idx) (U64.v idx + U64.v len) in
  content := Seq.replace_subseq s0 (U64.v idx) (U64.v idx + U64.v len) (Seq.upd sb0 (U64.v i) v)

let recallable (#a:Type0) (#rrel #rel:srel a) (b:mbuffer a rrel rel) :GTot Type0 =
  (not (g_is_null b)) ==> (
    HST.is_eternal_region (frameOf b) /\
    not (HS.is_mm (Buffer?.content b)))

let recallable_null #_ #_ #_ = ()

let recallable_includes #_ #_ #_ #_ #_ #_ larger smaller =
  if Null? larger || Null? smaller then ()
  else
    MG.loc_includes_aloc_elim #_ #LMB.cls #(frameOf larger) #(frameOf smaller) #(as_addr larger) #(as_addr smaller) (ubuffer_of_buffer larger) (ubuffer_of_buffer smaller)

let recall #_ #_ #_ b = if Null? b then () else HST.recall (Buffer?.content b)

private let spred_as_mempred (#a:Type0) (#rrel #rel:srel a) (b:mbuffer a rrel rel) (p:spred a)
  :HST.mem_predicate
  = fun h -> p (as_seq h b)

let witnessed #_ #_ #_ b p =
  match b with
  | Null -> p Seq.empty
  | Buffer _ content _ _ () -> HST.token_p content (spred_as_mempred b p)

private let lemma_stable_on_rel_is_stable_on_rrel (#a:Type0) (#rrel #rel:srel a)
  (b:mbuffer a rrel rel) (p:spred a)
  :Lemma (requires (Buffer? b /\ stable_on p rel))
         (ensures  (HST.stable_on (spred_as_mempred b p) (Buffer?.content b)))
  = let Buffer _ content _ _ () = b in
    let mp = spred_as_mempred b p in
    let aux (h0 h1:HS.mem) :Lemma ((mp h0 /\ rrel (HS.sel h0 content) (HS.sel h1 content)) ==> mp h1)
      = Classical.arrow_to_impl #(mp h0 /\ rrel (HS.sel h0 content) (HS.sel h1 content)) #(mp h1)
          (fun _ -> assert (rel (as_seq h0 b) (as_seq h1 b)))
    in
    Classical.forall_intro_2 aux

let witness_p #a #rrel #rel b p =
  match b with
  | Null -> ()
  | Buffer _ content _ _ () ->
    lemma_stable_on_rel_is_stable_on_rrel b p;
    //AR: TODO: the proof doesn't go through without this assertion, which should follow directly from the lemma call
    assert (HST.stable_on #(Seq.lseq a (U64.v (Buffer?.max_length b))) #(srel_to_lsrel (U64.v (Buffer?.max_length b)) rrel) (spred_as_mempred b p) (Buffer?.content b));
    HST.witness_p content (spred_as_mempred b p)

let recall_p #_ #_ #_ b p =
  match b with
  | Null -> ()
  | Buffer _ content _ _ () -> HST.recall_p content (spred_as_mempred b p)

let freeable (#a:Type0) (#rrel #rel:srel a) (b:mbuffer a rrel rel) =
  (not (g_is_null b)) /\
  HS.is_mm (Buffer?.content b) /\
  HST.is_eternal_region (frameOf b) /\
  U64.v (Buffer?.max_length b) > 0 /\
  Buffer?.idx b == 0UL /\
  Buffer?.length b == Buffer?.max_length b

let free #_ #_ #_ b = HST.rfree (Buffer?.content b)

let freeable_length #_ #_ #_ b = ()

let freeable_disjoint #_ #_ #_ #_ #_ #_ b1 b2 =
  if frameOf b1 = frameOf b2 && as_addr b1 = as_addr b2 then
    MG.loc_disjoint_aloc_elim #_ #LMB.cls #(frameOf b1) #(as_addr b1) #(frameOf b2) #(as_addr b2) (ubuffer_of_buffer b1) (ubuffer_of_buffer b2)

private let alloc_heap_common (#a:Type0) (#rrel:srel a)
  (r:HST.erid) (init:a) (len:U64.t{U64.v len > 0}) (mm:bool)
  :HST.ST (lmbuffer a rrel rrel (U64.v len))
          (requires (fun _      -> True))
          (ensures (fun h0 b h1 -> alloc_post_mem_common b h0 h1 (Seq.create (U64.v len) init) /\
	                        frameOf b == r /\
                                HS.is_mm (Buffer?.content b) == mm /\
                                Buffer?.idx b == 0UL /\
                                Buffer?.length b == Buffer?.max_length b))
  = let s = Seq.create (U64.v len) init in
    lemma_seq_sub_compatilibity_is_reflexive (U64.v len) rrel;
    let content: HST.mreference (Seq.lseq a (U64.v len)) (srel_to_lsrel (U64.v len) rrel) =
      if mm then HST.ralloc_mm r s else HST.ralloc r s
    in
    let b = Buffer len content 0UL len () in
    b

let mgcmalloc #_ #_ r init len = alloc_heap_common r init len false

let mmalloc #_ #_ r init len = alloc_heap_common r init len true

let malloca #a #rrel init len =
  lemma_seq_sub_compatilibity_is_reflexive (U64.v len) rrel;
  let content: HST.mreference (Seq.lseq a (U64.v len)) (srel_to_lsrel (U64.v len) rrel) =
    HST.salloc (Seq.create (U64.v len) init)
  in
  let b = Buffer len content 0UL len () in
  b

let malloca_of_list #a #rrel init =
  let len = U64.uint_to_t (FStar.List.Tot.length init) in
  let s = Seq.seq_of_list init in
  lemma_seq_sub_compatilibity_is_reflexive (U64.v len) rrel;
  let content: HST.mreference (Seq.lseq a (U64.v len)) (srel_to_lsrel (U64.v len) rrel) =
    HST.salloc s
  in
  let b = Buffer len content 0UL len () in
  b

let mgcmalloc_of_list #a #rrel r init =
  let len = U64.uint_to_t (FStar.List.Tot.length init) in
  let s = Seq.seq_of_list init in
  lemma_seq_sub_compatilibity_is_reflexive (U64.v len) rrel;
  let content: HST.mreference (Seq.lseq a (U64.v len)) (srel_to_lsrel (U64.v len) rrel) =
    HST.ralloc r s
  in
  let b = Buffer len content 0UL len () in
  b

#push-options "--z3rlimit 10 --max_fuel 1 --max_ifuel 1 --initial_fuel 1 --initial_ifuel 1"
let blit #a #rrel1 #rrel2 #rel1 #rel2 src idx_src dst idx_dst len =
  let open HST in
  if len = 0UL then ()
  else
    let h = get () in
    let Buffer _ content1 idx1 length1 () = src in
    let Buffer _ content2 idx2 length2 () = dst in
    let s_full1 = !content1 in
    let s_full2 = !content2 in
    let s1 = Seq.slice s_full1 (U64.v idx1) (U64.v idx1 + U64.v length1) in
    let s2 = Seq.slice s_full2 (U64.v idx2) (U64.v idx2 + U64.v length2) in
    let s_sub_src = Seq.slice s1 (U64.v idx_src) (U64.v idx_src + U64.v len) in
    let s2' = Seq.replace_subseq s2 (U64.v idx_dst) (U64.v idx_dst + U64.v len) s_sub_src in
    let s_full2' = Seq.replace_subseq s_full2 (U64.v idx2) (U64.v idx2 + U64.v length2) s2' in
    assert (Seq.equal (Seq.slice s2' (U64.v idx_dst) (U64.v idx_dst + U64.v len)) s_sub_src);
    assert (Seq.equal (Seq.slice s2' 0 (U64.v idx_dst)) (Seq.slice s2 0 (U64.v idx_dst)));
    assert (Seq.equal (Seq.slice s2' (U64.v idx_dst + U64.v len) (length dst))
                      (Seq.slice s2 (U64.v idx_dst + U64.v len) (length dst)));
    content2 := s_full2';
    g_upd_seq_as_seq dst s2' h  //for modifies clause
#pop-options

#push-options "--z3rlimit 64 --max_fuel 0 --max_ifuel 1 --initial_ifuel 1"
let fill' (#t:Type) (#rrel #rel: srel t)
  (b: mbuffer t rrel rel)
  (z:t)
  (len:U64.t)
: HST.Stack unit
  (requires (fun h ->
    live h b /\
    U64.v len <= length b /\
    rel (as_seq h b) (Seq.replace_subseq (as_seq h b) 0 (U64.v len) (Seq.create (U64.v len) z))
  ))
  (ensures  (fun h0 _ h1 ->
    LMB.modifies (loc_buffer b) h0 h1 /\
    live h1 b /\
    Seq.slice (as_seq h1 b) 0 (U64.v len) `Seq.equal` Seq.create (U64.v len) z /\
    Seq.slice (as_seq h1 b) (U64.v len) (length b) `Seq.equal` Seq.slice (as_seq h0 b) (U64.v len) (length b)
  ))
= let open HST in
  if len = 0UL then ()
  else begin
    let h = get () in
    let Buffer max_length content idx length () = b in
    let s_full = !content in
    let s = Seq.slice s_full (U64.v idx) (U64.v idx + U64.v length) in
    let s_src = Seq.create (U64.v len) z in
    let s' = Seq.replace_subseq s 0 (U64.v len) s_src in
    let s_full' = Seq.replace_subseq s_full (U64.v idx) (U64.v idx + U64.v len) s_src in
    assert (s_full' `Seq.equal` Seq.replace_subseq s_full (U64.v idx) (U64.v idx + U64.v length) s');
    content := s_full';
    let h' = HST.get () in
    assert (h' == g_upd_seq b s' h);
    g_upd_seq_as_seq b s' h  //for modifies clause
  end
#pop-options

let fill #t #rrel #rel b z len = fill' b z len