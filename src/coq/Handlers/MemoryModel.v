From Vellvm.Syntax Require Import
     DataLayout
     DynamicTypes.

From Vellvm.Semantics Require Import
     MemoryAddress
     MemoryParams
     Memory.Overlaps
     LLVMParams
     LLVMEvents.

Require Import MemBytes.

From Vellvm.Handlers Require Import
     MemPropT.

From Vellvm.Utils Require Import
     Error
     PropT
     Util
     NMaps
     Tactics
     Raise
     MonadReturnsLaws
     MonadEq1Laws
     MonadExcLaws.

From Vellvm.Numeric Require Import
     Integers.

From ExtLib Require Import
     Structures.Monads
     Structures.Functor.

From ITree Require Import
     ITree
     Basics.Basics
     Events.Exception
     Eq.Eq
     Events.StateFacts
     Events.State.

From Coq Require Import
     ZArith
     Strings.String
     List
     Lia
     Relations
     RelationClasses
     Wellfounded.

Import ListNotations.
Import ListUtil.
Import Utils.Monads.

Import Basics.Basics.Monads.
Import MonadNotation.
Open Scope monad_scope.


Module Type MemoryModelSpecPrimitives (LP : LLVMParams) (MP : MemoryParams LP).
  Import LP.Events.
  Import LP.ADDR.
  Import LP.SIZEOF.
  Import LP.PROV.

  Import MemBytes.
  Module MemByte := Byte LP.ADDR LP.IP LP.SIZEOF LP.Events MP.BYTE_IMPL.
  Import MemByte.
  Import LP.SIZEOF.

  (*** Internal state of memory *)
  Parameter MemState : Type.
  Parameter memory_stack : Type.
  Parameter MemState_get_memory : MemState -> memory_stack.
  Parameter MemState_get_provenance : MemState -> Provenance.
  Parameter MemState_put_memory : memory_stack -> MemState -> MemState.

  (* Type for frames and frame stacks *)
  Parameter Frame : Type.
  Parameter FrameStack : Type.

  (* TODO: Should DataLayout be here?

     It might make sense to move DataLayout to another module, some of
     the parameters in the DataLayout may be relevant to other
     modules, and we could enforce that everything agrees.

     For instance alignment may impact Sizeof, and there's also some
     stuff about pointer sizes in the DataLayout structure.
   *)
  (* Parameter datalayout : DataLayout. *)

  (*** Primitives on memory *)

  (** Reads *)
  Parameter read_byte_MemPropT : addr -> MemPropT memory_stack SByte.

  (** Allocations *)
  (* Returns true if a byte is allocated with a given AllocationId? *)
  Parameter addr_allocated_prop : addr -> AllocationId -> MemPropT memory_stack bool.

  (** Frame stacks *)
  (* Check if an address is allocated in a frame *)
  Parameter ptr_in_frame_prop : Frame -> addr -> Prop.

  (* Check for the current frame *)
  Parameter peek_frame_stack_prop : FrameStack -> Frame -> Prop.
  Parameter pop_frame_stack_prop : FrameStack -> FrameStack -> Prop.

  Parameter memory_stack_frame_stack_prop : memory_stack -> FrameStack -> Prop.

  Definition frame_eqv (f f' : Frame) : Prop :=
    forall ptr, ptr_in_frame_prop f ptr <-> ptr_in_frame_prop f' ptr.

  #[global] Instance frame_eqv_Equivalence : Equivalence frame_eqv.
  Proof.
    split.
    - intros f ptr.
      reflexivity.
    - intros f1 f2 EQV.
      unfold frame_eqv in *.
      firstorder.
    - intros x y z XY YZ.
      firstorder.
  Qed.

  Parameter frame_stack_eqv : FrameStack -> FrameStack -> Prop.
  #[global] Parameter frame_stack_eqv_Equivalence : Equivalence frame_stack_eqv.

  (** Provenances *)
  Parameter used_provenance_prop : MemState -> Provenance -> Prop. (* Has a provenance *ever* been used. *)

  (* Allocate a new fresh provenance *)
  Parameter mem_state_fresh_provenance : MemState -> (Provenance * MemState)%type.
  Parameter mem_state_fresh_provenance_fresh :
    forall (ms ms' : MemState) (pr : Provenance),
      mem_state_fresh_provenance ms = (pr, ms') ->
      MemState_get_memory ms = MemState_get_memory ms' /\
        (forall pr, used_provenance_prop ms pr -> used_provenance_prop ms' pr) /\
      ~ used_provenance_prop ms pr /\ used_provenance_prop ms' pr.

  (** Lemmas about MemState *)
  Parameter MemState_get_put_memory :
    forall ms mem,
      MemState_get_memory (MemState_put_memory mem ms) = mem.

  #[global] Instance MemState_memory_MemStateMem : MemStateMem MemState memory_stack :=
    {| ms_get_memory := MemState_get_memory;
      ms_put_memory := MemState_put_memory;
      ms_get_put_memory := MemState_get_put_memory;
    |}.

End MemoryModelSpecPrimitives.

Module MemoryHelpers (LP : LLVMParams) (MP : MemoryParams LP) (Byte : ByteModule LP.ADDR LP.IP LP.SIZEOF LP.Events MP.BYTE_IMPL).
  (*** Other helpers *)
  Import MP.GEP.
  Import MP.BYTE_IMPL.
  Import LP.
  Import LP.ADDR.
  Import LP.Events.
  Import LP.SIZEOF.
  Import Byte.

  (* TODO: Move this? *)
  Definition intptr_seq (start : Z) (len : nat) : OOM (list IP.intptr)
    := Util.map_monad (IP.from_Z) (Zseq start len).

  (* TODO: Move this? *)
  Lemma intptr_seq_succ :
    forall off n,
      intptr_seq off (S n) =
        hd <- IP.from_Z off;;
        tail <- intptr_seq (Z.succ off) n;;
        ret (hd :: tail).
  Proof.
    intros off n.
    cbn.
    reflexivity.
  Qed.

  Lemma intptr_seq_nth :
    forall start len seq ix ixip,
      intptr_seq start len = NoOom seq ->
      Util.Nth seq ix ixip ->
      IP.from_Z (start + (Z.of_nat ix)) = NoOom ixip.
  Proof.
    intros start len seq. revert start len.
    induction seq; intros start len ix ixip SEQ NTH.
    - cbn in NTH.
      destruct ix; inv NTH.
    - cbn in *.
      destruct ix.
      + cbn in *; inv NTH.
        destruct len; cbn in SEQ; inv SEQ.
        break_match_hyp; inv H0.
        replace (start + 0)%Z with start by lia.
        break_match_hyp; cbn in *; inv H1; auto.
      + cbn in *; inv NTH.
        destruct len as [ | len']; cbn in SEQ; inv SEQ.
        break_match_hyp; inv H1.
        break_match_hyp; cbn in *; inv H2; auto.

        replace (start + Z.pos (Pos.of_succ_nat ix))%Z with
          (Z.succ start + Z.of_nat ix)%Z by lia.

        eapply IHseq with (start := Z.succ start) (len := len'); eauto.
  Qed.

  Lemma intptr_seq_ge :
    forall start len seq x,
      intptr_seq start len = NoOom seq ->
      In x seq ->
      (IP.to_Z x >= start)%Z.
  Proof.
    intros start len seq x SEQ IN.
    apply In_nth_error in IN.
    destruct IN as [n IN].

    pose proof (intptr_seq_nth start len seq n x SEQ IN) as IX.
    erewrite IP.from_Z_to_Z; eauto.
    lia.
  Qed.

  Lemma in_intptr_seq :
    forall len start n seq,
      intptr_seq start len = NoOom seq ->
      In n seq <-> (start <= IP.to_Z n < start + Z.of_nat len)%Z.
  Proof.
  intros len start.
  revert start. induction len as [|len IHlen]; simpl; intros start n seq SEQ.
  - cbn in SEQ; inv SEQ.
    split.
    + intros IN; inv IN.
    + lia.
  - cbn in SEQ.
    break_match_hyp; [|inv SEQ].
    break_match_hyp; inv SEQ.
    split.
    + intros [IN | IN].
      * subst.
        apply IP.from_Z_to_Z in Heqo; subst.
        lia.
      * pose proof (IHlen (Z.succ start) n l Heqo0) as [A B].
        specialize (A IN).
        cbn.
        lia.
    + intros BOUND.
      cbn.
      destruct (IP.eq_dec i n) as [EQ | NEQ]; auto.
      right.

      pose proof (IHlen (Z.succ start) n l Heqo0) as [A B].
      apply IP.from_Z_to_Z in Heqo; subst.
      assert (IP.to_Z i <> IP.to_Z n).
      { intros EQ.
        apply IP.to_Z_inj in EQ; auto.
      }

      assert ((Z.succ (IP.to_Z i) <= IP.to_Z n < Z.succ (IP.to_Z i) + Z.of_nat len)%Z) as BOUND' by lia.
      specialize (B BOUND').
      auto.
  Qed.

  Lemma intptr_seq_from_Z :
    forall start len seq,
      intptr_seq start len = NoOom seq ->
      (forall x,
          (start <= x < start + Z.of_nat len)%Z ->
          exists ipx, IP.from_Z x = NoOom ipx).
  Proof.
    intros start len; revert start;
      induction len;
      intros start seq SEQ x BOUND.

    - lia.
    - rewrite intptr_seq_succ in SEQ.
      cbn in SEQ.
      break_match_hyp.
      + destruct (Z.eq_dec x start); subst.
        exists i; auto.

        break_match_hyp; inv SEQ.
        eapply IHlen with (x := x) in Heqo0; auto.
        lia.
      + inv SEQ.
  Qed.

  Lemma intptr_seq_len :
    forall len start seq,
      intptr_seq start len = NoOom seq ->
      length seq = len.
  Proof.
    induction len;
      intros start seq SEQ.
    - inv SEQ. reflexivity.
    - rewrite intptr_seq_succ in SEQ.
      cbn in SEQ.
      break_match_hyp; [break_match_hyp|]; inv SEQ.
      cbn.
      apply IHlen in Heqo0; subst.
      reflexivity.
  Qed.

  Definition get_consecutive_ptrs {M} `{Monad M} `{RAISE_OOM M} `{RAISE_ERROR M} (ptr : addr) (len : nat) : M (list addr) :=
    ixs <- lift_OOM (intptr_seq 0 len);;
    lift_err_RAISE_ERROR
      (Util.map_monad
         (fun ix => handle_gep_addr (DTYPE_I 8) ptr [DVALUE_IPTR ix])
         ixs).

  Definition generate_undef_bytes (dt : dtyp) (sid : store_id) : OOM (list SByte) :=
    N.recursion
      (fun (x : N) => ret [])
      (fun n mf x =>
         rest_bytes <- mf (N.succ x);;
         x' <- IP.from_Z (Z.of_N x);;
         let byte := uvalue_sbyte (UVALUE_Undef dt) dt (UVALUE_IPTR x') sid in
         ret (byte :: rest_bytes))
      (sizeof_dtyp dt) 0%N.

  Section Serialization.
    (** ** Serialization *)
  (*      Conversion back and forth between values and their byte representation *)
  (*    *)
    (* Given a little endian list of bytes, match the endianess of `e` *)
    Definition correct_endianess {BYTES : Type} (e : Endianess) (bytes : list BYTES)
      := match e with
         | ENDIAN_BIG => rev bytes
         | ENDIAN_LITTLE => bytes
         end.

    (* Converts an integer [x] to its byte representation over [n] bytes. *)
  (*    The representation is little endian. In particular, if [n] is too small, *)
  (*    only the least significant bytes are returned. *)
  (*    *)
    Fixpoint bytes_of_int_little_endian (n: nat) (x: Z) {struct n}: list byte :=
      match n with
      | O => nil
      | S m => Byte.repr x :: bytes_of_int_little_endian m (x / 256)
      end.

    Definition bytes_of_int (e : Endianess) (n : nat) (x : Z) : list byte :=
      correct_endianess e (bytes_of_int_little_endian n x).

    (* *)
  (* Definition sbytes_of_int (e : Endianess) (count:nat) (z:Z) : list SByte := *)
  (*   List.map Byte (bytes_of_int e count z). *)

    Definition uvalue_bytes_little_endian (uv :  uvalue) (dt : dtyp) (sid : store_id) : OOM (list uvalue)
      := map_monad (fun n => n' <- IP.from_Z (Z.of_N n);;
                          ret (UVALUE_ExtractByte uv dt (UVALUE_IPTR n') sid)) (Nseq 0 (N.to_nat (sizeof_dtyp DTYPE_Pointer))).

    Definition uvalue_bytes (e : Endianess) (uv :  uvalue) (dt : dtyp) (sid : store_id) : OOM (list uvalue)
      := fmap (correct_endianess e) (uvalue_bytes_little_endian uv dt sid).

    (* TODO: move this *)
    Definition dtyp_eqb (dt1 dt2 : dtyp) : bool
      := match @dtyp_eq_dec dt1 dt2 with
         | left x => true
         | right x => false
         end.

    (* TODO: revive this *)
    (* Definition fp_alignment (bits : N) : option Alignment := *)
    (*   let fp_map := dl_floating_point_alignments datalayout *)
    (*   in NM.find bits fp_map. *)

    (*  TODO: revive this *)
    (* Definition int_alignment (bits : N) : option Alignment := *)
    (*   let int_map := dl_integer_alignments datalayout *)
    (*   in match NM.find bits int_map with *)
    (*      | Some align => Some align *)
    (*      | None => *)
    (*        let keys  := map fst (NM.elements int_map) in *)
    (*        let bits' := nextOrMaximumOpt N.leb bits keys  *)
    (*        in match bits' with *)
    (*           | Some bits => NM.find bits int_map *)
    (*           | None => None *)
    (*           end *)
    (*      end. *)

    (* TODO: Finish this function *)
    (* Fixpoint dtyp_alignment (dt : dtyp) : option Alignment := *)
    (*   match dt with *)
    (*   | DTYPE_I sz => *)
    (*     int_alignment sz *)
    (*   | DTYPE_IPTR => *)
    (*     (* TODO: should these have the same alignments as pointers? *) *)
    (*     int_alignment (N.of_nat ptr_size * 4)%N *)
    (*   | DTYPE_Pointer => *)
    (*     (* TODO: address spaces? *) *)
    (*     Some (ps_alignment (head (dl_pointer_alignments datalayout))) *)
    (*   | DTYPE_Void => *)
    (*     None *)
    (*   | DTYPE_Half => *)
    (*     fp_alignment 16 *)
    (*   | DTYPE_Float => *)
    (*     fp_alignment 32 *)
    (*   | DTYPE_Double => *)
    (*     fp_alignment 64 *)
    (*   | DTYPE_X86_fp80 => *)
    (*     fp_alignment 80 *)
    (*   | DTYPE_Fp128 => *)
    (*     fp_alignment 128 *)
    (*   | DTYPE_Ppc_fp128 => *)
    (*     fp_alignment 128 *)
    (*   | DTYPE_Metadata => *)
    (*     None *)
    (*   | DTYPE_X86_mmx => _ *)
    (*   | DTYPE_Array sz t => *)
    (*     dtyp_alignment t *)
    (*   | DTYPE_Struct fields => _ *)
    (*   | DTYPE_Packed_struct fields => _ *)
    (*   | DTYPE_Opaque => _ *)
    (*   | DTYPE_Vector sz t => _ *)
    (*   end. *)

    Definition dtyp_extract_fields (dt : dtyp) : err (list dtyp)
      := match dt with
         | DTYPE_Struct fields
         | DTYPE_Packed_struct fields =>
             ret fields
         | DTYPE_Array sz t
         | DTYPE_Vector sz t =>
             ret (repeat t (N.to_nat sz))
         | _ => inl "No fields."%string
         end.

    Definition extract_byte_to_sbyte (uv : uvalue) : ERR SByte
      := match uv with
         | UVALUE_ExtractByte uv dt idx sid =>
             ret (uvalue_sbyte uv dt idx sid)
         | _ => inl (ERR_message "extract_byte_to_ubyte invalid conversion.")
         end.

    Definition sbyte_sid_match (a b : SByte) : bool
      := match sbyte_to_extractbyte a, sbyte_to_extractbyte b with
         | UVALUE_ExtractByte uv dt idx sid, UVALUE_ExtractByte uv' dt' idx' sid' =>
             N.eqb sid sid'
         | _, _ => false
         end.

    Definition replace_sid (sid : store_id) (ub : SByte) : SByte
      := match sbyte_to_extractbyte ub with
         | UVALUE_ExtractByte uv dt idx sid_old =>
             uvalue_sbyte uv dt idx sid
         | _ =>
             ub (* Should not happen... *)
         end.

    Definition filter_sid_matches (byte : SByte) (sbytes : list (N * SByte)) : (list (N * SByte) * list (N * SByte))
      := filter_split (fun '(n, uv) => sbyte_sid_match byte uv) sbytes.

    (* TODO: should I move this? *)
    (* Assign fresh sids to ubytes while preserving entanglement *)
    Program Fixpoint re_sid_ubytes_helper {M} `{Monad M} `{MonadStoreId M} `{RAISE_ERROR M}
            (bytes : list (N * SByte)) (acc : NMap SByte) {measure (length bytes)} : M (NMap SByte)
      := match bytes with
         | [] => ret acc
         | ((n, x)::xs) =>
             match sbyte_to_extractbyte x with
             | UVALUE_ExtractByte uv dt idx sid =>
                 let '(ins, outs) := filter_sid_matches x xs in
                 nsid <- fresh_sid;;
                 let acc := @NM.add _ n (replace_sid nsid x) acc in
                 (* Assign new sid to entangled bytes *)
                 let acc := fold_left (fun acc '(n, ub) => @NM.add _ n (replace_sid nsid ub) acc) ins acc in
                 re_sid_ubytes_helper outs acc
             | _ => raise_error "re_sid_ubytes_helper: sbyte_to_extractbyte did not yield UVALUE_ExtractByte"
             end
         end.
    Next Obligation.
      cbn.
      symmetry in Heq_anonymous.
      apply filter_split_out_length in Heq_anonymous.
      lia.
    Defined.

    Definition re_sid_ubytes {M} `{Monad M} `{MonadStoreId M} `{RAISE_ERROR M}
               (bytes : list SByte) : M (list SByte)
      := let len := length bytes in
         byte_map <- re_sid_ubytes_helper (zip (Nseq 0 len) bytes) (@NM.empty _);;
         trywith_error "re_sid_ubytes: missing indices." (NM_find_many (Nseq 0 len) byte_map).

    Definition sigT_of_prod {A B : Type} (p : A * B) : {_ : A & B} :=
      let (a, b) := p in existT (fun _ : A => B) a b.

    Definition uvalue_measure_rel (uv1 uv2 : uvalue) : Prop :=
      (uvalue_measure uv1 < uvalue_measure uv2)%nat.

    Lemma wf_uvalue_measure_rel :
      @well_founded uvalue uvalue_measure_rel.
    Proof.
      unfold uvalue_measure_rel.
      apply wf_inverse_image.
      apply Wf_nat.lt_wf.
    Defined.

    Definition lt_uvalue_dtyp (uvdt1 uvdt2 : (uvalue * dtyp)) : Prop :=
      lexprod uvalue (fun uv => dtyp) uvalue_measure_rel (fun uv dt1f dt2f => dtyp_measure dt1f < dtyp_measure dt2f)%nat (sigT_of_prod uvdt1) (sigT_of_prod uvdt2).

    Lemma wf_lt_uvalue_dtyp : well_founded lt_uvalue_dtyp.
    Proof.
      unfold lt_uvalue_dtyp.
      apply wf_inverse_image.
      apply wf_lexprod.
      - unfold well_founded; intros a.
        apply wf_uvalue_measure_rel.
      - intros uv.
        apply wf_inverse_image.
        apply Wf_nat.lt_wf.
    Defined.

    Definition lex_nats (ns1 ns2 : (nat * nat)) : Prop :=
      lexprod nat (fun n => nat) lt (fun _ => lt) (sigT_of_prod ns1) (sigT_of_prod ns2).

    Lemma well_founded_lex_nats :
      well_founded lex_nats.
    Proof.
      unfold lex_nats.
      apply wf_inverse_image.
      apply wf_lexprod; intros;
        apply Wf_nat.lt_wf.
    Qed.

    (* This is mostly to_ubytes, except it will also unwrap concatbytes *)
    Obligation Tactic := try Tactics.program_simpl; try solve [solve_uvalue_dtyp_measure
                                                              | intuition;
                                                               match goal with
                                                               | H: _ |- _ =>
                                                                   try solve [inversion H]
                                                               end
                                                    ].

    Program Fixpoint serialize_sbytes
            {M} `{Monad M} `{MonadStoreId M} `{RAISE_ERROR M} `{RAISE_OOM M}
            (uv : uvalue) (dt : dtyp) {measure (uvalue_measure uv, dtyp_measure dt) lex_nats} : M (list SByte)
      :=
      match uv with
      (* Base types *)
      | UVALUE_Addr _
      | UVALUE_I1 _
      | UVALUE_I8 _
      | UVALUE_I32 _
      | UVALUE_I64 _
      | UVALUE_IPTR _
      | UVALUE_Float _
      | UVALUE_Double _

      (* Expressions *)
      | UVALUE_IBinop _ _ _
      | UVALUE_ICmp _ _ _
      | UVALUE_FBinop _ _ _ _
      | UVALUE_FCmp _ _ _
      | UVALUE_Conversion _ _ _ _
      | UVALUE_GetElementPtr _ _ _
      | UVALUE_ExtractElement _ _
      | UVALUE_InsertElement _ _ _
      | UVALUE_ShuffleVector _ _ _
      | UVALUE_ExtractValue _ _
      | UVALUE_InsertValue _ _ _
      | UVALUE_Select _ _ _ =>
          sid <- fresh_sid;;
          lift_OOM (to_ubytes uv dt sid)

      (* Undef values, these can possibly be aggregates *)
      | UVALUE_Undef _ =>
          match dt with
          | DTYPE_Struct [] =>
              ret []
          | DTYPE_Struct (t::ts) =>
              f_bytes <- serialize_sbytes (UVALUE_Undef t) t;; (* How do I know this is smaller? *)
              fields_bytes <- serialize_sbytes (UVALUE_Undef (DTYPE_Struct ts)) (DTYPE_Struct ts);;
              ret (f_bytes ++ fields_bytes)

          | DTYPE_Packed_struct [] =>
              ret []
          | DTYPE_Packed_struct (t::ts) =>
              f_bytes <- serialize_sbytes (UVALUE_Undef t) t;; (* How do I know this is smaller? *)
              fields_bytes <- serialize_sbytes (UVALUE_Undef (DTYPE_Packed_struct ts)) (DTYPE_Packed_struct ts);;
              ret (f_bytes ++ fields_bytes)

          | DTYPE_Array sz t =>
              field_bytes <- map_monad_In (repeatN sz (UVALUE_Undef t)) (fun elt Hin => serialize_sbytes elt t);;
              ret (concat field_bytes)

          | DTYPE_Vector sz t =>
              field_bytes <- map_monad_In (repeatN sz (UVALUE_Undef t)) (fun elt Hin => serialize_sbytes elt t);;
              ret (concat field_bytes)
          | _ =>
              sid <- fresh_sid;;
              lift_OOM (to_ubytes uv dt sid)
          end

      (* Poison values, possibly aggregates *)
      | UVALUE_Poison _ =>
          match dt with
          | DTYPE_Struct [] =>
              ret []
          | DTYPE_Struct (t::ts) =>
              f_bytes <- serialize_sbytes (UVALUE_Poison t) t;; (* How do I know this is smaller? *)
              fields_bytes <- serialize_sbytes (UVALUE_Poison (DTYPE_Struct ts)) (DTYPE_Struct ts);;
              ret (f_bytes ++ fields_bytes)

          | DTYPE_Packed_struct [] =>
              ret []
          | DTYPE_Packed_struct (t::ts) =>
              f_bytes <- serialize_sbytes (UVALUE_Poison t) t;; (* How do I know this is smaller? *)
              fields_bytes <- serialize_sbytes (UVALUE_Poison (DTYPE_Packed_struct ts)) (DTYPE_Packed_struct ts);;
              ret (f_bytes ++ fields_bytes)

          | DTYPE_Array sz t =>
              field_bytes <- map_monad_In (repeatN sz (UVALUE_Poison t)) (fun elt Hin => serialize_sbytes elt t);;
              ret (concat field_bytes)

          | DTYPE_Vector sz t =>
              field_bytes <- map_monad_In (repeatN sz (UVALUE_Poison t)) (fun elt Hin => serialize_sbytes elt t);;
              ret (concat field_bytes)
          | _ =>
              sid <- fresh_sid;;
              lift_OOM (to_ubytes uv dt sid)
          end

      (* TODO: each field gets a separate store id... Is that sensible? *)
      (* Padded aggregate types *)
      | UVALUE_Struct [] =>
          ret []
      | UVALUE_Struct (f::fields) =>
          (* TODO: take padding into account *)
          match dt with
          | DTYPE_Struct (t::ts) =>
              f_bytes <- serialize_sbytes f t;;
              fields_bytes <- serialize_sbytes (UVALUE_Struct fields) (DTYPE_Struct ts);;
              ret (f_bytes ++ fields_bytes)
          | _ =>
              raise_error "serialize_sbytes: UVALUE_Struct field / type mismatch."
          end

      (* Packed aggregate types *)
      | UVALUE_Packed_struct [] =>
          ret []
      | UVALUE_Packed_struct (f::fields) =>
          (* TODO: take padding into account *)
          match dt with
          | DTYPE_Packed_struct (t::ts) =>
              f_bytes <- serialize_sbytes f t;;
              fields_bytes <- serialize_sbytes (UVALUE_Packed_struct fields) (DTYPE_Packed_struct ts);;
              ret (f_bytes ++ fields_bytes)
          | _ =>
              raise_error "serialize_sbytes: UVALUE_Packed_struct field / type mismatch."
          end

      | UVALUE_Array elts =>
          match dt with
          | DTYPE_Array sz t =>
              field_bytes <- map_monad_In elts (fun elt Hin => serialize_sbytes elt t);;
              ret (concat field_bytes)
          | _ =>
              raise_error "serialize_sbytes: UVALUE_Array with incorrect type."
          end
      | UVALUE_Vector elts =>
          match dt with
          | DTYPE_Vector sz t =>
              field_bytes <- map_monad_In elts (fun elt Hin => serialize_sbytes elt t);;
              ret (concat field_bytes)
          | _ =>
              raise_error "serialize_sbytes: UVALUE_Array with incorrect type."
          end

      | UVALUE_None => ret nil

      (* Byte manipulation. *)
      | UVALUE_ExtractByte uv dt' idx sid =>
          raise_error "serialize_sbytes: UVALUE_ExtractByte not guarded by UVALUE_ConcatBytes."

      | UVALUE_ConcatBytes bytes t =>
          (* TODO: should provide *new* sids... May need to make this function in a fresh sid monad *)
          bytes' <- lift_ERR_RAISE_ERROR (map_monad extract_byte_to_sbyte bytes);;
          re_sid_ubytes bytes'
      end.
    Next Obligation.
      unfold Wf.MR.
      unfold lex_nats.
      apply wf_inverse_image.
      apply wf_lexprod; intros;
        apply Wf_nat.lt_wf.
    Qed.

    Lemma serialize_sbytes_equation {M} `{Monad M} `{MonadStoreId M} `{RAISE_ERROR M} `{RAISE_OOM M} : forall (uv : uvalue) (dt : dtyp),
        @serialize_sbytes M _ _ _ _ uv dt =
          match uv with
          (* Base types *)
          | UVALUE_Addr _
          | UVALUE_I1 _
          | UVALUE_I8 _
          | UVALUE_I32 _
          | UVALUE_I64 _
          | UVALUE_IPTR _
          | UVALUE_Float _
          | UVALUE_Double _

          (* Expressions *)
          | UVALUE_IBinop _ _ _
          | UVALUE_ICmp _ _ _
          | UVALUE_FBinop _ _ _ _
          | UVALUE_FCmp _ _ _
          | UVALUE_Conversion _ _ _ _
          | UVALUE_GetElementPtr _ _ _
          | UVALUE_ExtractElement _ _
          | UVALUE_InsertElement _ _ _
          | UVALUE_ShuffleVector _ _ _
          | UVALUE_ExtractValue _ _
          | UVALUE_InsertValue _ _ _
          | UVALUE_Select _ _ _ =>
              sid <- fresh_sid;;
              lift_OOM (to_ubytes uv dt sid)

          (* Undef values, these can possibly be aggregates *)
          | UVALUE_Undef _ =>
              match dt with
              | DTYPE_Struct [] =>
                  ret []
              | DTYPE_Struct (t::ts) =>
                  f_bytes <- serialize_sbytes (UVALUE_Undef t) t;; (* How do I know this is smaller? *)
                  fields_bytes <- serialize_sbytes (UVALUE_Undef (DTYPE_Struct ts)) (DTYPE_Struct ts);;
                  ret (f_bytes ++ fields_bytes)

              | DTYPE_Packed_struct [] =>
                  ret []
              | DTYPE_Packed_struct (t::ts) =>
                  f_bytes <- serialize_sbytes (UVALUE_Undef t) t;; (* How do I know this is smaller? *)
                  fields_bytes <- serialize_sbytes (UVALUE_Undef (DTYPE_Packed_struct ts)) (DTYPE_Packed_struct ts);;
                  ret (f_bytes ++ fields_bytes)

              | DTYPE_Array sz t =>
                  field_bytes <- map_monad_In (repeatN sz (UVALUE_Undef t)) (fun elt Hin => serialize_sbytes elt t);;
                  ret (concat field_bytes)

              | DTYPE_Vector sz t =>
                  field_bytes <- map_monad_In (repeatN sz (UVALUE_Undef t)) (fun elt Hin => serialize_sbytes elt t);;
                  ret (concat field_bytes)
              | _ =>
                  sid <- fresh_sid;;
                  lift_OOM (to_ubytes uv dt sid)
              end

          (* Poison values, possibly aggregates *)
          | UVALUE_Poison _ =>
              match dt with
              | DTYPE_Struct [] =>
                  ret []
              | DTYPE_Struct (t::ts) =>
                  f_bytes <- serialize_sbytes (UVALUE_Poison t) t;; (* How do I know this is smaller? *)
                  fields_bytes <- serialize_sbytes (UVALUE_Poison (DTYPE_Struct ts)) (DTYPE_Struct ts);;
                  ret (f_bytes ++ fields_bytes)

              | DTYPE_Packed_struct [] =>
                  ret []
              | DTYPE_Packed_struct (t::ts) =>
                  f_bytes <- serialize_sbytes (UVALUE_Poison t) t;; (* How do I know this is smaller? *)
                  fields_bytes <- serialize_sbytes (UVALUE_Poison (DTYPE_Packed_struct ts)) (DTYPE_Packed_struct ts);;
                  ret (f_bytes ++ fields_bytes)

              | DTYPE_Array sz t =>
                  field_bytes <- map_monad_In (repeatN sz (UVALUE_Poison t)) (fun elt Hin => serialize_sbytes elt t);;
                  ret (concat field_bytes)

              | DTYPE_Vector sz t =>
                  field_bytes <- map_monad_In (repeatN sz (UVALUE_Poison t)) (fun elt Hin => serialize_sbytes elt t);;
                  ret (concat field_bytes)
              | _ =>
                  sid <- fresh_sid;;
                  lift_OOM (to_ubytes uv dt sid)
              end

          (* TODO: each field gets a separate store id... Is that sensible? *)
          (* Padded aggregate types *)
          | UVALUE_Struct [] =>
              ret []
          | UVALUE_Struct (f::fields) =>
              (* TODO: take padding into account *)
              match dt with
              | DTYPE_Struct (t::ts) =>
                  f_bytes <- serialize_sbytes f t;;
                  fields_bytes <- serialize_sbytes (UVALUE_Struct fields) (DTYPE_Struct ts);;
                  ret (f_bytes ++ fields_bytes)
              | _ =>
                  raise_error "serialize_sbytes: UVALUE_Struct field / type mismatch."
              end

          (* Packed aggregate types *)
          | UVALUE_Packed_struct [] =>
              ret []
          | UVALUE_Packed_struct (f::fields) =>
              (* TODO: take padding into account *)
              match dt with
              | DTYPE_Packed_struct (t::ts) =>
                  f_bytes <- serialize_sbytes f t;;
                  fields_bytes <- serialize_sbytes (UVALUE_Packed_struct fields) (DTYPE_Packed_struct ts);;
                  ret (f_bytes ++ fields_bytes)
              | _ =>
                  raise_error "serialize_sbytes: UVALUE_Packed_struct field / type mismatch."
              end

          | UVALUE_Array elts =>
              match dt with
              | DTYPE_Array sz t =>
                  field_bytes <- map_monad_In elts (fun elt Hin => serialize_sbytes elt t);;
                  ret (concat field_bytes)
              | _ =>
                  raise_error "serialize_sbytes: UVALUE_Array with incorrect type."
              end
          | UVALUE_Vector elts =>
              match dt with
              | DTYPE_Vector sz t =>
                  field_bytes <- map_monad_In elts (fun elt Hin => serialize_sbytes elt t);;
                  ret (concat field_bytes)
              | _ =>
                  raise_error "serialize_sbytes: UVALUE_Array with incorrect type."
              end

          | UVALUE_None => ret nil

          (* Byte manipulation. *)
          | UVALUE_ExtractByte uv dt' idx sid =>
              raise_error "serialize_sbytes: UVALUE_ExtractByte not guarded by UVALUE_ConcatBytes."

          | UVALUE_ConcatBytes bytes t =>
              (* TODO: should provide *new* sids... May need to make this function in a fresh sid monad *)
              bytes' <- lift_ERR_RAISE_ERROR (map_monad extract_byte_to_sbyte bytes);;
              re_sid_ubytes bytes'
          end.
    Proof.
      (* intros uv dt. *)
      (* unfold serialize_sbytes. *)
      (* unfold serialize_sbytes_func at 1. *)
      (* rewrite Wf.WfExtensionality.fix_sub_eq_ext. *)
      (* destruct uv. *)
      (* all: try reflexivity. *)
      (* all: cbn. *)
      (* - destruct dt; try reflexivity. *)
      (*   destruct (Datatypes.length fields0 =? Datatypes.length fields)%nat eqn:Hlen. *)
      (*   + cbn. *)
      (*     reflexivity. *)
      (*   + *)


      (* destruct uv; try reflexivity. simpl. *)
      (* destruct dt; try reflexivity. simpl. *)
      (* break_match. *)
      (*  destruct (find (fun a : ident * typ => Ident.eq_dec id (fst a)) env). *)
      (* destruct p; simpl; eauto. *)
      (* reflexivity. *)
    Admitted.

    (* deserialize_sbytes takes a list of SBytes and turns them into a uvalue. *)

  (*    This relies on the similar, but different, from_ubytes function *)
  (*    which given a set of bytes checks if all of the bytes are from *)
  (*    the same uvalue, and if so returns the original uvalue, and *)
  (*    otherwise returns a UVALUE_ConcatBytes value instead. *)

  (*    The reason we also have deserialize_sbytes is in order to deal *)
  (*    with aggregate data types. *)
  (*    *)
    Obligation Tactic := try Tactics.program_simpl; try solve [solve_dtyp_measure].
    Program Fixpoint deserialize_sbytes (bytes : list SByte) (dt : dtyp) {measure (dtyp_measure dt)} : err uvalue
      :=
      match dt with
      (* TODO: should we bother with this? *)
      (* Array and vector types *)
      | DTYPE_Array sz t =>
          let size := sizeof_dtyp t in
          let size_nat := N.to_nat size in
          fields <- monad_fold_right (fun acc idx => uv <- deserialize_sbytes (between (idx*size) ((idx+1) * size) bytes) t;; ret (uv::acc)) (Nseq 0 size_nat) [];;
          ret (UVALUE_Array fields)

      | DTYPE_Vector sz t =>
          let size := sizeof_dtyp t in
          let size_nat := N.to_nat size in
          fields <- monad_fold_right (fun acc idx => uv <- deserialize_sbytes (between (idx*size) ((idx+1) * size) bytes) t;; ret (uv::acc)) (Nseq 0 size_nat) [];;
          ret (UVALUE_Vector fields)

      (* Padded aggregate types *)
      | DTYPE_Struct fields =>
          (* TODO: Add padding *)
          match fields with
          | [] => ret (UVALUE_Struct []) (* TODO: Not 100% sure about this. *)
          | (dt::dts) =>
              let sz := sizeof_dtyp dt in
              let init_bytes := take sz bytes in
              let rest_bytes := drop sz bytes in
              f <- deserialize_sbytes init_bytes dt;;
              rest <- deserialize_sbytes rest_bytes (DTYPE_Struct dts);;
              match rest with
              | UVALUE_Struct fs =>
                  ret (UVALUE_Struct (f::fs))
              | _ =>
                  inl "deserialize_sbytes: DTYPE_Struct recursive call did not return a struct."%string
              end
          end

      (* Structures with no padding *)
      | DTYPE_Packed_struct fields =>
          match fields with
          | [] => ret (UVALUE_Packed_struct []) (* TODO: Not 100% sure about this. *)
          | (dt::dts) =>
              let sz := sizeof_dtyp dt in
              let init_bytes := take sz bytes in
              let rest_bytes := drop sz bytes in
              f <- deserialize_sbytes init_bytes dt;;
              rest <- deserialize_sbytes rest_bytes (DTYPE_Packed_struct dts);;
              match rest with
              | UVALUE_Packed_struct fs =>
                  ret (UVALUE_Packed_struct (f::fs))
              | _ =>
                  inl "deserialize_sbytes: DTYPE_Struct recursive call did not return a struct."%string
              end
          end

      (* Base types *)
      | DTYPE_I _
      | DTYPE_IPTR
      | DTYPE_Pointer
      | DTYPE_Half
      | DTYPE_Float
      | DTYPE_Double
      | DTYPE_X86_fp80
      | DTYPE_Fp128
      | DTYPE_Ppc_fp128
      | DTYPE_X86_mmx
      | DTYPE_Opaque
      | DTYPE_Metadata =>
          ret (from_ubytes bytes dt)

      | DTYPE_Void =>
          inl "deserialize_sbytes: Attempt to deserialize void."%string
      end.

  (* (* TODO: *) *)

  (*  (*   What is the difference between a pointer and an integer...? *) *)

  (*  (*   Primarily, it's that pointers have provenance and integers don't? *) *)

  (*  (*   So, if we do PVI is there really any difference between an address *) *)
  (*  (*   and an integer, and should we actually distinguish between them? *) *)

  (*  (*   Provenance in UVALUE_IPTR probably means we need provenance in *all* *) *)
  (*  (*   data types... i1, i8, i32, etc, and even doubles and floats... *) *)
  (*  (*  *) *)

  (* (* TODO: *) *)

  (*  (*    Should uvalue have something like... UVALUE_ExtractByte which *) *)
  (*  (*    extracts a certain byte out of a uvalue? *) *)

  (*  (*    Will probably need an equivalence relation on UVALUEs, likely won't *) *)
  (*  (*    end up with a round-trip property with regular equality... *) *)
  (*  (* *) *)

  End Serialization.
End MemoryHelpers.

Module Type MemoryModelSpec (LP : LLVMParams) (MP : MemoryParams LP) (MMSP : MemoryModelSpecPrimitives LP MP).
  Import LP.
  Import LP.Events.
  Import LP.ADDR.
  Import LP.SIZEOF.
  Import LP.PROV.
  Import LP.PTOI.
  Import MMSP.

  Module OVER := PTOIOverlaps ADDR PTOI SIZEOF.
  Import OVER.
  Module OVER_H := OverlapHelpers ADDR SIZEOF OVER.
  Import OVER_H.

  Import MemByte.

  Module MemHelpers := MemoryHelpers LP MP MemByte.
  Import MemHelpers.

  Definition read_byte_prop (ms : MemState) (ptr : addr) (byte : SByte) : Prop
    := read_byte_MemPropT ptr (MemState_get_memory ms) (ret ((MemState_get_memory ms), byte)).

  Definition lift_memory_MemPropT {X} (m : MemPropT memory_stack X) : MemPropT MemState X :=
    fun ms res =>
      m (MemState_get_memory ms) (fmap (fun '(ms, x) => (MemState_get_memory ms, x)) res) /\
        (* Provenance should be preserved as memory operation shouldn't touch rest of MemState *)
        forall ms' x, res = ret (ms', x) -> MemState_get_provenance ms = MemState_get_provenance ms'.

  Definition byte_allocated_MemPropT (ptr : addr) (aid : AllocationId) : MemPropT MemState unit :=
    b <- lift_memory_MemPropT (addr_allocated_prop ptr aid);;
    MemPropT_assert (b = true).

  Definition byte_allocated (ms : MemState) (ptr : addr) (aid : AllocationId) : Prop
    := byte_allocated_MemPropT ptr aid ms (ret (ms, tt)).

  Definition byte_not_allocated (ms : MemState) (ptr : addr) : Prop
    := forall (aid : AllocationId), ~ byte_allocated ms ptr aid.

  (** Addresses *)
  Definition disjoint_ptr_byte (a b : addr) :=
    ptr_to_int a <> ptr_to_int b.

  (*** Predicates *)

  (** Reads *)
  Definition read_byte_allowed (ms : MemState) (ptr : addr) : Prop :=
    exists aid, byte_allocated ms ptr aid /\ access_allowed (address_provenance ptr) aid = true.

  Definition read_byte_allowed_all_preserved (m1 m2 : MemState) : Prop :=
    forall ptr,
      read_byte_allowed m1 ptr <-> read_byte_allowed m2 ptr.

  Definition read_byte_prop_all_preserved (m1 m2 : MemState) : Prop :=
    forall ptr byte,
      read_byte_prop m1 ptr byte <-> read_byte_prop m2 ptr byte.

  Definition read_byte_preserved (m1 m2 : MemState) : Prop :=
    read_byte_allowed_all_preserved m1 m2 /\ read_byte_prop_all_preserved m1 m2.

  (** Writes *)
  Definition write_byte_allowed (ms : MemState) (ptr : addr) : Prop :=
    exists aid, byte_allocated ms ptr aid /\ access_allowed (address_provenance ptr) aid = true.

  Definition write_byte_allowed_all_preserved (m1 m2 : MemState) : Prop :=
    forall ptr,
      write_byte_allowed m1 ptr <-> write_byte_allowed m2 ptr.

  (** Allocations *)
  Definition allocations_preserved (m1 m2 : MemState) : Prop :=
    forall ptr aid, byte_allocated m1 ptr aid <-> byte_allocated m2 ptr aid.

  (** Provenances / allocation ids *)
  Definition extend_provenance (ms : MemState) (new_pr : Provenance) (ms' : MemState) : Prop
    := (forall pr, used_provenance_prop ms pr -> used_provenance_prop ms' pr) /\
         ~ used_provenance_prop ms new_pr /\
         used_provenance_prop ms' new_pr.

  Definition preserve_allocation_ids (ms ms' : MemState) : Prop
    := forall p, used_provenance_prop ms p <-> used_provenance_prop ms' p.

  (** Store ids *)
  Definition used_store_id_prop (ms : MemState) (sid : store_id) : Prop
    := exists ptr byte, read_byte_prop ms ptr byte /\ sbyte_sid byte = inr sid.

  Definition fresh_store_id (ms : MemState) (new_sid : store_id) : Prop
    := ~ used_store_id_prop ms new_sid.

  (** Frame stack *)
  Definition frame_stack_preserved (m1 m2 : MemState) : Prop
    := forall fs,
      memory_stack_frame_stack_prop (MemState_get_memory m1) fs <-> memory_stack_frame_stack_prop (MemState_get_memory m2) fs.

  (*** Provenance operations *)
  #[global] Instance MemPropT_MonadProvenance : MonadProvenance Provenance (MemPropT MemState).
  Proof.
    (* Need to be careful with allocation ids / provenances (more so than store ids)

       They can never be reused. E.g., if you have a pointer `p` with
       allocation id `aid`, and that block is freed, you can't reuse
       `aid` without causing problems. If you allocate a new block
       with `aid` again, then `p` may still be around and may be able
       to access the block.

       Therefore the MemState has to have some idea of what allocation
       ids have been used in the past, not just the allocation ids
       that are *currently* in use.
    *)
    split.
    - (* fresh_provenance *)
      unfold MemPropT.
      intros ms [[[[[[[oom_res] | [[ub_res] | [[err_res] | [ms' new_pr]]]]]]]]].
      + exact True.
      + exact False.
      + exact True.
      + exact
          ( extend_provenance ms new_pr ms' /\
              read_byte_preserved ms ms' /\
              write_byte_allowed_all_preserved ms ms' /\
              allocations_preserved ms ms' /\
              frame_stack_preserved ms ms'
          ).
  Defined.

  (*** Store id operations *)
  #[global] Instance MemPropT_MonadStoreID : MonadStoreId (MemPropT MemState).
  Proof.
    split.
    - (* fresh_sid *)
      unfold MemPropT.
      intros ms [[[[[[[oom_res] | [[ub_res] | [[err_res] | [ms' new_sid]]]]]]]]].
      + exact True.
      + exact False.
      + exact True.
      + exact
          ( fresh_store_id ms' new_sid /\
              preserve_allocation_ids ms ms' /\
              read_byte_preserved ms ms' /\
              write_byte_allowed_all_preserved ms ms' /\
              allocations_preserved ms ms' /\
              frame_stack_preserved ms ms'
          ).
  Defined.

  (*** Reading from memory *)
  Record read_byte_spec (ms : MemState) (ptr : addr) (byte : SByte) : Prop :=
    { read_byte_allowed_spec : read_byte_allowed ms ptr;
      read_byte_value : read_byte_prop ms ptr byte;
    }.

  Definition read_byte_spec_MemPropT (ptr : addr) : MemPropT MemState SByte :=
    fun m1 res =>
      match run_err_ub_oom res with
      | inl (OOM_message x) =>
          True
      | inr (inl (UB_message x)) =>
          forall byte, ~ read_byte_spec m1 ptr byte
      | inr (inr (inl (ERR_message x))) =>
          True
      | inr (inr (inr (m2, byte))) =>
          m1 = m2 /\ read_byte_spec m1 ptr byte
      end.

  (*** Framestack operations *)
  Definition empty_frame (f : Frame) : Prop :=
    forall ptr, ~ ptr_in_frame_prop f ptr.

  Record add_ptr_to_frame (f1 : Frame) (ptr : addr) (f2 : Frame) : Prop :=
    {
      old_frame_lu : forall ptr', disjoint_ptr_byte ptr ptr' ->
                             ptr_in_frame_prop f1 ptr' <-> ptr_in_frame_prop f2 ptr';
      new_frame_lu : ptr_in_frame_prop f2 ptr;
    }.

  Record empty_frame_stack (fs : FrameStack) : Prop :=
    {
      no_pop : (forall f, ~ pop_frame_stack_prop fs f);
      empty_fs_empty_frame : forall f, peek_frame_stack_prop fs f -> empty_frame f;
    }.

  Record push_frame_stack_spec (fs1 : FrameStack) (f : Frame) (fs2 : FrameStack) : Prop :=
    {
      can_pop : pop_frame_stack_prop fs2 fs1;
      new_frame : peek_frame_stack_prop fs2 f;
    }.

  Definition ptr_in_current_frame (ms : MemState) (ptr : addr) : Prop
    := forall fs, memory_stack_frame_stack_prop (MemState_get_memory ms) fs ->
             forall f, peek_frame_stack_prop fs f ->
                  ptr_in_frame_prop f ptr.

  (** mempush *)
  Record mempush_operation_invariants (m1 : MemState) (m2 : MemState) :=
    {
      mempush_op_reads : read_byte_preserved m1 m2;
      mempush_op_write_allowed : write_byte_allowed_all_preserved m1 m2;
      mempush_op_allocations : allocations_preserved m1 m2;
      mempush_op_allocation_ids : preserve_allocation_ids m1 m2;
    }.

  Record mempush_spec (m1 : MemState) (m2 : MemState) : Prop :=
    {
      fresh_frame :
      forall fs1 fs2 f,
        memory_stack_frame_stack_prop (MemState_get_memory m1) fs1 ->
        empty_frame f ->
        push_frame_stack_spec fs1 f fs2 ->
        memory_stack_frame_stack_prop (MemState_get_memory m2) fs2;

      mempush_invariants :
      mempush_operation_invariants m1 m2;
    }.

  Definition mempush_spec_MemPropT : MemPropT MemState unit :=
    fun m1 res =>
      match run_err_ub_oom res with
      | inl (OOM_message x) =>
          True
      | inr (inl (UB_message x)) =>
          forall m2, ~ mempush_spec m1 m2
      | inr (inr (inl (ERR_message x))) =>
          True
      | inr (inr (inr (m2, tt))) =>
          mempush_spec m1 m2
      end.

  (** mempop *)
  Record mempop_operation_invariants (m1 : MemState) (m2 : MemState) :=
    {
      mempop_op_allocation_ids : preserve_allocation_ids m1 m2;
    }.

  Record mempop_spec (m1 : MemState) (m2 : MemState) : Prop :=
    {
      (* all bytes in popped frame are freed. *)
      bytes_freed :
      forall ptr,
        ptr_in_current_frame m1 ptr ->
        byte_not_allocated m2 ptr;

      (* Bytes not allocated in the popped frame have the same allocation status as before *)
      non_frame_bytes_preserved :
      forall ptr aid,
        (~ ptr_in_current_frame m1 ptr) ->
        byte_allocated m1 ptr aid <-> byte_allocated m2 ptr aid;

      (* Bytes not allocated in the popped frame are the same when read *)
      non_frame_bytes_read :
      forall ptr byte,
        (~ ptr_in_current_frame m1 ptr) ->
        read_byte_spec m1 ptr byte <-> read_byte_spec m2 ptr byte;

      (* Set new framestack *)
      pop_frame :
      forall fs1 fs2,
        memory_stack_frame_stack_prop (MemState_get_memory m1) fs1 ->
        pop_frame_stack_prop fs1 fs2 ->
        memory_stack_frame_stack_prop (MemState_get_memory m2) fs2;

      (* Invariants *)
      mempop_invariants : mempop_operation_invariants m1 m2;
    }.

  Definition mempop_spec_MemPropT : MemPropT MemState unit :=
    fun m1 res =>
      match run_err_ub_oom res with
      | inl (OOM_message x) =>
          True
      | inr (inl (UB_message x)) =>
          forall m2, ~ mempop_spec m1 m2
      | inr (inr (inl (ERR_message x))) =>
          True
      | inr (inr (inr (m2, tt))) =>
          mempop_spec m1 m2
      end.

  (* Add a pointer onto the current frame in the frame stack *)
  Definition add_ptr_to_frame_stack (fs1 : FrameStack) (ptr : addr) (fs2 : FrameStack) : Prop :=
    forall f,
      peek_frame_stack_prop fs1 f ->
      exists f', add_ptr_to_frame f ptr f' /\
              peek_frame_stack_prop fs2 f' /\
              (forall fs1_pop, pop_frame_stack_prop fs1 fs1_pop <-> pop_frame_stack_prop fs2 fs1_pop).

  Fixpoint add_ptrs_to_frame_stack (fs1 : FrameStack) (ptrs : list addr) (fs2 : FrameStack) : Prop :=
    match ptrs with
    | nil => frame_stack_eqv fs1 fs2
    | (ptr :: ptrs) =>
        exists fs',
          add_ptrs_to_frame_stack fs1 ptrs fs' /\
            add_ptr_to_frame_stack fs' ptr fs2
    end.

  (*** Writing to memory *)
  Record set_byte_memory (m1 : MemState) (ptr : addr) (byte : SByte) (m2 : MemState) : Prop :=
    {
      new_lu : read_byte_spec m2 ptr byte;
      old_lu : forall ptr' byte',
        disjoint_ptr_byte ptr ptr' ->
        (read_byte_spec m1 ptr' byte' <-> read_byte_spec m2 ptr' byte');
    }.

  Record write_byte_operation_invariants (m1 m2 : MemState) : Prop :=
    {
      write_byte_op_preserves_allocations : allocations_preserved m1 m2;
      write_byte_op_preserves_frame_stack : frame_stack_preserved m1 m2;
      write_byte_op_read_allowed : read_byte_allowed_all_preserved m1 m2;
      write_byte_op_write_allowed : write_byte_allowed_all_preserved m1 m2;
      write_byte_op_allocation_ids : preserve_allocation_ids m1 m2;
    }.

  Record write_byte_spec (m1 : MemState) (ptr : addr) (byte : SByte) (m2 : MemState) : Prop :=
    {
      byte_write_succeeds : write_byte_allowed m1 ptr;
      byte_written : set_byte_memory m1 ptr byte m2;

      write_byte_invariants : write_byte_operation_invariants m1 m2;
    }.

  Definition write_byte_spec_MemPropT (ptr : addr) (byte : SByte) : MemPropT MemState unit
    := fun m1 res =>
         match run_err_ub_oom res with
         | inl (OOM_message x) =>
             True
         | inr (inl (UB_message x)) =>
             forall m2, ~ write_byte_spec m1 ptr byte m2
         | inr (inr (inl (ERR_message x))) =>
             True
         | inr (inr (inr (m2, tt))) =>
             write_byte_spec m1 ptr byte m2
         end.

  (*** Allocating bytes in memory *)
  Record allocate_bytes_succeeds_spec (m1 : MemState) (t : dtyp) (init_bytes : list SByte) (pr : Provenance) (m2 : MemState) (ptr : addr) (ptrs : list addr) : Prop :=
    {
      (* The allocated pointers are consecutive in memory. *)
      (* m1 doesn't really matter here. *)
      allocate_bytes_consecutive : get_consecutive_ptrs ptr (length init_bytes) m1 (ret (m1, ptrs));

      (* Provenance *)
      allocate_bytes_address_provenance : address_provenance ptr = allocation_id_to_prov (provenance_to_allocation_id pr); (* Need this case if `ptrs` is empty (allocating 0 bytes) *)
      allocate_bytes_addresses_provenance : forall ptr, In ptr ptrs -> address_provenance ptr = allocation_id_to_prov (provenance_to_allocation_id pr);
      allocate_bytes_provenances_preserved :
      forall pr',
        (used_provenance_prop m1 pr' <-> used_provenance_prop m2 pr');

      (* byte_allocated *)
      allocate_bytes_was_fresh_byte : forall ptr, In ptr ptrs -> byte_not_allocated m1 ptr;
      allocate_bytes_now_byte_allocated : forall ptr, In ptr ptrs -> byte_allocated m2 ptr (provenance_to_allocation_id pr);
      allocate_bytes_preserves_old_allocations :
      forall ptr aid,
        (forall p, In p ptrs -> disjoint_ptr_byte p ptr) ->
        (byte_allocated m1 ptr aid <-> byte_allocated m2 ptr aid);

      (* read permissions *)
      alloc_bytes_new_reads_allowed :
      forall p, In p ptrs ->
           read_byte_allowed m2 p;

      alloc_bytes_old_reads_allowed :
      forall ptr',
        (forall p, In p ptrs -> disjoint_ptr_byte p ptr') ->
        read_byte_allowed m1 ptr' <-> read_byte_allowed m2 ptr';

      (* reads *)
      alloc_bytes_new_reads :
      forall p ix byte,
        Util.Nth ptrs ix p ->
        Util.Nth init_bytes ix byte ->
        read_byte_prop m2 p byte;

      alloc_bytes_old_reads :
      forall ptr' byte,
        (forall p, In p ptrs -> disjoint_ptr_byte p ptr') ->
        read_byte_prop m1 ptr' byte <-> read_byte_prop m2 ptr' byte;

      (* write permissions *)
      alloc_bytes_new_writes_allowed :
      forall p, In p ptrs ->
           write_byte_allowed m2 p;

      alloc_bytes_old_writes_allowed :
      forall ptr',
        (forall p, In p ptrs -> disjoint_ptr_byte p ptr') ->
        write_byte_allowed m1 ptr' <-> write_byte_allowed m2 ptr';

      (* Add allocated bytes onto the stack frame *)
      allocate_bytes_add_to_frame :
      forall fs1 fs2,
        memory_stack_frame_stack_prop (MemState_get_memory m1) fs1 ->
        add_ptrs_to_frame_stack fs1 ptrs fs2 ->
        memory_stack_frame_stack_prop (MemState_get_memory m2) fs2;

      (* Type is valid *)
      allocate_bytes_typ :
      t <> DTYPE_Void;

      allocate_bytes_typ_size :
      sizeof_dtyp t = N.of_nat (length init_bytes);
    }.

  Definition allocate_bytes_spec_MemPropT' (t : dtyp) (init_bytes : list SByte) (prov : Provenance)
    : MemPropT MemState (addr * list addr)
    := fun m1 res =>
         match run_err_ub_oom res with
         | inl (OOM_message x) =>
             True
         | inr (inl (UB_message x)) =>
             forall m2 ptr ptrs, ~ allocate_bytes_succeeds_spec m1 t init_bytes prov m2 ptr ptrs
         | inr (inr (inl (ERR_message x))) =>
             True
         | inr (inr (inr (m2, (ptr, ptrs)))) =>
             allocate_bytes_succeeds_spec m1 t init_bytes prov m2 ptr ptrs
         end.

  Definition allocate_bytes_spec_MemPropT (t : dtyp) (init_bytes : list SByte)
    : MemPropT MemState addr
    := prov <- fresh_provenance;;
       '(ptr, _) <- allocate_bytes_spec_MemPropT' t init_bytes prov;;
       ret ptr.

  (*** Aggregate things *)

  (** Reading uvalues *)
  Definition read_bytes_spec (ptr : addr) (len : nat) : MemPropT MemState (list SByte) :=
    (* TODO: should this OOM, or should this count as walking outside of memory and be UB? *)
    ptrs <- get_consecutive_ptrs ptr len;;

    (* Actually perform reads *)
    Util.map_monad (fun ptr => read_byte_spec_MemPropT ptr) ptrs.

  Definition read_uvalue_spec (dt : dtyp) (ptr : addr) : MemPropT MemState uvalue :=
    bytes <- read_bytes_spec ptr (N.to_nat (sizeof_dtyp dt));;
    lift_err_RAISE_ERROR (deserialize_sbytes bytes dt).

  (** Writing uvalues *)
  Definition write_bytes_spec (ptr : addr) (bytes : list SByte) : MemPropT MemState unit :=
    ptrs <- get_consecutive_ptrs ptr (length bytes);;
    let ptr_bytes := zip ptrs bytes in

    (* TODO: double check that this is correct... Should we check if all writes are allowed first? *)
    (* Actually perform writes *)
    Util.map_monad_ (fun '(ptr, byte) => write_byte_spec_MemPropT ptr byte) ptr_bytes.

  Definition write_uvalue_spec (dt : dtyp) (ptr : addr) (uv : uvalue) : MemPropT MemState unit :=
    bytes <- serialize_sbytes uv dt;;
    write_bytes_spec ptr bytes.

  (** Allocating dtyps *)
  (* Need to make sure MemPropT has provenance and sids to generate the bytes. *)
  Definition allocate_dtyp_spec (dt : dtyp) : MemPropT MemState addr :=
    sid <- fresh_sid;;
    bytes <- lift_OOM (generate_undef_bytes dt sid);;
    allocate_bytes_spec_MemPropT dt bytes.

  (** memcpy spec *)
  Definition memcpy_spec (src dst : addr) (len : Z) (align : N) (volatile : bool) : MemPropT MemState unit :=
    if Z.ltb len 0
    then
      raise_ub "memcpy given negative length."
    else
      (* From LangRef: The ‘llvm.memcpy.*’ intrinsics copy a block of
       memory from the source location to the destination location, which
       must either be equal or non-overlapping.
       *)
      if orb (no_overlap dst len src len)
             (Z.eqb (ptr_to_int src) (ptr_to_int dst))
      then
        src_bytes <- read_bytes_spec src (Z.to_nat len);;

        (* TODO: Double check that this is correct... Should we check if all writes are allowed first? *)
        write_bytes_spec dst src_bytes
      else
        raise_ub "memcpy with overlapping or non-equal src and dst memory locations.".

  (*** Handling memory events *)
  Section Handlers.
    Definition handle_memory_prop : MemoryE ~> MemPropT MemState
      := fun T m =>
           match m with
           (* Unimplemented *)
           | MemPush =>
               mempush_spec_MemPropT
           | MemPop =>
               mempop_spec_MemPropT
           | Alloca t =>
               addr <- allocate_dtyp_spec t;;
               ret (DVALUE_Addr addr)
           | Load t a =>
               match a with
               | DVALUE_Addr a =>
                   read_uvalue_spec t a
               | _ => raise_ub "Loading from something that isn't an address."
               end
           | Store t a v =>
               match a with
               | DVALUE_Addr a =>
                   write_uvalue_spec t a v
               | _ => raise_ub "Writing something to somewhere that isn't an address."
               end
           end.

    Definition handle_memcpy_prop (args : list dvalue) : MemPropT MemState unit :=
      match args with
      | DVALUE_Addr dst ::
                    DVALUE_Addr src ::
                    DVALUE_I32 len ::
                    DVALUE_I32 align :: (* alignment ignored *)
                    DVALUE_I1 volatile :: [] (* volatile ignored *)  =>
          memcpy_spec src dst (unsigned len) (Z.to_N (unsigned align)) (equ volatile one)
      | DVALUE_Addr dst ::
                    DVALUE_Addr src ::
                    DVALUE_I64 len ::
                    DVALUE_I64 align :: (* alignment ignored *)
                    DVALUE_I1 volatile :: [] (* volatile ignored *)  =>
          memcpy_spec src dst (unsigned len) (Z.to_N (unsigned align)) (equ volatile one)
      | DVALUE_Addr dst ::
                    DVALUE_Addr src ::
                    DVALUE_IPTR len ::
                    DVALUE_IPTR align :: (* alignment ignored *)
                    DVALUE_I1 volatile :: [] (* volatile ignored *)  =>
          memcpy_spec src dst (IP.to_Z len) (Z.to_N (IP.to_Z align)) (equ volatile one)
      | _ => raise_error "Unsupported arguments to memcpy."
      end.

    Definition handle_intrinsic_prop : IntrinsicE ~> MemPropT MemState
      := fun T e =>
           match e with
           | Intrinsic t name args =>
               (* Pick all arguments, they should all be unique. *)
               (* TODO: add more variants to memcpy *)
               (* FIXME: use reldec typeclass? *)
               if orb (Coqlib.proj_sumbool (string_dec name "llvm.memcpy.p0i8.p0i8.i32"))
                      (Coqlib.proj_sumbool (string_dec name "llvm.memcpy.p0i8.p0i8.i64"))
               then
                 handle_memcpy_prop args;;
                 ret DVALUE_None
               else
                 raise_error ("Unknown intrinsic: " ++ name)
           end.

  End Handlers.
End MemoryModelSpec.

Module MakeMemoryModelSpec (LP : LLVMParams) (MP : MemoryParams LP) (MMSP : MemoryModelSpecPrimitives LP MP) <: MemoryModelSpec LP MP MMSP.
  Include MemoryModelSpec LP MP MMSP.
End MakeMemoryModelSpec.

Module Type MemoryExecMonad (LP : LLVMParams) (MP : MemoryParams LP) (MMSP : MemoryModelSpecPrimitives LP MP) (MMS : MemoryModelSpec LP MP MMSP).
  (* TODO: move these imports *)
  Import EitherMonad.
  Import Monad.
  Require Import Morphisms.
  From Vellvm Require Import
       MonadEq1Laws
       Raise.

  Import LP.
  Import PROV.
  Import MMSP.
  Import MMS.

  Class MemMonad (ExtraState : Type) (M : Type -> Type) (RunM : Type -> Type)
        `{MM : Monad M} `{MRun: Monad RunM}
        `{MPROV : MonadProvenance Provenance M} `{MSID : MonadStoreId M} `{MMS: MonadMemState MemState M}
        `{MERR : RAISE_ERROR M} `{MUB : RAISE_UB M} `{MOOM :RAISE_OOM M}
        `{RunERR : RAISE_ERROR RunM} `{RunUB : RAISE_UB RunM} `{RunOOM :RAISE_OOM RunM}
    : Type
    :=
    { MemMonad_eq1_runm :> Eq1 RunM;
      MemMonad_runm_monadlaws :> MonadLawsE RunM;
      MemMonad_eq1_runm_equiv {A} :> Equivalence (@eq1 _ MemMonad_eq1_runm A);
      MemMonad_eq1_runm_eq1laws :> Eq1_ret_inv RunM;
      MemMonad_raisebindm_ub :> RaiseBindM RunM string (@raise_ub RunM RunUB);
      MemMonad_raisebindm_oom :> RaiseBindM RunM string (@raise_oom RunM RunOOM);
      MemMonad_raisebindm_err :> RaiseBindM RunM string (@raise_error RunM RunERR);

      MemMonad_eq1_runm_proper :>
                               (forall A, Proper ((@eq1 _ MemMonad_eq1_runm) A ==> (@eq1 _ MemMonad_eq1_runm) A ==> iff) ((@eq1 _ MemMonad_eq1_runm) A));

      MemMonad_run {A} (ma : M A) (ms : MemState) (st : ExtraState)
      : RunM (ExtraState * (MemState * A))%type;

      (** Whether a piece of extra state is valid for a given execution *)
      MemMonad_valid_state : MemState -> ExtraState -> Prop;

    (** Run bind / ret laws *)
    MemMonad_run_bind
      {A B} (ma : M A) (k : A -> M B) (ms : MemState) (st : ExtraState):
    eq1 (MemMonad_run (x <- ma;; k x) ms st)
        ('(st', (ms', x)) <- MemMonad_run ma ms st;; MemMonad_run (k x) ms' st');

    MemMonad_run_ret
      {A} (x : A) (ms : MemState) st:
    eq1 (MemMonad_run (ret x) ms st) (ret (st, (ms, x)));

    (** MonadMemState properties *)
    MemMonad_get_mem_state
      (ms : MemState) st :
    eq1 (MemMonad_run (get_mem_state) ms st) (ret (st, (ms, ms)));

    MemMonad_put_mem_state
      (ms ms' : MemState) st :
    eq1 (MemMonad_run (put_mem_state ms') ms st) (ret (st, (ms', tt)));

    (** Fresh store id property *)
    MemMonad_run_fresh_sid
      (ms : MemState) st (VALID : MemMonad_valid_state ms st):
    exists st' sid',
      eq1 (MemMonad_run (fresh_sid) ms st) (ret (st', (ms, sid'))) /\
        MemMonad_valid_state ms st' /\
        ~ used_store_id_prop ms sid';

    (** Fresh provenance property *)
    (* TODO: unclear if this should exist, must change ms. *)
    MemMonad_run_fresh_provenance
      (ms : MemState) st (VALID : MemMonad_valid_state ms st):
    exists ms' pr',
      eq1 (MemMonad_run (fresh_provenance) ms st) (ret (st, (ms', pr'))) /\
        MemMonad_valid_state ms' st /\
        ms_get_memory ms = ms_get_memory ms' /\
        (* Analogous to extend_provenance *)
        (forall pr, used_provenance_prop ms pr -> used_provenance_prop ms' pr) /\
        ~ used_provenance_prop ms pr' /\
        used_provenance_prop ms' pr';

    (** Exceptions *)
    MemMonad_run_raise_oom :
    forall {A} ms oom_msg st,
      eq1 (MemMonad_run (@raise_oom _ _ A oom_msg) ms st) (raise_oom oom_msg);

    MemMonad_eq1_raise_oom_inv :
    forall {A} x oom_msg,
      ~ ((@eq1 _ MemMonad_eq1_runm) A (ret x) (raise_oom oom_msg));

    MemMonad_run_raise_ub :
    forall {A} ms ub_msg st,
      eq1 (MemMonad_run (@raise_ub _ _ A ub_msg) ms st) (raise_ub ub_msg);

    MemMonad_run_raise_error :
    forall {A} ms error_msg st,
      eq1 (MemMonad_run (@raise_error _ _ A error_msg) ms st) (raise_error error_msg);

    MemMonad_eq1_raise_error_inv :
    forall {A} x error_msg,
      ~ ((@eq1 _ MemMonad_eq1_runm) A (ret x) (raise_error error_msg));
  }.

    (*** Correctness *)
    Definition exec_correct {MemM Eff ExtraState} `{MM: MemMonad ExtraState MemM (itree Eff)} {X} (exec : MemM X) (spec : MemPropT MemState X) : Prop :=
      forall ms st,
        (@MemMonad_valid_state ExtraState MemM (itree Eff) _ _ _ _ _ _ _ _ _ _ _ _ ms st) ->
        let t := MemMonad_run exec ms st in
        let eqi := (@eq1 _ (@MemMonad_eq1_runm _ _ _ _ _ _ _ _ _ _ _ _ _ _ MM)) in
        (* UB *)
        (exists msg_spec,
            spec ms (raise_ub msg_spec)) \/
          (* Error *)
          ((exists msg msg_spec,
               eqi _ t (raise_error msg) ->
               spec ms (raise_error msg_spec))) /\
          (* OOM *)
          (exists msg msg_spec,
              eqi _ t (raise_oom msg) ->
              spec ms (raise_oom msg_spec)) /\
          (* Success *)
          (forall st' ms' x,
              eqi _ t (ret (st', (ms', x))) ->
              spec ms (ret (ms', x))).

    Definition exec_correct_memory {MemM Eff ExtraState} `{MM: MemMonad ExtraState MemM (itree Eff)} {X} (exec : MemM X) (spec : MemPropT memory_stack X) : Prop :=
      exec_correct exec (lift_memory_MemPropT spec).

    Lemma exec_correct_lift_memory :
      forall {MemM Eff ExtraState} `{MemMonad ExtraState MemM (itree Eff)}
        {X} (exec : MemM X)  (spec : MemPropT memory_stack X),
        exec_correct_memory exec spec ->
        exec_correct exec (lift_memory_MemPropT spec).
    Proof.
      intros * EXEC.
      unfold exec_correct_memory in EXEC.
      auto.
    Qed.
End MemoryExecMonad.

Module MakeMemoryExecMonad (LP : LLVMParams) (MP : MemoryParams LP) (MMSP : MemoryModelSpecPrimitives LP MP) (MMS : MemoryModelSpec LP MP MMSP) <: MemoryExecMonad LP MP MMSP MMS.
  Include MemoryExecMonad LP MP MMSP MMS.
End MakeMemoryExecMonad.

Module Type MemoryModelExecPrimitives (LP : LLVMParams) (MP : MemoryParams LP).
  Import LP.
  Import LP.ADDR.
  Import LP.SIZEOF.
  Import LP.PROV.
  Import MP.

  (** Specification of the memory model *)
  Declare Module MMSP : MemoryModelSpecPrimitives LP MP.
  Import MMSP.
  Import MMSP.MemByte.

  Module MemSpec := MakeMemoryModelSpec LP MP MMSP.
  Import MemSpec.

  Module MemExecM := MakeMemoryExecMonad LP MP MMSP MemSpec.
  Import MemExecM.

  Section MemoryPrimatives.
    Context {MemM : Type -> Type}.
    Context {Eff : Type -> Type}.
    Context {ExtraState : Type}.
    Context `{MM : MemMonad ExtraState MemM (itree Eff)}.

    (*** Data types *)
    Parameter initial_memory_state : MemState.
    Parameter initial_frame : Frame.

    (*** Primitives on memory *)
    (** Reads *)
    Parameter read_byte :
      forall `{MemMonad ExtraState MemM (itree Eff)}, addr -> MemM SByte.

    (** Writes *)
    Parameter write_byte :
      forall `{MemMonad ExtraState MemM (itree Eff)}, addr -> SByte -> MemM unit.

    (** Allocations *)
    Parameter allocate_bytes :
      forall `{MemMonad ExtraState MemM (itree Eff)}, dtyp -> list SByte -> MemM addr.

    (** Frame stacks *)
    Parameter mempush : forall `{MemMonad ExtraState MemM (itree Eff)}, MemM unit.
    Parameter mempop : forall `{MemMonad ExtraState MemM (itree Eff)}, MemM unit.

    (*** Correctness *)

    (** Correctness of the main operations on memory *)
    Parameter read_byte_correct :
      forall ptr, exec_correct (read_byte ptr) (read_byte_spec_MemPropT ptr).

    Parameter write_byte_correct :
      forall ptr byte, exec_correct (write_byte ptr byte) (write_byte_spec_MemPropT ptr byte).

    Parameter allocate_bytes_correct :
      forall dt init_bytes, exec_correct (allocate_bytes dt init_bytes) (allocate_bytes_spec_MemPropT dt init_bytes).

    (** Correctness of frame stack operations *)
    Parameter mempush_correct :
      exec_correct mempush mempush_spec_MemPropT.

    Parameter mempop_correct :
      exec_correct mempop mempop_spec_MemPropT.

    (*** Initial memory state *)
    Record initial_memory_state_prop : Prop :=
      {
        initial_memory_no_allocations :
        forall ptr aid,
          ~ byte_allocated initial_memory_state ptr aid;

        initial_memory_frame_stack :
        forall fs,
          memory_stack_frame_stack_prop (MemState_get_memory initial_memory_state) fs ->
          empty_frame_stack fs;

        initial_memory_no_reads :
        forall ptr byte,
          ~ read_byte_prop initial_memory_state ptr byte
      }.

    Record initial_frame_prop : Prop :=
      {
        initial_frame_is_empty : empty_frame initial_frame;
      }.

    Parameter initial_memory_state_correct : initial_memory_state_prop.
    Parameter initial_frame_correct : initial_frame_prop.
  End MemoryPrimatives.
End MemoryModelExecPrimitives.

Module Type MemoryModelExec (LP : LLVMParams) (MP : MemoryParams LP) (MMEP : MemoryModelExecPrimitives LP MP).
  Import LP.
  Import LP.ADDR.
  Import LP.SIZEOF.
  Import LP.PROV.
  Import LP.PTOI.
  Import LP.Events.
  Import MP.
  Import MMEP.
  Import MemExecM.
  Import MMSP.
  Import MMSP.MemByte.
  Import MMEP.MemSpec.
  Import MemHelpers.

  Module OVER := PTOIOverlaps ADDR PTOI SIZEOF.
  Import OVER.
  Module OVER_H := OverlapHelpers ADDR SIZEOF OVER.
  Import OVER_H.

  (*** Handling memory events *)
  Section Handlers.
    Context {MemM : Type -> Type}.
    Context {Eff : Type -> Type}.
    Context {ExtraState : Type}.
    Context `{MM : MemMonad ExtraState MemM (itree Eff)}.

    (** Reading uvalues *)
    Definition read_bytes `{MemMonad ExtraState MemM (itree Eff)} (ptr : addr) (len : nat) : MemM (list SByte) :=
      (* TODO: this should maybe be UB and not OOM??? *)
      ptrs <- get_consecutive_ptrs ptr len;;

      (* Actually perform reads *)
      Util.map_monad (fun ptr => read_byte ptr) ptrs.

    Definition read_uvalue `{MemMonad ExtraState MemM (itree Eff)} (dt : dtyp) (ptr : addr) : MemM uvalue :=
      bytes <- read_bytes ptr (N.to_nat (sizeof_dtyp dt));;
      lift_err_RAISE_ERROR (deserialize_sbytes bytes dt).

    (** Writing uvalues *)
    Definition write_bytes `{MemMonad ExtraState MemM (itree Eff)} (ptr : addr) (bytes : list SByte) : MemM unit :=
      (* TODO: Should this be UB instead of OOM? *)
      ptrs <- get_consecutive_ptrs ptr (length bytes);;
      let ptr_bytes := zip ptrs bytes in

      (* Actually perform writes *)
      Util.map_monad_ (fun '(ptr, byte) => write_byte ptr byte) ptr_bytes.

    Definition write_uvalue `{MemMonad ExtraState MemM (itree Eff)} (dt : dtyp) (ptr : addr) (uv : uvalue) : MemM unit :=
      bytes <- serialize_sbytes uv dt;;
      write_bytes ptr bytes.

    (** Allocating dtyps *)
    (* Need to make sure MemPropT has provenance and sids to generate the bytes. *)
    Definition allocate_dtyp `{MemMonad ExtraState MemM (itree Eff)} (dt : dtyp) : MemM addr :=
      sid <- fresh_sid;;
      bytes <- lift_OOM (generate_undef_bytes dt sid);;
      allocate_bytes dt bytes.

    (** Handle memcpy *)
    Definition memcpy `{MemMonad ExtraState MemM (itree Eff)} (src dst : addr) (len : Z) (align : N) (volatile : bool) : MemM unit :=
      if Z.ltb len 0
      then
        raise_ub "memcpy given negative length."
      else
        (* From LangRef: The ‘llvm.memcpy.*’ intrinsics copy a block of
       memory from the source location to the destination location, which
       must either be equal or non-overlapping.
         *)
        if orb (no_overlap dst len src len)
               (Z.eqb (ptr_to_int src) (ptr_to_int dst))
        then
          src_bytes <- read_bytes src (Z.to_nat len);;

          (* TODO: Double check that this is correct... Should we check if all writes are allowed first? *)
          write_bytes dst src_bytes
        else
          raise_ub "memcpy with overlapping or non-equal src and dst memory locations.".

    Definition handle_memory `{MemMonad ExtraState MemM (itree Eff)} : MemoryE ~> MemM
      := fun T m =>
           match m with
           (* Unimplemented *)
           | MemPush =>
               mempush
           | MemPop =>
               mempop
           | Alloca t =>
               addr <- allocate_dtyp t;;
               ret (DVALUE_Addr addr)
           | Load t a =>
               match a with
               | DVALUE_Addr a =>
                   read_uvalue t a
               | _ =>
                   raise_ub "Loading from something that is not an address."
               end
           | Store t a v =>
               match a with
               | DVALUE_Addr a =>
                   write_uvalue t a v
               | _ =>
                   raise_ub "Store to somewhere that is not an address."
               end
           end.

    Definition handle_memcpy `{MemMonad ExtraState MemM (itree Eff)} (args : list dvalue) : MemM unit :=
      match args with
      | DVALUE_Addr dst ::
                    DVALUE_Addr src ::
                    DVALUE_I32 len ::
                    DVALUE_I32 align :: (* alignment ignored *)
                    DVALUE_I1 volatile :: [] (* volatile ignored *)  =>
          memcpy src dst (unsigned len) (Z.to_N (unsigned align)) (equ volatile one)
      | DVALUE_Addr dst ::
                    DVALUE_Addr src ::
                    DVALUE_I64 len ::
                    DVALUE_I64 align :: (* alignment ignored *)
                    DVALUE_I1 volatile :: [] (* volatile ignored *)  =>
          memcpy src dst (unsigned len) (Z.to_N (unsigned align)) (equ volatile one)
      | DVALUE_Addr dst ::
                    DVALUE_Addr src ::
                    DVALUE_IPTR len ::
                    DVALUE_IPTR align :: (* alignment ignored *)
                    DVALUE_I1 volatile :: [] (* volatile ignored *)  =>
          memcpy src dst (IP.to_Z len) (Z.to_N (IP.to_Z align)) (equ volatile one)
      | _ => raise_error "Unsupported arguments to memcpy."
      end.

    Definition handle_intrinsic `{MemMonad ExtraState MemM (itree Eff)} : IntrinsicE ~> MemM
      := fun T e =>
           match e with
           | Intrinsic t name args =>
               (* Pick all arguments, they should all be unique. *)
               (* TODO: add more variants to memcpy *)
               (* FIXME: use reldec typeclass? *)
               if orb (Coqlib.proj_sumbool (string_dec name "llvm.memcpy.p0i8.p0i8.i32"))
                      (Coqlib.proj_sumbool (string_dec name "llvm.memcpy.p0i8.p0i8.i64"))
               then
                 handle_memcpy args;;
                 ret DVALUE_None
               else
                 raise_error ("Unknown intrinsic: " ++ name)
           end.
  End Handlers.
End MemoryModelExec.

Module MakeMemoryModelExec (LP : LLVMParams) (MP : MemoryParams LP) (MMEP : MemoryModelExecPrimitives LP MP) <: MemoryModelExec LP MP MMEP.
  Include MemoryModelExec LP MP MMEP.
End MakeMemoryModelExec.

Module MemoryModelTheory (LP : LLVMParams) (MP : MemoryParams LP) (MMEP : MemoryModelExecPrimitives LP MP) (MME : MemoryModelExec LP MP MMEP).
  Import MMEP.
  Import MME.
  Import MemSpec.
  Import MMSP.
  Import MemExecM.
  Import MemHelpers.

  Section Correctness.
    Context {MemM : Type -> Type}.
    Context {Eff : Type -> Type}.
    Context {ExtraState : Type}.
    Context `{MM : MemMonad ExtraState MemM (itree Eff)}.

    Import Monad.

    Lemma exec_correct_bind :
      forall {A B}
        (m_exec : MemM A) (k_exec : A -> MemM B)
        (m_spec : MemPropT MemState A) (k_spec : A -> MemPropT MemState B),
        exec_correct m_exec m_spec ->
        (forall a, exec_correct (k_exec a) (k_spec a)) ->
        exec_correct (a <- m_exec;; k_exec a) (a <- m_spec;; k_spec a).
    Proof.
      intros A B m_exec k_exec m_spec k_spec HM HK.
      unfold exec_correct in *.
      intros ms st VALID.

      pose proof (HM ms st VALID) as [[ubm UBM] | NUBM].
      { (* m raised UB *)
        left.
        repeat eexists; eauto.
      }

      (* m did not raise UB *)
      destruct NUBM as [ERROR [OOM SUCC]].
      right.

      split; [|split].
      { (* Error *)
        do 2 eexists; intros RUN.

        rewrite MemMonad_run_bind in RUN.
        (* I think I need some kind of inversion lemma about this *)
        admit.
      }
      admit.
      admit.
    Admitted.

    Lemma exec_correct_ret :
      forall {X} (x : X),
        exec_correct (ret x) (ret x).
    Proof.
      intros X x.
      cbn; red; cbn.
      intros ms st VALID.
      right.
      setoid_rewrite MemMonad_run_ret.
      split; [|split].
      + (* Error *)
        cbn. repeat eexists.
        exact ""%string.
        intros CONTRA.
        apply MemMonad_eq1_raise_error_inv in CONTRA; auto.
      + (* OOM *)
        cbn. repeat eexists.
        exact ""%string.
        intros CONTRA.
        apply MemMonad_eq1_raise_oom_inv in CONTRA; auto.
      + (* Success *)
        intros st' ms' x' RUN.
        apply eq1_ret_ret in RUN; [|typeclasses eauto].
        inv RUN; cbn; auto.

        Unshelve.
        all: exact ""%string.
    Qed.
        
    Lemma exec_correct_map_monad :
      forall {A B}
        xs
        (m_exec : A -> MemM B) (m_spec : A -> MemPropT MemState B),
        (forall a, exec_correct (m_exec a) (m_spec a)) ->
        exec_correct (map_monad m_exec xs) (map_monad m_spec xs).
    Proof.
      induction xs;
        intros m_exec m_spec HM.

      - unfold map_monad.
        apply exec_correct_ret.
      - rewrite map_monad_unfold.
        rewrite map_monad_unfold.

        eapply exec_correct_bind; eauto.
        intros a0.

        eapply exec_correct_bind; eauto.
        intros a1.

        apply exec_correct_ret.
    Qed.

    Lemma read_bytes_correct :
      forall len ptr,
        exec_correct (read_bytes ptr len) (read_bytes_spec ptr len).
    Proof.
      unfold read_bytes.
      unfold read_bytes_spec.
      intros len ptr.
      eapply exec_correct_bind.
      admit.

      intros a.
      eapply exec_correct_map_monad.
      intros ptr'.
      apply read_byte_correct.
    Admitted.

    (* Lemma read_bytes_correct : *)
    (*   forall len ptr, *)
    (*     exec_correct (read_bytes ptr len) (read_bytes_spec ptr len). *)
    (* Proof. *)
    (*   induction len; intros ptr. *)
    (*   { (* Reading no bytes *) *)
    (*     cbn. *)
    (*     unfold read_bytes. *)
    (*     unfold read_bytes_spec. *)
    (*     unfold get_consecutive_ptrs in *. *)
    (*     cbn. *)

    (*     unfold exec_correct. *)
    (*     intros ms st VALID. *)

    (*     (* Reading 0 bytes should always succeed *) *)
    (*     right. *)
    (*     split; [|split]. *)
    (*     { (* Error *) *)
    (*       do 2 eexists. *)
    (*       intros RUN. *)
    (*       exfalso. *)

    (*       repeat rewrite MemMonad_run_bind in RUN. *)
    (*       repeat rewrite MemMonad_run_ret in RUN. *)
    (*       repeat rewrite bind_ret_l in RUN. *)
    (*       cbn in RUN. *)

    (*       repeat rewrite MemMonad_run_ret in RUN. *)
    (*       repeat rewrite bind_ret_l in RUN. *)
    (*       cbn in RUN. *)

    (*       repeat rewrite MemMonad_run_ret in RUN. *)
    (*       repeat rewrite bind_ret_l in RUN. *)

    (*       eapply MemMonad_eq1_raise_error_inv in RUN; contradiction. *)
    (*     } *)

    (*     { (* OOM *) *)
    (*       do 2 eexists. *)
    (*       intros RUN. *)
    (*       exfalso. *)

    (*       repeat rewrite MemMonad_run_bind in RUN. *)
    (*       repeat rewrite MemMonad_run_ret in RUN. *)
    (*       repeat rewrite bind_ret_l in RUN. *)
    (*       cbn in RUN. *)

    (*       repeat rewrite MemMonad_run_ret in RUN. *)
    (*       repeat rewrite bind_ret_l in RUN. *)
    (*       cbn in RUN. *)

    (*       repeat rewrite MemMonad_run_ret in RUN. *)
    (*       repeat rewrite bind_ret_l in RUN. *)

    (*       eapply MemMonad_eq1_raise_oom_inv in RUN; contradiction. *)
    (*     } *)

    (*     { (* Success *) *)
    (*       intros st' ms' x RUN. *)

    (*       repeat rewrite MemMonad_run_bind in RUN. *)
    (*       repeat rewrite MemMonad_run_ret in RUN. *)
    (*       repeat rewrite bind_ret_l in RUN. *)
    (*       cbn in RUN. *)

    (*       repeat rewrite MemMonad_run_ret in RUN. *)
    (*       repeat rewrite bind_ret_l in RUN. *)
    (*       cbn in RUN. *)

    (*       repeat rewrite MemMonad_run_ret in RUN. *)
    (*       repeat rewrite bind_ret_l in RUN. *)
    (*       eapply eq1_ret_ret in RUN; [| typeclasses eauto]. *)
    (*       inv RUN. *)
    (*       cbn. *)

    (*       do 2 eexists. *)
    (*       split. *)
    (*       { do 2 eexists. *)
    (*         split; eauto. *)
    (*         cbn. *)
    (*         split; eauto. *)
    (*       } *)

    (*       cbn. auto.           *)
    (*     } *)
    (*   } *)

    (*   { (* Inductive case *) *)
    (*     cbn. *)
    (*     unfold read_bytes. *)
    (*     unfold read_bytes_spec. *)
    (*     unfold get_consecutive_ptrs in *. *)
    (*     cbn. *)

    (*     unfold exec_correct. *)
    (*     intros ms st VALID. *)

    (*     cbn. *)
    (*     repeat rewrite LP.IP.from_Z_0. *)

    (*     pose proof read_byte_correct ptr as READBYTE. *)
    (*     unfold exec_correct_memory in READBYTE. unfold exec_correct in READBYTE. *)
    (*     specialize (READBYTE ms st VALID). *)
    (*     destruct READBYTE as [[ubmsg [UB LIFT]] | READBYTE]. *)
    (*     { (* Reading the byte gave UB *) *)
    (*       left. *)
    (*       exists ubmsg. cbn. *)
    (*       repeat eexists. *)
    (*       left. *)
    (*       repeat eexists. *)
    (*       break_match. *)
    (*       { cbn. right. *)
    (*         repeat eexists. *)
    (*         cbn. *)
    (*         rewrite MP.GEP.handle_gep_addr_0. *)
    (*         break_match; cbn; eauto. *)
    (*         cbn in UB. *)

    (*       } *)
    (*     } *)

    (*     cbn. *)


    (*     destruct (map_monad LP.IP.from_Z (Zseq 1 len)) as [iptrs | OOM] eqn:HMAPM. *)

    (*     2: { (* OOM *) *)
    (*       right. *)
    (*       split; [|split]. *)

    (*       { (* Error *) *)
    (*         do 2 exists ""%string. *)

    (*         intros RUN. *)
    (*         exfalso. *)

    (*         repeat rewrite MemMonad_run_bind in RUN. *)
    (*         cbn in RUN. *)
    (*         repeat rewrite MemMonad_run_raise_oom in RUN. *)
    (*         rewrite rbm_raise_bind in RUN; [| typeclasses eauto]. *)
    (*         rewrite rbm_raise_bind in RUN; [| typeclasses eauto]. *)
    (*         admit. (* OOM <> error *) *)
    (*       } *)

    (*       { (* OOM *) *)
    (*         repeat eexists. *)
    (*         exact ""%string. *)
    (*         cbn. *)
    (*         left. eauto. *)
    (*       } *)

    (*       { (* Success *) *)
    (*         intros st' ms' x RUN. *)
    (*         exfalso. *)

    (*         cbn in RUN. *)
    (*         repeat rewrite MemMonad_run_bind in RUN. *)
    (*         cbn in RUN. *)
    (*         repeat rewrite MemMonad_run_raise_oom in RUN. *)
    (*         rewrite rbm_raise_bind in RUN; [| typeclasses eauto]. *)
    (*         rewrite rbm_raise_bind in RUN; [| typeclasses eauto]. *)

    (*         symmetry in RUN. *)
    (*         eapply MemMonad_eq1_raise_oom_inv in RUN. *)
    (*         contradiction. *)
    (*       } *)
    (*     } *)
        
    (*     { (* No OOM *) *)
    (*       right. *)
    (*       split; [|split]. *)

    (*       { (* Error *) *)
    (*         do 2 exists ""%string. *)

    (*         intros RUN. *)

    (*         repeat rewrite MemMonad_run_bind in RUN. *)
    (*         repeat rewrite MemMonad_run_ret in RUN. *)
    (*         repeat rewrite bind_ret_l in RUN. *)
    (*         cbn in RUN. *)

    (*         repeat rewrite MemMonad_run_ret in RUN. *)
    (*         repeat rewrite bind_ret_l in RUN. *)
    (*         cbn in RUN. *)

    (*         rewrite MP.GEP.handle_gep_addr_0 in RUN. *)
    (*         break_match_hyp. *)

    (*         { (* Error when using gep to get pointers *) *)
    (*           cbn in RUN. *)
    (*           cbn. *)
    (*           eexists. *)
    (*           left. *)
    (*           eexists. *)
    (*           right. *)
    (*           repeat eexists. *)
    (*           cbn. *)
    (*           break_match; cbn; auto. *)
    (*           rewrite Heqs. *)
    (*           cbn. auto. *)
    (*         } *)

    (*         cbn in RUN. *)
    (*         repeat rewrite MemMonad_run_ret in RUN. *)
    (*         repeat rewrite bind_ret_l in RUN. *)

    (*         rewrite map_monad_unfold in RUN. *)
    (*         repeat rewrite MemMonad_run_bind in RUN. *)

    (*         (* TODO: RUN should be a contradiction if read_byte succeeds... *)

    (*            Unfortunately, I don't know anything about MemMonad_run and read_byte... *)
    (*          *) *)
    (*         (* I *DO* know read_byte_correct, though... *) *)
    (*         pose proof read_byte_correct ptr as READBYTE. *)
    (*         unfold exec_correct_memory in READBYTE. unfold exec_correct in READBYTE. *)
    (*         specialize (READBYTE ms st VALID). *)
    (*         destruct READBYTE as [[ubmsg [UB LIFT]] | READBYTE]. *)
    (*         { (* Reading the byte gave UB *) *)
    (*           cbn in UB. *)
    (*           Transparent read_byte_MemPropT. *)
    (*           unfold read_byte_MemPropT in *. *)
    (*         } *)
    (*       } *)

    (*       { (* OOM *) *)
    (*         do 2 eexists. *)
    (*         exact ""%string. *)
    (*         intros RUN. *)

    (*         cbn in RUN. *)
    (*         repeat rewrite MemMonad_run_bind in RUN. *)
    (*         repeat rewrite MemMonad_run_ret in RUN. *)
    (*         repeat rewrite bind_ret_l in RUN. *)

    (*         rewrite map_monad_unfold in RUN. *)
    (*         repeat rewrite MemMonad_run_bind in RUN. *)

            
    (*       } *)

    (*       (* ---------------------------------------------------------------------- *) *)
    (*         (* Messing around... *) *)
    (*         (* IHlen with read_bytes (ptr+1) len *) *)
    (*         destruct len. *)
    (*         { (* Just one byte read *) *)
    (*           cbn in HMAPM. *)
    (*           inv HMAPM. *)
    (*           cbn in Heqs. *)
    (*           inv Heqs. *)
    (*           cbn in RUN. *)
    (*           repeat rewrite MemMonad_run_ret in RUN. *)
    (*           repeat rewrite bind_ret_l in RUN. *)

    (*           repeat eexists. *)
    (*           left. *)
    (*           eexists. *)
    (*           cbn. *)
    (*           right. *)
    (*           repeat eexists. *)

    (*           cbn. *)
    (*           rewrite MP.GEP.handle_gep_addr_0. *)
    (*           cbn. *)
    (*         } *)

    (*         cbn in HMAPM. *)
    (*         destruct (LP.IP.from_Z 1) eqn:HONE; inv HMAPM. *)

    (*         set (fstptr:= MP.GEP.handle_gep_addr (DTYPE_I 8) ptr [LP.Events.DV.DVALUE_IPTR i]). *)
    (*         destruct fstptr eqn:HFSTPTR. *)
    (*         admit. (* Will be contradiction when I can use this *) *)
    (*         pose proof (IHlen a) as REST. *)
            
    (*         repeat rewrite MemMonad_run_ret in RUN. *)
    (*         repeat rewrite bind_ret_l in RUN. *)

    (*         eapply MemMonad_eq1_raise_error_inv in RUN; contradiction. *)

    (*       } *)
    (*     } *)

    (*     (* I need to know whether UB happens or not based on if the read is allowed *) *)
    (*     right. *)
    (*     split; [|split]. *)

    (*     { (* Error *) *)
    (*       do 2 exists ""%string. *)

    (*       intros RUN. *)
    (*       exfalso. *)
    (*       rewrite LP.IP.from_Z_0 in RUN. *)

    (*       repeat rewrite MemMonad_run_bind in RUN. *)
    (*       repeat rewrite MemMonad_run_ret in RUN. *)
    (*       repeat rewrite bind_ret_l in RUN. *)
    (*       cbn in RUN. *)

    (*       repeat rewrite MemMonad_run_ret in RUN. *)
    (*       repeat rewrite bind_ret_l in RUN. *)
    (*       cbn in RUN. *)

    (*       repeat rewrite MemMonad_run_ret in RUN. *)
    (*       repeat rewrite bind_ret_l in RUN. *)

    (*       eapply MemMonad_eq1_raise_error_inv in RUN; contradiction. *)

    (*     } *)
    (*   } *)
    (*   intros ptr len. *)
    (*   unfold read_bytes. *)
    (*   unfold read_bytes_spec. *)
    (*   unfold get_consecutive_ptrs in *. *)


    (* Lemma read_bytes_correct : *)
    (*   forall ptr len, *)
    (*     exec_correct (read_bytes ptr len) (read_bytes_spec ptr len). *)
    (* Proof. *)
    (*   intros ptr len. *)
    (*   unfold read_bytes. *)
    (*   unfold read_bytes_spec. *)
    (*   unfold get_consecutive_ptrs in *. *)

    (*   cbn. *)

    (*   unfold exec_correct. *)
    (*   intros ms st VALID. *)

    (*   destruct (intptr_seq 0 len) eqn:HSEQ. *)
    (*   2: { (* OOM *) *)
    (*     cbn. *)
    (*     right. *)
    (*     split. *)
    (*     { (* Error *) *)
    (*       eexists. exists ""%string. *)
    (*       intros RUN. *)

    (*       repeat rewrite MemMonad_run_bind in RUN. *)
    (*       rewrite Monad.bind_bind in RUN. *)
    (*       rewrite MemMonad_run_raise_oom in RUN. *)
    (*       rewrite rbm_raise_bind in RUN; [| typeclasses eauto]. *)
    (*       exfalso. *)
    (*       admit. (* TODO: Need something about raise_oom not being raise_error... *) *)
    (*     } *)

    (*     split. *)
    (*     { (* OOM *) *)
    (*       exists s. exists ""%string. *)
    (*       intros RUN. *)

    (*       repeat rewrite MemMonad_run_bind in RUN. *)
    (*       rewrite Monad.bind_bind in RUN. *)
    (*       rewrite MemMonad_run_raise_oom in RUN. *)
    (*       rewrite rbm_raise_bind in RUN; [| typeclasses eauto]. *)

    (*       repeat eexists. *)
    (*       left. *)
    (*       eauto. *)
    (*     } *)

    (*     { (* Success *) *)
    (*       intros st' ms' x RUN. *)
    (*       repeat rewrite MemMonad_run_bind in RUN. *)
    (*       rewrite Monad.bind_bind in RUN. *)
    (*       rewrite MemMonad_run_raise_oom in RUN. *)
    (*       rewrite rbm_raise_bind in RUN; [| typeclasses eauto]. *)

    (*       symmetry in RUN. *)
    (*       eapply MemMonad_eq1_raise_oom_inv in RUN. *)
    (*       contradiction. *)
    (*     } *)
    (*   } *)

    (*   right. (* No UB *) *)

    (*   split; cbn. *)
    (*   { (* Error *) *)
    (*     do 2 exists (""%string). *)

    (*     intros RUN. *)
    (*     repeat rewrite MemMonad_run_bind in RUN. *)
    (*     repeat rewrite MemMonad_run_ret in RUN. *)
    (*     rewrite bind_ret_l in RUN. *)

    (*     match goal with *)
    (*     | RUN : context [Util.map_monad ?f ?s] |- _ => *)
    (*         destruct (Util.map_monad f s) as [ERR | ptrs] eqn:HMAPM *)
    (*     end. *)

    (*     { (* Error in map monad *) *)
    (*       cbn in RUN. *)
    (*       rewrite MemMonad_run_raise_error in RUN. *)
    (*       rewrite rbm_raise_bind in RUN; [| typeclasses eauto]. *)
    (*       repeat eexists. *)

    (*       left. *)
    (*       exists ""%string. *)
    (*       right. *)

    (*       repeat eexists. *)
    (*       rewrite HMAPM. *)
    (*       cbn. *)
    (*       auto. *)
    (*     } *)

    (*     { (* Success in HMAPM *) *)
    (*       cbn in RUN. *)
    (*       rewrite MemMonad_run_ret in RUN. *)
    (*       rewrite bind_ret_l in RUN. *)

    (*       induction ptrs. *)
    (*       - cbn in *. *)
    (*         rewrite MemMonad_run_ret in RUN. *)
    (*         eapply MemMonad_eq1_raise_error_inv in RUN. *)
    (*         contradiction. *)
    (*       - cbn in *. *)
    (*         rewrite MemMonad_run_bind in RUN. *)

    (*         (* read_byte_correct *) *)
          
          
    (*       destruct (map_monad (fun ptr : LP.ADDR.addr => read_byte ptr) ptrs) as [ERR | bytes] eqn:HREADS. *)
    (*     } *)
    (*   } *)
    (* Qed. *)

    End Correctness.
End MemoryModelTheory.
