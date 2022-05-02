From Vellvm.Syntax Require Import
     DataLayout
     DynamicTypes.

From Vellvm.Semantics Require Import
     MemoryAddress
     MemoryParams
     LLVMParams
     LLVMEvents
     Lang
     Memory.FiniteProvenance
     Memory.Sizeof
     Memory.MemBytes
     Memory.ErrSID
     GepM
     VellvmIntegers.

From Vellvm Require Import
     Numeric.Coqlib
     Numeric.Integers.

From Vellvm.Handlers Require Import
     MemPropT.

From Vellvm.Utils Require Import
     Error
     PropT
     Tactics
     IntMaps
     MonadEq1Laws
     MonadExcLaws
     MapMonadExtra
     Raise.

From ITree Require Import
     ITree
     Eq.Eq.

From ExtLib Require Import
     Structures.Monads
     Structures.Functor
     Data.Monads.StateMonad.

From Coq Require Import
     ZArith
     Strings.String
     List
     Lia
     Relations
     RelationClasses.

Import ListNotations.
Import ListUtil.
Import Utils.Monads.

Import MonadNotation.
Open Scope monad_scope.

From Vellvm.Handlers Require Import
     MemoryModel
     MemoryInterpreters.

Require Import Morphisms.

#[local] Open Scope Z_scope.

(** * Memory Model

    This file implements VIR's memory model as an handler for the [MemoryE] family of events.
    The model is inspired by CompCert's memory model, but differs in that it maintains two
    representation of the memory, a logical one and a low-level one.
    Pointers (type signature [MemoryAddress.ADDRESS]) are implemented as a pair containing
    an address and an offset.
*)

(* Specifying the currently supported dynamic types.
       This is mostly to rule out:

       - arbitrary bitwidth integers
       - half
       - x86_fp80
       - fp128
       - ppc_fp128
       - metadata
       - x86_mmx
       - opaque
 *)
Inductive is_supported : dtyp -> Prop :=
| is_supported_DTYPE_I1 : is_supported (DTYPE_I 1)
| is_supported_DTYPE_I8 : is_supported (DTYPE_I 8)
| is_supported_DTYPE_I32 : is_supported (DTYPE_I 32)
| is_supported_DTYPE_I64 : is_supported (DTYPE_I 64)
| is_supported_DTYPE_Pointer : is_supported (DTYPE_Pointer)
| is_supported_DTYPE_Void : is_supported (DTYPE_Void)
| is_supported_DTYPE_Float : is_supported (DTYPE_Float)
| is_supported_DTYPE_Double : is_supported (DTYPE_Double)
| is_supported_DTYPE_Array : forall sz τ, is_supported τ -> is_supported (DTYPE_Array sz τ)
| is_supported_DTYPE_Struct : forall fields, Forall is_supported fields -> is_supported (DTYPE_Struct fields)
| is_supported_DTYPE_Packed_struct : forall fields, Forall is_supported fields -> is_supported (DTYPE_Packed_struct fields)
(* TODO: unclear if is_supported τ is good enough here. Might need to make sure it's a sized type *)
| is_supported_DTYPE_Vector : forall sz τ, is_supported τ -> vector_dtyp τ -> is_supported (DTYPE_Vector sz τ)
.


(** ** Type of pointers
    Implementation of the notion of pointer used: an address and an offset.
 *)
Definition Iptr := Z. (* Integer pointer type (physical addresses) *)

(* TODO: Should probably make this an NSet, but it gives universe inconsistency with Module addr *)
Definition Prov := option (list Provenance). (* Provenance *)

Definition wildcard_prov : Prov := None.
Definition nil_prov : Prov := Some [].

(* TODO: If Prov is an NSet, I get a universe inconsistency here... *)
Module Addr : MemoryAddress.ADDRESS with Definition addr := (Iptr * Prov) % type.
  Definition addr := (Iptr * Prov) % type.
  Definition null : addr := (0, nil_prov)%Z.

  (* TODO: is this what we should be using for equality on pointers? Probably *NOT* because of provenance. *)
  Lemma eq_dec : forall (a b : addr), {a = b} + {a <> b}.
  Proof.
    intros [a1 a2] [b1 b2].

    destruct (Z.eq_dec a1 b1);
      destruct (option_eq (fun x y => list_eq_dec N.eq_dec x y) a2 b2); subst.
    - left; reflexivity.
    - right. intros H. inversion H; subst. apply n. reflexivity.
    - right. intros H. inversion H; subst. apply n. reflexivity.
    - right. intros H. inversion H; subst. apply n. reflexivity.
  Qed.

  Lemma different_addrs :
    forall (a : addr), exists (b : addr), a <> b.
  Proof.
    intros a.
    destruct a.
    destruct i.
    - exists (Z.pos 1, p).
      intros CONTRA; inversion CONTRA.
    - exists (0, p).
      intros CONTRA; inversion CONTRA.
    - exists (Z.pos 1, p).
      intros CONTRA; inversion CONTRA.
  Qed.

  Definition show_addr (a : addr) := Show.show a.
End Addr.

Module BigIP : MemoryAddress.INTPTR with
Definition intptr := Z with
Definition from_Z := (fun (x : Z) => ret x : OOM Z).
  Definition intptr := Z.
  Definition zero := 0%Z.

  Definition eq_dec := Z.eq_dec.
  Definition eqb := Z.eqb.

  Definition to_Z (x : intptr) := x.

  (* TODO: negatives.... ???? *)
  Definition to_unsigned := to_Z.
  Definition from_Z (x : Z) : OOM intptr := ret x.

  Lemma from_Z_to_Z :
    forall (z : Z) (i : intptr),
      from_Z z = NoOom i ->
      to_Z i = z.
  Proof.
    intros z i FROM.
    inversion FROM; auto.
  Qed.

  Lemma from_Z_0 :
    from_Z 0 = NoOom zero.
  Proof.
    auto.
  Qed.

  Lemma to_Z_0 :
    to_Z zero = 0.
  Proof.
    auto.
  Qed.

  Definition mequ_Z (x y : Z) : bool :=
    Z.eqb x y.

  Definition mcmp_Z (c : comparison) (x y : Z) : bool :=
    match c with
    | Ceq => Z.eqb x y
    | Cne => Zneq_bool x y
    | Clt => Z.ltb x y
    | Cle => Z.leb x y
    | Cgt => Z.gtb x y
    | Cge => Z.geb x y
    end.

  Definition mcmpu_Z (c : comparison) (x y : Z) : bool :=
    match c with
    | Ceq => Z.eqb x y
    | Cne => Zneq_bool x y
    | Clt => Z.ltb x y
    | Cle => Z.leb x y
    | Cgt => Z.gtb x y
    | Cge => Z.geb x y
    end.

  Instance VMemInt_intptr : VMemInt intptr
    :=
    { mequ  := mequ_Z;
      mcmp  := mcmp_Z;
      mcmpu := mcmpu_Z;

      mbitwidth := None;
      mzero     := 0%Z;
      mone      := 1%Z;

      madd := fun x y => ret (Z.add x y);
      (* No overflows *)
      madd_carry := fun x y c => 0%Z;
      madd_overflow := fun x y c => 0%Z;

      msub := fun x y => ret (Z.sub x y);
      (* No overflows *)
      msub_borrow := fun x y c => 0%Z;
      msub_overflow := fun x y c => 0%Z;

      mmul := fun x y => ret (Z.mul x y);

      mdivu := fun x y => Z.div x y;
      mdivs := fun x y => ret (Z.div x y);

      mmodu := fun x y => Z.modulo x y;
      mmods := fun x y => ret (Z.modulo x y);

      mshl := fun x y => ret (Z.shiftl x y);
      mshr := fun x y => Z.shiftr x y;
      mshru := fun x y => Z.shiftr x y;

      mnegative := fun x => ret (0 - x)%Z;

      mand := Z.land;
      mor := Z.lor;
      mxor := Z.lxor;

      mmin_signed := None;
      mmax_signed := None;

      munsigned := fun x => x;
      msigned := fun x => x;

      mrepr := fun x => ret x;

      mdtyp_of_int := DTYPE_IPTR
    }.

  Lemma VMemInt_intptr_dtyp :
    @mdtyp_of_int intptr VMemInt_intptr = DTYPE_IPTR.
  Proof.
    cbn. reflexivity.
  Qed.

End BigIP.

Module BigIP_BIG : MemoryAddress.INTPTR_BIG BigIP.
  Import BigIP.

  Lemma from_Z_safe :
    forall z,
      match from_Z z with
      | NoOom _ => True
      | Oom _ => False
      end.
  Proof.
    intros z.
    unfold from_Z.
    reflexivity.
  Qed.
End BigIP_BIG.

Module IP64Bit : MemoryAddress.INTPTR.
  Definition intptr := int64.
  Definition zero := Int64.zero.

  Definition eq_dec := Int64.eq_dec.
  Definition eqb := Int64.eq.

  Definition to_Z (x : intptr) := Int64.signed x.

  (* TODO: negatives.... ???? *)
  Definition to_unsigned := to_Z.
  Definition from_Z (x : Z) : OOM intptr :=
    if (x <=? Int64.max_signed)%Z && (x >=? Int64.min_signed)%Z
    then ret (Int64.repr x)
    else Oom "IP64Bit from_Z oom.".

  Lemma from_Z_to_Z :
    forall (z : Z) (i : intptr),
      from_Z z = NoOom i ->
      to_Z i = z.
  Proof.
    intros z i FROM.
    unfold from_Z in FROM.
    break_match_hyp; inversion FROM.
    unfold to_Z.
    apply Integers.Int64.signed_repr.
    lia.
  Qed.

  Lemma from_Z_0 :
    from_Z 0 = NoOom zero.
  Proof.
    auto.
  Qed.

  Lemma to_Z_0 :
    to_Z zero = 0.
  Proof.
    auto.
  Qed.

  Instance VMemInt_intptr : VMemInt intptr
    :=
    { (* Comparisons *)
      mequ := Int64.eq;
      mcmp := Int64.cmp;
      mcmpu := Int64.cmpu;

      (* Constants *)
      mbitwidth := Some 64%nat;
      mzero := Int64.zero;
      mone := Int64.one;

      (* Arithmetic *)
      madd := fun x y =>
               if (Int64.eq (Int64.add_overflow x y Int64.zero) Int64.one)
               then Oom "IP64Bit addition overflow."
               else ret (Int64.add x y);
      madd_carry := Int64.add_carry;
      madd_overflow := Int64.add_overflow;

      msub := fun x y =>
               if (Int64.eq (Int64.sub_overflow x y Int64.zero) Int64.one)
               then Oom "IP64Bit addition overflow."
               else ret (Int64.sub x y);
      msub_borrow := Int64.sub_borrow;
      msub_overflow := Int64.sub_overflow;

      mmul :=
      fun x y =>
        let res_s' := ((Int64.signed x) * (Int64.signed y))%Z in

        let min_s_bound := Int64.min_signed >? res_s' in
        let max_s_bound := res_s' >? Int64.max_signed in

        if (orb min_s_bound max_s_bound)
        then Oom "IP64Bit multiplication overflow."
        else NoOom (Int64.mul x y);

      mdivu := Int64.divu;
      mdivs :=
      fun x y =>
        if (Int64.signed x =? Int64.max_signed) && (Int64.signed y =? (-1)%Z)
        then Oom "IP64Bit signed division overflow."
        else ret (Int64.divs x y);

      mmodu := Int64.modu;
      mmods :=
      (* TODO: is this overflow check needed? *)
      fun x y =>
        if (Int64.signed x =? Int64.max_signed) && (Int64.signed y =? (-1)%Z)
        then Oom "IP64Bit signed modulo overflow."
        else ret (Int64.mods x y);

      mshl :=
      fun x y =>
        let res := Int64.shl x y in
        if Int64.signed res =? Int64.min_signed
        then Oom "IP64Bit left shift overflow (res is min signed, should not happen)."
        else
          let nres := Int64.negative res in
          if (negb (Z.shiftr (Int64.unsigned x)
                             (64%Z - Int64.unsigned y)
                    =? (Int64.unsigned nres)
                       * (Z.pow 2 (Int64.unsigned y) - 1))%Z)
          then Oom "IP64Bit left shift overflow."
          else ret res;
      mshr := Int64.shr;
      mshru := Int64.shru;

      mnegative :=
      fun x =>
        if (Int64.signed x =? Int64.min_signed)
        then Oom "IP64Bit taking negative of smallest number."
        else ret (Int64.negative x);

      (* Logic *)
      mand := Int64.and;
      mor := Int64.or;
      mxor := Int64.xor;

      (* Bounds *)
      mmin_signed := ret Int64.min_signed;
      mmax_signed := ret Int64.max_signed;

      (* Conversion *)
      munsigned := Int64.unsigned;
      msigned := Int64.signed;

      mrepr := from_Z;

      mdtyp_of_int := DTYPE_IPTR
    }.

  Lemma VMemInt_intptr_dtyp :
    @mdtyp_of_int intptr VMemInt_intptr = DTYPE_IPTR.
  Proof.
    cbn. reflexivity.
  Qed.

End IP64Bit.


Module FinPTOI : PTOI(Addr)
with Definition ptr_to_int := fun (ptr : Addr.addr) => fst ptr.
  Definition ptr_to_int (ptr : Addr.addr) := fst ptr.
End FinPTOI.

Module FinPROV : PROVENANCE(Addr)
with Definition Prov := Prov
with Definition address_provenance
    := fun (a : Addr.addr) => snd a.
  Definition Provenance := Provenance.
  Definition AllocationId := AllocationId.
  Definition Prov := Prov.
  Definition wildcard_prov : Prov := wildcard_prov.
  Definition nil_prov : Prov := nil_prov.
  Definition address_provenance (a : Addr.addr) : Prov
    := snd a.

  (* Does the provenance set pr allow for access to aid? *)
  Definition access_allowed (pr : Prov) (aid : AllocationId) : bool
    := match pr with
       | None => true (* Wildcard can access anything. *)
       | Some prset =>
         match aid with
         | None => true (* Wildcard, can be accessed by anything. *)
         | Some aid =>
           existsb (N.eqb aid) prset
         end
       end.

  Definition aid_access_allowed (pr : AllocationId) (aid : AllocationId) : bool
    := match pr with
       | None => true
       | Some pr =>
         match aid with
         | None => true
         | Some aid =>
           N.eqb pr aid
         end
       end.

  Definition allocation_id_to_prov (aid : AllocationId) : Prov
    := fmap (fun x => [x]) aid.

  Definition provenance_to_allocation_id (pr : Provenance) : AllocationId
    := Some pr.

  Definition next_provenance (pr : Provenance) : Provenance
    := N.succ pr.

  Definition initial_provenance : Provenance
    := 0%N.

  Definition provenance_lt (p1 p2 : Provenance) : Prop
    := N.lt p1 p2.

  Lemma aid_access_allowed_refl :
    forall aid, aid_access_allowed aid aid = true.
  Proof.
    intros aid.
    unfold aid_access_allowed.
    destruct aid; auto.
    rewrite N.eqb_refl.
    auto.
  Qed.

  Lemma access_allowed_refl :
    forall aid,
      access_allowed (allocation_id_to_prov aid) aid = true.
  Proof.
    intros aid.
    unfold access_allowed.
    cbn.
    destruct aid; auto.
    cbn.
    rewrite N.eqb_refl.
    cbn.
    auto.
  Qed.

  Lemma provenance_eq_dec :
    forall (pr pr' : Provenance),
      {pr = pr'} + {pr <> pr'}.
  Proof.
    unfold Provenance.
    unfold FiniteProvenance.Provenance.
    intros pr pr'.
    apply N.eq_dec.
  Defined.

  Lemma provenance_eq_dec_refl :
    forall (pr : Provenance),
      true = provenance_eq_dec pr pr.
  Proof.
    intros pr.
    destruct provenance_eq_dec; cbn; auto.
    exfalso; auto.
  Qed.

  Lemma aid_eq_dec :
    forall (aid aid' : AllocationId),
      {aid = aid'} + {aid <> aid'}.
  Proof.
    intros aid aid'.
    destruct aid, aid'; auto.
    pose proof provenance_eq_dec p p0.
    destruct H; subst; auto.
    right.
    intros CONTRA. inv CONTRA; contradiction.
    right; intros CONTRA; inv CONTRA.
    right; intros CONTRA; inv CONTRA.
  Qed.

  Lemma aid_eq_dec_refl :
    forall (aid : AllocationId),
      true = aid_eq_dec aid aid.
  Proof.
    intros aid.
    destruct (aid_eq_dec aid aid); cbn; auto.
    exfalso; auto.
  Qed.

  #[global] Instance provenance_lt_trans : Transitive provenance_lt.
  Proof.
    unfold Transitive.
    intros x y z XY YZ.
    unfold provenance_lt in *.
    lia.
  Defined.

  Lemma provenance_lt_next_provenance :
    forall pr,
      provenance_lt pr (next_provenance pr).
  Proof.
    unfold provenance_lt, next_provenance.
    lia.
  Qed.

  Lemma provenance_lt_nrefl :
    forall pr,
      ~ provenance_lt pr pr.
  Proof.
    intros pr.
    unfold provenance_lt.
    lia.
  Qed.

  #[global] Instance provenance_lt_antisym : Antisymmetric Provenance eq provenance_lt.
  Proof.
    unfold Antisymmetric.
    intros x y XY YX.
    unfold provenance_lt in *.
    lia.
  Defined.

  Lemma next_provenance_neq :
    forall pr,
      pr <> next_provenance pr.
  Proof.
    intros pr.
    unfold next_provenance.
    lia.
  Qed.

  (* Debug *)
  Definition show_prov (pr : Prov) := Show.show pr.
  Definition show_provenance (pr : Provenance) := Show.show pr.
  Definition show_allocation_id (aid : AllocationId) := Show.show aid.
End FinPROV.

Module FinITOP : ITOP(Addr)(FinPROV)(FinPTOI).
  Import Addr.
  Import FinPROV.
  Import FinPTOI.

  Definition int_to_ptr (i : Z) (pr : Prov) : addr
    := (i, pr).

  Lemma int_to_ptr_provenance :
    forall (x : Z) (p : Prov) ,
      FinPROV.address_provenance (int_to_ptr x p) = p.
  Proof.
    intros x p.
    reflexivity.
  Qed.

  Lemma int_to_ptr_ptr_to_int :
    forall (a : addr) (p : Prov),
      address_provenance a = p ->
      int_to_ptr (ptr_to_int a) p = a.
  Proof.
    intros a p PROV.
    unfold int_to_ptr.
    unfold ptr_to_int.
    destruct a; cbn.
    inv PROV; cbn; auto.
  Qed.

  Lemma ptr_to_int_int_to_ptr :
    forall (x : Z) (p : Prov),
      ptr_to_int (int_to_ptr x p) = x.
  Proof.
    intros x p.
    reflexivity.
  Qed.
End FinITOP.

Module FinSizeof : Sizeof.
  (* TODO: make parameter? *)
  Definition ptr_size : nat := 8.

  Fixpoint sizeof_dtyp (ty:dtyp) : N :=
    match ty with
    | DTYPE_I 1          => 1 (* TODO: i1 sizes... *)
    | DTYPE_I 8          => 1
    | DTYPE_I 32         => 4
    | DTYPE_I 64         => 8
    | DTYPE_I _          => 0 (* Unsupported integers *)
    | DTYPE_IPTR         => N.of_nat ptr_size
    | DTYPE_Pointer      => N.of_nat ptr_size
    | DTYPE_Packed_struct l
    | DTYPE_Struct l     => fold_left (fun acc x => (acc + sizeof_dtyp x)%N) l 0%N
    | DTYPE_Vector sz ty'
    | DTYPE_Array sz ty' => sz * sizeof_dtyp ty'
    | DTYPE_Float        => 4
    | DTYPE_Double       => 8
    | DTYPE_Half         => 4
    | DTYPE_X86_fp80     => 10 (* TODO: Unsupported, currently modeled by Float32 *)
    | DTYPE_Fp128        => 16 (* TODO: Unsupported, currently modeled by Float32 *)
    | DTYPE_Ppc_fp128    => 16 (* TODO: Unsupported, currently modeled by Float32 *)
    | DTYPE_Metadata     => 0
    | DTYPE_X86_mmx      => 8 (* TODO: Unsupported *)
    | DTYPE_Opaque       => 0 (* TODO: Unsupported *)
    | _                  => 0 (* TODO: add support for more types as necessary *)
    end.

  Lemma sizeof_dtyp_void :
    sizeof_dtyp DTYPE_Void = 0%N.
  Proof. reflexivity. Qed.

  Lemma sizeof_dtyp_pos :
    forall dt,
      (0 <= sizeof_dtyp dt)%N.
  Proof.
    intros dt.
    lia.
  Qed.

  Lemma sizeof_dtyp_packed_struct_0 :
    sizeof_dtyp (DTYPE_Packed_struct nil) = 0%N.
  Proof.
    reflexivity.
  Qed.

  Lemma sizeof_dtyp_packed_struct_cons :
    forall dt dts,
      sizeof_dtyp (DTYPE_Packed_struct (dt :: dts)) = (sizeof_dtyp dt + sizeof_dtyp (DTYPE_Packed_struct dts))%N.
  Proof.
    intros dt dts.
    cbn.
    rewrite fold_sum_acc.
    reflexivity.
  Qed.

  Lemma sizeof_dtyp_struct_0 :
    sizeof_dtyp (DTYPE_Struct nil) = 0%N.
  Proof.
    reflexivity.
  Qed.

  (* TODO: this should take padding into account *)
  Lemma sizeof_dtyp_struct_cons :
    forall dt dts,
      sizeof_dtyp (DTYPE_Struct (dt :: dts)) = (sizeof_dtyp dt + sizeof_dtyp (DTYPE_Struct dts))%N.
  Proof.
    intros dt dts.
    cbn.
    rewrite fold_sum_acc.
    reflexivity.
  Qed.

  Lemma sizeof_dtyp_array :
    forall sz t,
      sizeof_dtyp (DTYPE_Array sz t) = (sz * sizeof_dtyp t)%N.
  Proof.
    reflexivity.
  Qed.

  Lemma sizeof_dtyp_vector :
    forall sz t,
      sizeof_dtyp (DTYPE_Vector sz t) = (sz * sizeof_dtyp t)%N.
  Proof.
    reflexivity.
  Qed.

  Lemma sizeof_dtyp_i8 :
    sizeof_dtyp (DTYPE_I 8) = 1%N.
  Proof.
    reflexivity.
  Qed.
End FinSizeof.

Module FinByte (ADDR : MemoryAddress.ADDRESS) (IP : MemoryAddress.INTPTR) (SIZEOF : Sizeof) (LLVMEvents:LLVM_INTERACTIONS(ADDR)(IP)(SIZEOF)) : ByteImpl(ADDR)(IP)(SIZEOF)(LLVMEvents).
  Import LLVMEvents.
  Import DV.

  Inductive UByte :=
  | mkUByte (uv : uvalue) (dt : dtyp) (idx : uvalue) (sid : store_id) : UByte.

  Definition SByte := UByte.

  Definition uvalue_sbyte := mkUByte.

  Definition sbyte_to_extractbyte (byte : SByte) : uvalue
    := match byte with
       | mkUByte uv dt idx sid => UVALUE_ExtractByte uv dt idx sid
       end.

  Lemma sbyte_to_extractbyte_inv :
    forall (b : SByte),
    exists uv dt idx sid,
      sbyte_to_extractbyte b = UVALUE_ExtractByte uv dt idx sid.
  Proof.
    intros b. destruct b.
    cbn; eauto.
  Qed.

  Lemma sbyte_to_extractbyte_of_uvalue_sbyte :
    forall uv dt idx sid,
      sbyte_to_extractbyte (uvalue_sbyte uv dt idx sid) =  UVALUE_ExtractByte uv dt idx sid.
  Proof.
    auto.
  Qed.

End FinByte.


Module FiniteMemoryModelSpecPrimitives (LP : LLVMParams) (MP : MemoryParams LP) <: MemoryModelSpecPrimitives LP MP.
  Import LP.
  Import LP.Events.
  Import LP.ADDR.
  Import LP.SIZEOF.
  Import LP.PROV.
  Import PTOI.
  Import ITOP.
  Import MP.
  Import GEP.

  Import MemBytes.
  Module MemByte := Byte LP.ADDR LP.IP LP.SIZEOF LP.Events MP.BYTE_IMPL.
  Import MemByte.
  Import LP.SIZEOF.


  Section Datatype_Definition.

    (* Memory consists of bytes which have a provenance associated with them. *)
    Definition mem_byte := (SByte * AllocationId)%type.

    (** ** Memory
        Memory is just a map of blocks.
     *)
    Definition memory := IntMap mem_byte.

    (** ** Stack frames
      A frame contains the list of block ids that need to be freed when popped,
      i.e. when the function returns.
      A [frame_stack] is a list of such frames.
     *)
    Definition Frame := list Iptr.
    Inductive FrameStack' : Type :=
    | Singleton (f : Frame)
    | Snoc (s : FrameStack') (f : Frame).

    (* The kernel does not recognize yet that a parameter can be
       instantiated by an inductive type. Hint: you can rename the
       inductive type and give a definition to map the old name to the new
       name. *)
    Definition FrameStack := FrameStack'.

    (** ** Memory stack
      The full notion of state manipulated by the monad is a pair of a [memory] and a [mem_stack].
     *)
    Definition memory_stack : Type := memory * FrameStack.

    (** Some operations on memory *)
    Definition set_byte_raw (mem : memory) (phys_addr : Z) (byte : mem_byte) : memory :=
      IM.add phys_addr byte mem.

    Definition read_byte_raw (mem : memory) (phys_addr : Z) : option mem_byte :=
      IM.find phys_addr mem.

    Lemma set_byte_raw_eq :
      forall (mem : memory) (byte : mem_byte) (x y : Z),
        x = y ->
        read_byte_raw (set_byte_raw mem x byte) y = Some byte.
    Proof.
      intros mem byte x y XY.
      apply IP.F.add_eq_o; auto.
    Qed.

    Lemma set_byte_raw_neq :
      forall (mem : memory) (byte : mem_byte) (x y : Z),
        x <> y ->
        read_byte_raw (set_byte_raw mem x byte) y = read_byte_raw mem y.
    Proof.
      intros mem byte x y XY.
      apply IP.F.add_neq_o; auto.
    Qed.

    Lemma read_byte_raw_add_all_index_out :
      forall (mem : memory) l z p,
        p < z \/ p >= z + Zlength l ->
        read_byte_raw (add_all_index l z mem) p = read_byte_raw mem p.
    Proof.
      intros mem l z p BOUNDS.
      unfold read_byte_raw.
      eapply lookup_add_all_index_out; eauto.
    Qed.

    Lemma read_byte_raw_add_all_index_in :
      forall (mem : memory) l z p v,
        z <= p <= z + Zlength l - 1 ->
        list_nth_z l (p - z) = Some v ->
        read_byte_raw (add_all_index l z mem) p = Some v.
    Proof.
      intros mem l z p v BOUNDS IN.
      unfold read_byte_raw.
      eapply lookup_add_all_index_in; eauto.
    Qed.

    Lemma read_byte_raw_add_all_index_in_exists :
      forall (mem : memory) l z p,
        z <= p <= z + Zlength l - 1 ->
        exists v, list_nth_z l (p - z) = Some v /\
               read_byte_raw (add_all_index l z mem) p = Some v.
    Proof.
      intros mem l z p IN.
      pose proof range_list_nth_z l (p - z) as H.
      forward H.
      lia.
      destruct H as [v NTH].
      exists v.

      split; auto.
      unfold read_byte_raw.
      eapply lookup_add_all_index_in; eauto.
    Qed.

  End Datatype_Definition.

  (* Convenient to make these opaque so they don't get unfolded *)
  #[global] Opaque set_byte_raw.
  #[global] Opaque read_byte_raw.


  Record MemState' :=
    mkMemState
      { ms_memory_stack : memory_stack;
        (* Used to keep track of allocation ids in use *)
        ms_provenance : Provenance;
      }.

  (* The kernel does not recognize yet that a parameter can be
  instantiated by an inductive type. Hint: you can rename the
  inductive type and give a definition to map the old name to the new
  name.
  *)
  Definition MemState := MemState'.

  Definition mem_state_memory_stack (ms : MemState) : memory_stack
    := ms.(ms_memory_stack).

  Definition mem_state_memory (ms : MemState) : memory
    := fst ms.(ms_memory_stack).

  Definition mem_state_provenance (ms : MemState) : Provenance
    := ms.(ms_provenance).

  Definition mem_state_frame_stack (ms : MemState) : FrameStack
    := snd ms.(ms_memory_stack).

  Definition read_byte_MemPropT (ptr : addr) : MemPropT MemState SByte :=
    let addr := ptr_to_int ptr in
    let pr := address_provenance ptr in
    ms <- get_mem_state;;
    let mem := mem_state_memory ms in
    match read_byte_raw mem addr with
    | None => raise_ub "Reading from unallocated memory."
    | Some byte =>
        let aid := snd byte in
        if access_allowed pr aid
        then ret (fst byte)
        else
          raise_ub
            ("Read from memory with invalid provenance -- addr: " ++ Show.show addr ++ ", addr prov: " ++ show_prov pr ++ ", memory allocation id: " ++ Show.show (show_allocation_id aid) ++ " memory: " ++ Show.show (map (fun '(key, (_, aid)) => (key, show_allocation_id aid)) (IM.elements mem)))
    end.

  Definition addr_allocated_prop (ptr : addr) (aid : AllocationId) : MemPropT MemState bool :=
    ms <- get_mem_state;;
    match read_byte_raw (mem_state_memory ms) (ptr_to_int ptr) with
    | None => ret false
    | Some (byte, aid') =>
        ret (proj_sumbool (aid_eq_dec aid aid'))
    end.

  Definition ptr_in_frame_prop (f : Frame) (ptr : addr) : Prop :=
    In (ptr_to_int ptr) f.

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

  Fixpoint FSIn (f : Frame) (fs : FrameStack) : Prop :=
    match fs with
    | Singleton f' => f' = f
    | Snoc fs f' => f' = f \/ FSIn f fs
    end.

  Fixpoint FSIn_eqv (f : Frame) (fs : FrameStack) : Prop :=
    match fs with
    | Singleton f' => frame_eqv f' f
    | Snoc fs f' => frame_eqv f' f \/ FSIn_eqv f fs
    end.

  Fixpoint FSNth_rel (R : relation Frame) (fs : FrameStack) (n : nat) (f : Frame) : Prop :=
    match n with
    | 0%nat =>
        match fs with
        | Singleton f' => R f' f
        | Snoc fs f' => R f' f
        end
    | S n =>
        match fs with
        | Singleton f' => False
        | Snoc fs f' => FSNth_rel R fs n f
        end
    end.

  Definition FSNth_eqv := FSNth_rel frame_eqv.

  Definition frame_stack_eqv (fs fs' : FrameStack) : Prop :=
    forall f n, FSNth_eqv fs n f <-> FSNth_eqv fs' n f.

  #[global] Instance frame_stack_eqv_Equivalence : Equivalence frame_stack_eqv.
  Proof.
    split; try firstorder.
    - intros x y z XY YZ.
      unfold frame_stack_eqv in *.
      intros f n.
      split; intros NTH.
      + apply YZ; apply XY; auto.
      + apply XY; apply YZ; auto.
  Qed.

  (* Check for the current frame *)
  Definition peek_frame_stack_prop (fs : FrameStack) (f : Frame) : Prop :=
    match fs with
    | Singleton f' => frame_eqv f f'
    | Snoc s f' => frame_eqv f f'
    end.

  Definition pop_frame_stack_prop (fs fs' : FrameStack) : Prop :=
    match fs with
    | Singleton f => False
    | Snoc s f => frame_stack_eqv s fs'
    end.

  Definition mem_state_frame_stack_prop (ms : MemState) (fs : FrameStack) : Prop :=
    frame_stack_eqv (snd (ms_memory_stack ms)) fs.

  (** Provenance / store ids *)
  Definition used_provenance_prop (ms : MemState) (pr : Provenance) : Prop :=
    provenance_lt pr (next_provenance (mem_state_provenance ms)).

  Definition get_fresh_provenance (ms : MemState) : Provenance :=
    let pr := mem_state_provenance ms in
    next_provenance pr.

  Lemma get_fresh_provenance_fresh :
    forall (ms : MemState),
      ~ used_provenance_prop ms (get_fresh_provenance ms).
  Proof.
    intros ms.
    unfold used_provenance_prop.
    destruct ms.
    cbn.
    unfold get_fresh_provenance.
    cbn.
    apply provenance_lt_nrefl.
  Qed.

  Definition mem_state_fresh_provenance (ms : MemState) : (Provenance * MemState)%type :=
    match ms with
    | mkMemState mem_stack pr =>
        let pr' := next_provenance pr in
        (pr', mkMemState mem_stack pr')
    end.

  Definition used_store_id_prop (ms : MemState) (sid : store_id) : Prop :=
    exists ptr byte aid,
      let mem := mem_state_memory ms in
      read_byte_raw mem ptr = Some (byte, aid) /\
        sbyte_sid byte = inr sid.

  Lemma mem_state_fresh_provenance_fresh :
    forall (ms ms' : MemState) (pr : Provenance),
      mem_state_fresh_provenance ms = (pr, ms') ->
      ~ used_provenance_prop ms pr /\ used_provenance_prop ms' pr.
  Proof.
    intros ms ms' pr MSFP.
    unfold mem_state_fresh_provenance in *.
    destruct ms; cbn in *; inv MSFP.
    split.
    - intros CONTRA;
      unfold used_provenance_prop in *.
      cbn in CONTRA.
      eapply provenance_lt_nrefl; eauto.
    - unfold used_provenance_prop in *.
      cbn.
      apply provenance_lt_next_provenance.
  Qed.

  (** Extra frame stack lemmas *)
  Lemma frame_stack_eqv_snoc_sing_inv :
    forall fs f1 f2,
      frame_stack_eqv (Snoc fs f1) (Singleton f2) -> False.
  Proof.
    intros fs f1 f2 EQV.
    destruct fs.
    - unfold frame_stack_eqv in *.
      specialize (EQV f 1%nat).
      destruct EQV as [NTH1 NTH2].
      cbn in *.
      apply NTH1.
      reflexivity.
    - unfold frame_stack_eqv in *.
      specialize (EQV f 1%nat).
      destruct EQV as [NTH1 NTH2].
      cbn in *.
      apply NTH1.
      reflexivity.
  Qed.

  Lemma frame_stack_eqv_sing_snoc_inv :
    forall fs f1 f2,
      frame_stack_eqv (Singleton f2) (Snoc fs f1) -> False.
  Proof.
    intros fs f1 f2 EQV.
    destruct fs.
    - unfold frame_stack_eqv in *.
      specialize (EQV f 1%nat).
      destruct EQV as [NTH1 NTH2].
      cbn in *.
      apply NTH2.
      reflexivity.
    - unfold frame_stack_eqv in *.
      specialize (EQV f 1%nat).
      destruct EQV as [NTH1 NTH2].
      cbn in *.
      apply NTH2.
      reflexivity.
  Qed.

  Lemma FSNTH_rel_snoc :
    forall R fs f n x,
      FSNth_rel R (Snoc fs f) (S n) x =
        FSNth_rel R fs n x.
  Proof.
    intros R fs f n x.
    cbn. reflexivity.
  Qed.

  Lemma frame_stack_snoc_inv_fs :
    forall fs1 fs2 f1 f2,
      frame_stack_eqv (Snoc fs1 f1) (Snoc fs2 f2) ->
      frame_stack_eqv fs1 fs2.
  Proof.
    intros fs1 fs2 f1 f2 EQV.
    unfold frame_stack_eqv in *.
    intros f n.
    specialize (EQV f (S n)).
    setoid_rewrite FSNTH_rel_snoc in EQV.
    apply EQV.
  Qed.

  Lemma frame_stack_snoc_inv_f :
    forall fs1 fs2 f1 f2,
      frame_stack_eqv (Snoc fs1 f1) (Snoc fs2 f2) ->
      frame_eqv f1 f2.
  Proof.
    intros fs1 fs2 f1 f2 EQV.
    unfold frame_stack_eqv in *.
    specialize (EQV f2 0%nat).
    cbn in *.
    apply EQV.
    reflexivity.
  Qed.

  Lemma frame_stack_inv :
    forall fs1 fs2,
      frame_stack_eqv fs1 fs2 ->
      (exists fs1' fs2' f1 f2,
          fs1 = (Snoc fs1' f1) /\ fs2 = (Snoc fs2' f2) /\
            frame_stack_eqv fs1' fs2' /\
            frame_eqv f1 f2) \/
        (exists f1 f2,
            fs1 = Singleton f1 /\ fs2 = Singleton f2 /\
              frame_eqv f1 f2).
  Proof.
    intros fs1 fs2 EQV.
    destruct fs1, fs2.
    - right.
      do 2 eexists.
      split; eauto.
      split; eauto.
      specialize (EQV f 0%nat).
      cbn in EQV.
      symmetry.
      apply EQV.
      reflexivity.
    - exfalso; eapply frame_stack_eqv_sing_snoc_inv; eauto.
    - exfalso; eapply frame_stack_eqv_snoc_sing_inv; eauto.
    - left.
      do 4 eexists.
      split; eauto.
      split; eauto.

      split.
      + eapply frame_stack_snoc_inv_fs; eauto.
      + eapply frame_stack_snoc_inv_f; eauto.
  Qed.

  #[global] Instance peek_frame_stack_prop_Proper :
    Proper (frame_stack_eqv ==> frame_eqv ==> iff) peek_frame_stack_prop.
  Proof.
    unfold Proper, respectful.
    intros xs ys XSYS x y XY.
    eapply frame_stack_inv in XSYS as [XSYS | XSYS].
    - (* Singleton framestacks *)
      destruct XSYS as [fs1' [fs2' [f1 [f2 [X [Y [EQFS EQF]]]]]]].
      subst.
      cbn in *.
      rewrite EQF.
      rewrite XY.
      reflexivity.
    - (* Snoc framestacks *)
      destruct XSYS as [f1 [f2 [X [Y EQF]]]].
      subst.
      cbn in *.
      rewrite EQF.
      rewrite XY.
      reflexivity.
  Qed.

  #[global] Instance peek_frame_stack_prop_impl_Proper :
    Proper (frame_stack_eqv ==> frame_eqv ==> Basics.impl ) peek_frame_stack_prop.
  Proof.
    unfold Proper, respectful.
    intros xs ys XSYS x y XY.
    rewrite XY.
    rewrite XSYS.
    intros H; auto.
  Qed.

  #[global] Instance pop_frame_stack_prop_Proper :
    Proper (frame_stack_eqv ==> frame_stack_eqv ==> iff) pop_frame_stack_prop.
  Proof.
    unfold Proper, respectful.
    intros x y XY a b AB.
    eapply frame_stack_inv in XY as [XY | XY].
    - (* Singleton framestacks *)
      destruct XY as [fs1' [fs2' [f1 [f2 [X [Y [EQFS EQF]]]]]]].
      subst.
      cbn in *.
      rewrite EQFS.
      rewrite AB.
      reflexivity.
    - (* Snoc framestacks *)
      destruct XY as [f1 [f2 [X [Y EQF]]]].
      subst.
      cbn in *.
      reflexivity.
  Qed.

  #[global] Instance frame_eqv_cons_Proper :
    Proper (eq ==> frame_eqv ==> frame_eqv) cons.
  Proof.
    unfold Proper, respectful.
    intros ptr ptr' EQ f1 f2 EQV; subst.
    unfold frame_eqv in *.
    cbn in *; intros ptr; split; firstorder.
  Qed.

End FiniteMemoryModelSpecPrimitives.

Module FiniteMemoryModelExecPrimitives (LP : LLVMParams) (MP : MemoryParams LP) : MemoryModelExecPrimitives LP MP.
  Module MMSP := FiniteMemoryModelSpecPrimitives LP MP.
  Module MemSpec := MakeMemoryModelSpec LP MP MMSP.

  Import LP.
  Import LP.ADDR.
  Import LP.SIZEOF.
  Import LP.PROV.
  Import LP.PTOI.
  Import LP.ITOP.
  Import MMSP.
  Import MMSP.MemByte.
  Import MemSpec.
  Import MemHelpers.
  Import MP.
  Import GEP.

  (* Convenient to make these opaque so they don't get unfolded *)
  Section MemoryPrimatives.
    Context {MemM : Type -> Type}.
    Context {Eff : Type -> Type}.
    (* Context `{Monad MemM}. *)
    (* Context `{MonadProvenance Provenance MemM}. *)
    (* Context `{MonadStoreID MemM}. *)
    (* Context `{MonadMemState MemState MemM}. *)
    (* Context `{RAISE_ERROR MemM} `{RAISE_UB MemM} `{RAISE_OOM MemM}. *)
    Context {ExtraState : Type}.
    Context `{MemMonad MemState ExtraState Provenance MemM (itree Eff)}.

    (*** Data types *)
    Definition memory_empty : memory := IntMaps.empty.
    Definition frame_empty : FrameStack := Singleton [].
    Definition empty_memory_stack : memory_stack := (memory_empty, frame_empty).

    Definition initial_memory_state : MemState :=
      mkMemState empty_memory_stack initial_provenance.

    Definition initial_frame : Frame :=
      [].

    (** ** Fresh key getters *)

    (* Get the next key in the memory *)
    Definition next_memory_key (m : memory_stack) : Z :=
      next_key (fst m).

    (*** Primitives on memory *)
    (** Reads *)
    Definition read_byte `{MemMonad MemState ExtraState Provenance MemM (itree Eff)} (ptr : addr) : MemM SByte :=
      let addr := ptr_to_int ptr in
      let pr := address_provenance ptr in
      ms <- get_mem_state;;
      let mem := mem_state_memory ms in
      match read_byte_raw mem addr with
      | None => raise_ub "Reading from unallocated memory."
      | Some (byte, aid) =>
          if access_allowed pr aid
          then ret byte

          else
            raise_ub
              ("Read from memory with invalid provenance -- addr: " ++ Show.show addr ++ ", addr prov: " ++ show_prov pr ++ ", memory allocation id: " ++ Show.show (show_allocation_id aid) ++ " memory: " ++ Show.show (map (fun '(key, (_, aid)) => (key, show_allocation_id aid)) (IM.elements mem)))
      end.

    (** Writes *)
    Definition write_byte `{MemMonad MemState ExtraState Provenance MemM (itree Eff)} (ptr : addr) (byte : SByte) : MemM unit :=
      let addr := ptr_to_int ptr in
      let pr := address_provenance ptr in
      ms <- get_mem_state;;
      let mem := mem_state_memory ms in
      let prov := mem_state_provenance ms in
      match read_byte_raw mem addr with
      | None => raise_ub "Writing to unallocated memory"
      | Some (_, aid) =>
          if access_allowed pr aid
          then
            let mem' := set_byte_raw mem addr (byte, aid) in
            let fs := mem_state_frame_stack ms in
            put_mem_state (mkMemState (mem', fs) prov)
          else raise_ub
                 ("Trying to write to memory with invalid provenance -- addr: " ++ Show.show addr ++ ", addr prov: " ++ show_prov pr ++ ", memory allocation id: " ++ show_allocation_id aid ++ " Memory: " ++ Show.show (map (fun '(key, (_, aid)) => (key, show_allocation_id aid)) (IM.elements mem)))
      end.

    (** Allocations *)
    Definition addr_allocated `{MemMonad MemState ExtraState Provenance MemM (itree Eff)} (ptr : addr) (aid : AllocationId) : MemM bool :=
      ms <- get_mem_state;;
      match read_byte_raw (mem_state_memory ms) (ptr_to_int ptr) with
      | None => ret false
      | Some (byte, aid') =>
          ret (proj_sumbool (aid_eq_dec aid aid'))
      end.

    (* Register a concrete address in a frame *)
    Definition add_to_frame (m : memory_stack) (k : Z) : memory_stack :=
      let '(m,s) := m in
      match s with
      | Singleton f => (m, Singleton (k :: f))
      | Snoc s f => (m, Snoc s (k :: f))
      end.

    (* Register a list of concrete addresses in a frame *)
    Definition add_all_to_frame (m : memory_stack) (ks : list Z) : memory_stack
      := fold_left (fun ms k => add_to_frame ms k) ks m.

    Lemma add_to_frame_preserves_memory :
      forall ms k,
        fst (add_to_frame ms k) = fst ms.
    Proof.
      intros [m fs] k.
      destruct fs; auto.
    Qed.

    Lemma add_all_to_frame_preserves_memory :
      forall ms ks,
        fst (add_all_to_frame ms ks) = fst ms.
    Proof.
      intros ms ks; revert ms;
      induction ks; intros ms; auto.
      cbn in *. unfold add_all_to_frame in IHks.
      specialize (IHks (add_to_frame ms a)).
      rewrite add_to_frame_preserves_memory in IHks.
      auto.
    Qed.

    Lemma add_all_to_frame_nil_preserves_frames :
      forall ms,
        snd (add_all_to_frame ms []) = snd ms.
    Proof.
      intros [m fs].
      destruct fs; auto.
    Qed.

    (* These should be opaque for convenience *)
    #[global] Opaque add_all_to_frame.
    #[global] Opaque next_memory_key.

    Definition allocate_bytes `{MemMonad MemState ExtraState Provenance MemM (itree Eff)} (dt : dtyp) (init_bytes : list SByte) : MemM addr :=
      match dtyp_eq_dec dt DTYPE_Void with
      | left _ => raise_ub "Allocation of type void"
      | _ =>
          let len := length init_bytes in
          match N.eq_dec (sizeof_dtyp dt) (N.of_nat len) with
          | right _ => raise_ub "Sizeof dtyp doesn't match number of bytes for initialization in allocation."
          | _ =>
              (* TODO: roll this into fresh provenance somehow? *)
              ms <- get_mem_state;;
              let '(pr, ms') := mem_state_fresh_provenance ms in
              put_mem_state ms';;

              sid <- fresh_sid;;
              ms <- get_mem_state;;
              let mem_stack := ms_memory_stack ms in
              let addr := next_memory_key mem_stack in
              let '(mem, fs) := ms_memory_stack ms in
              let aid := provenance_to_allocation_id pr in
              let ptr := (int_to_ptr addr (allocation_id_to_prov aid)) in
              ptrs <- get_consecutive_ptrs ptr (length init_bytes);;
              let mem' := add_all_index (map (fun b => (b, aid)) init_bytes) addr mem in
              let mem_stack' := add_all_to_frame (mem', fs) (map ptr_to_int ptrs) in
              put_mem_state (mkMemState mem_stack' pr);;
              ret ptr
          end
      end.


    (** Frame stacks *)
    (* Check if an address is allocated in a frame *)
    Definition ptr_in_frame (f : Frame) (ptr : addr) : bool
      := existsb (fun p => Z.eqb (ptr_to_int ptr) p) f.

    (* Check for the current frame *)
    Definition peek_frame_stack (fs : FrameStack) : Frame :=
      match fs with
      | Singleton f => f
      | Snoc s f => f
      end.

    Definition push_frame_stack (fs : FrameStack) (f : Frame) : FrameStack :=
      Snoc fs f.

    Definition pop_frame_stack (fs : FrameStack) : err FrameStack :=
      match fs with
      | Singleton f => inl "Last frame, cannot pop."%string
      | Snoc s f => inr s
      end.

    Definition mem_state_set_frame_stack (ms : MemState) (fs : FrameStack) : MemState :=
      let (mem, _) := ms_memory_stack ms in
      let pr := mem_state_provenance ms in
      mkMemState (mem, fs) pr.

    Definition mempush `{MemMonad MemState ExtraState Provenance MemM (itree Eff)} : MemM unit :=
      ms <- get_mem_state;;
      let fs := mem_state_frame_stack ms in
      let fs' := push_frame_stack fs initial_frame in
      let ms' := mem_state_set_frame_stack ms fs' in
      put_mem_state ms'.

    Definition free_byte
               (b : Iptr)
               (m : memory) : memory
      := delete b m.

    Definition free_frame_memory (f : Frame) (m : memory) : memory :=
      fold_left (fun m key => free_byte key m) f m.

    Definition mempop `{MemMonad MemState ExtraState Provenance MemM (itree Eff)} : MemM unit :=
      ms <- get_mem_state;;
      let (mem, fs) := ms_memory_stack ms in
      let f := peek_frame_stack fs in
      fs' <- lift_err_RAISE_ERROR (pop_frame_stack fs);;
      let mem' := free_frame_memory f mem in
      let pr := mem_state_provenance ms in
      let ms' := mkMemState (mem', fs') pr in
      put_mem_state ms'.

    (*** Correctness *)
    (* Import ESID. *)
    (* Definition MemStateM := ErrSID_T (state MemState). *)

    (* Instance MemStateM_MonadAllocationId : MonadAllocationId AllocationId MemStateM. *)
    (* Proof. *)
    (*   split. *)
    (*   apply ESID.fresh_allocation_id. *)
    (* Defined. *)

    (* Instance MemStateM_MonadStoreID : MonadStoreId MemStateM. *)
    (* Proof. *)
    (*   split. *)
    (*   apply ESID.fresh_sid. *)
    (* Defined. *)

    (* Instance MemStateM_MonadMemState : MonadMemState MemState MemStateM. *)
    (* Proof. *)
    (*   split. *)
    (*   - apply (lift MonadState.get). *)
    (*   - intros ms. *)
    (*     apply (lift (MonadState.put ms)). *)
    (* Defined. *)

    (* Instance ErrSIDMemMonad : MemMonad MemState ExtraState AllocationId (ESID.ErrSID_T (state MemState)). *)
    (* Proof. *)
    (*   split. *)
    (*   - (* MemMonad_runs_to *) *)
    (*     intros A ma ms. *)
    (*     destruct ms eqn:Hms. *)
    (*     pose proof (runState (runErrSID_T ma ms_sid0 ms_prov0) ms). *)
    (*     destruct X as [[[res sid'] pr'] ms']. *)
    (*     unfold err_ub_oom. *)
    (*     constructor. *)
    (*     repeat split. *)
    (*     destruct res. *)
    (*     left. apply o. *)
    (*     destruct s. *)
    (*     right. left. apply u. *)
    (*     destruct s. *)
    (*     right. right. left. apply e. *)
    (*     repeat right. apply (ms', a). *)
    (*   - (* MemMonad_lift_stateT *) *)
    (*     admit. *)
    (* Admitted. *)

    Import Monad.
    Definition exec_correct {MemM Eff ExtraState} `{MM: MemMonad MemState ExtraState Provenance MemM (itree Eff)} {X} (exec : MemM X) (spec : MemPropT MemState X) : Prop :=
      forall ms st,
        (@MemMonad_valid_state MemState ExtraState Provenance MemM (itree Eff) _ _ _ _ _ _ _ _ _ _ _ _ _ _ ms st) ->
        let t := MemMonad_run exec ms st in
        let eqi := (@eq1 _ (@MemMonad_eq1_runm _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ MM)) in
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

    (* TODO: Move these tactics *)
    Ltac MemMonad_go :=
      repeat match goal with
             | |- context [MemMonad_run (bind _ _)] => rewrite MemMonad_run_bind
             | |- context [MemMonad_run get_mem_state] => rewrite MemMonad_get_mem_state
             | |- context [MemMonad_run (put_mem_state _)] => rewrite MemMonad_put_mem_state
             | |- context [MemMonad_run (ret _)] => rewrite MemMonad_run_ret
             | |- context [MemMonad_run (raise_ub _)] => rewrite MemMonad_run_raise_ub
             end.

    Ltac break_memory_lookup :=
      match goal with
      | |- context [match read_byte_raw ?memory ?intptr with _ => _ end] =>
          let Hlookup := fresh "Hlookup" in
          let byte := fresh "byte" in
          let aid := fresh "aid" in
          destruct (read_byte_raw memory intptr) as [[byte aid] | ] eqn:Hlookup
      end.

    Ltac MemMonad_break :=
      first
        [ break_memory_lookup
        | match goal with
          | |- context [MemMonad_run (if ?X then _ else _)] =>
              let Hcond := fresh "Hcond" in
              destruct X eqn:Hcond
          end
        ].

    Ltac MemMonad_inv_break :=
      match goal with
      | H: Some _ = Some _ |- _ =>
          inv H
      | H: None = Some _ |- _ =>
          inv H
      | H: Some _ = None |- _ =>
          inv H
      end; cbn in *.

    Ltac MemMonad_subst_if :=
      match goal with
      | H: ?X = true |- context [if ?X then _ else _] =>
          rewrite H
      | H: ?X = false |- context [if ?X then _ else _] =>
          rewrite H
      end.

    Ltac intros_mempropt_contra :=
      intros [?err | [[?ms' ?res] | ?oom]];
      match goal with
      | |- ~ _ =>
          let CONTRA := fresh "CONTRA" in
          let err := fresh "err" in
          intros CONTRA;
          destruct CONTRA as [err [CONTRA | CONTRA]]; auto;
          destruct CONTRA as (? & ? & (? & ?) & CONTRA); subst
      | |- ~ _ =>
          let CONTRA := fresh "CONTRA" in
          let err := fresh "err" in
          intros CONTRA;
          destruct CONTRA as (? & ? & (? & ?) & CONTRA); subst
      end.

    Ltac subst_mempropt :=
      repeat
        match goal with
        | Hlup: read_byte_raw ?mem ?addr = _,
            H: context [match read_byte_raw ?mem ?addr with _ => _ end] |- _
          => rewrite Hlup in H; cbn in H
        | Hlup: read_byte_raw ?mem ?addr = _ |-
            context [match read_byte_raw ?mem ?addr with _ => _ end]
          => rewrite Hlup; cbn
        | HC: ?X = _,
            H: context [if ?X then _ else _] |- _
          => rewrite HC in H; cbn in H
        | HC: ?X = _ |-
            context [if ?X then _ else _]
          => rewrite HC; cbn
        end.

    Ltac solve_mempropt_contra :=
      intros_mempropt_contra;
      repeat
        (first
           [ progress subst_mempropt
           | tauto
        ]).

    Ltac MemMonad_solve :=
      repeat
        (first
           [ progress (MemMonad_go; cbn)
           | MemMonad_break; try MemMonad_inv_break; cbn
           | solve_mempropt_contra
           | MemMonad_subst_if; cbn
           | repeat eexists
           | tauto
        ]).

    Ltac unfold_mem_state_memory :=
      unfold mem_state_memory;
      unfold fst;
      unfold ms_memory_stack.

    Ltac unfold_mem_state_memory_in H :=
      unfold mem_state_memory in H;
      unfold fst in H;
      unfold ms_memory_stack in H.

    (* TODO: move this *)
    Lemma byte_allocated_mem_stack :
      forall ms1 ms2 addr aid,
        byte_allocated ms1 addr aid ->
        mem_state_memory_stack ms1 = mem_state_memory_stack ms2 ->
        byte_allocated ms2 addr aid.
    Proof.
      intros [ms1 pr1] [ms2 pr2] addr aid ALLOC EQ.
      cbn in EQ; subst.
      unfold byte_allocated, byte_allocated_MemPropT in *.
      cbn in *.
      destruct ALLOC as [ms' [ms'' [[EQ1 EQ2] ALLOC]]]; subst.
      destruct ALLOC as [ms' [b [ALLOC [EQ1 EQ2]]]]; subst.
      destruct ALLOC as [ms' [ms'' [[EQ1 EQ2] ALLOC]]]; subst.
      repeat eexists.
      unfold mem_state_memory in *; cbn in *.
      break_match.
      - break_match.
        tauto.
      - tauto.
    Qed.

    (* TODO: move this *)
    Lemma read_byte_prop_mem_stack :
      forall ms1 ms2 addr sbyte,
        read_byte_prop ms1 addr sbyte ->
        mem_state_memory_stack ms1 = mem_state_memory_stack ms2 ->
        read_byte_prop ms2 addr sbyte.
    Proof.
      intros [ms1 pr1] [ms2 pr2] addr aid ALLOC EQ.
      cbn in EQ; subst.
      unfold read_byte_prop, read_byte_MemPropT in *.
      cbn in *.
      destruct ALLOC as [ms' [ms'' [[EQ1 EQ2] ALLOC]]]; subst.
      repeat eexists.
      unfold mem_state_memory in *; cbn in *.
      break_match.
      - break_match; tauto.
      - tauto.
    Qed.

    Ltac solve_byte_allocated :=
      solve [ eapply byte_allocated_mem_stack; eauto
            | repeat eexists;
              first [ cbn; (* This was unfold_mem_state_memory, but I think with read_byte_raw / write_byte raw opaque it's fine to cbn *)
                      rewrite set_byte_raw_eq; [|solve [eauto]]
                    | subst_mempropt
                ];
              split; try reflexivity;
              first [rewrite aid_access_allowed_refl | apply aid_eq_dec_refl]; auto
        ].

    Ltac solve_allocations_preserved :=
      intros ?ptr ?aid; split; intros ALLOC;
      solve_byte_allocated.

    Ltac destruct_read_byte_allowed_in READ :=
      destruct READ as [?aid [?ALLOC ?ALLOWED]].

    Ltac destruct_write_byte_allowed_in WRITE :=
      destruct WRITE as [?aid [?ALLOC ?ALLOWED]].

    Ltac break_write_byte_allowed_hyps :=
      repeat
        match goal with
        | WRITE : write_byte_allowed _ _ |- _ =>
            destruct_write_byte_allowed_in WRITE
        end.

    Ltac break_read_byte_allowed_hyps :=
      repeat
        match goal with
        | READ : read_byte_allowed _ _ |- _ =>
            destruct_read_byte_allowed_in READ
        end.

    Ltac break_access_hyps :=
      break_read_byte_allowed_hyps;
      break_write_byte_allowed_hyps.

    Hint Rewrite int_to_ptr_provenance : PROVENANCE.
    Hint Resolve access_allowed_refl : ACCESS_ALLOWED.

      Ltac access_allowed_auto :=
        solve [autorewrite with PROVENANCE; eauto with ACCESS_ALLOWED].

      Ltac solve_access_allowed :=
        solve [match goal with
               | HMAPM :
                 Util.map_monad _ _ = inr ?xs,
                   IN :
                   In _ ?xs |- _ =>
                   let GENPTR := fresh "GENPTR" in
                   pose proof map_monad_err_In _ _ _ _ HMAPM IN as [?ip [GENPTR ?INip]];
                   apply handle_gep_addr_preserves_provenance in GENPTR;
                   rewrite <- GENPTR
               end; access_allowed_auto
              | access_allowed_auto
          ].

    Ltac solve_write_byte_allowed :=
      break_access_hyps; eexists; split; [| solve_access_allowed]; solve_byte_allocated.

    Ltac solve_read_byte_allowed :=
      solve_write_byte_allowed.

    Ltac solve_read_byte_allowed_all_preserved :=
      intros ?ptr; split; intros ?READ; solve_read_byte_allowed.

    Ltac solve_write_byte_allowed_all_preserved :=
      intros ?ptr; split; intros ?WRITE; solve_write_byte_allowed.

    Ltac solve_read_byte_prop :=
      solve [ eapply read_byte_prop_mem_stack; eauto
            | repeat eexists;
              first [ cbn; (*unfold_mem_state_memory; *)
                      rewrite set_byte_raw_eq; [|solve [eauto]]
                    | subst_mempropt
                ];
              cbn; subst_mempropt;
              split; auto
        ].

    Ltac solve_read_byte_prop_all_preserved :=
      split; intros ?READ; solve_read_byte_prop.

    Ltac solve_read_byte_preserved :=
      split;
      [ solve_read_byte_allowed_all_preserved
      | solve_read_byte_prop_all_preserved
      ].

    (* Ltac solve_set_byte_memory := *)
    (*   split; [solve_read_byte_allowed | solve_read_byte_prop | solve_disjoint_read_bytes]. *)

    Ltac solve_read_byte_spec :=
      split; [solve_read_byte_allowed | solve_read_byte_prop].

    Ltac solve_frame_stack_preserved :=
      solve [
          let PROP := fresh "PROP" in
          intros ?fs; split; intros PROP; unfold mem_state_frame_stack_prop in *; auto
          (* intros ?fs; split; intros PROP; inv PROP; reflexivity *)
        ].

    (* TODO: move this stuff? *)
    Hint Resolve
         provenance_lt_trans
         provenance_lt_next_provenance
         provenance_lt_nrefl : PROVENANCE_LT.

    Hint Unfold used_provenance_prop : PROVENANCE_LT.

    Ltac solve_used_provenance_prop :=
      unfold used_provenance_prop in *;
      eauto with PROVENANCE_LT.

    Ltac solve_extend_provenance :=
      unfold extend_provenance;
      split; [|split]; solve_used_provenance_prop.

    Ltac solve_fresh_provenance_invariants :=
      split;
      [ solve_extend_provenance
      | split; [| split; [| split]];
        [ solve_read_byte_preserved
        | solve_write_byte_allowed_all_preserved
        | solve_allocations_preserved
        | solve_frame_stack_preserved
        ]
      ].

    Lemma byte_allocated_set_byte_raw_eq :
      forall ptr aid new new_aid m1 m2,
        byte_allocated m1 ptr aid ->
        mem_state_memory m2 = set_byte_raw (mem_state_memory m1) (ptr_to_int ptr) (new, new_aid) ->
        byte_allocated m2 ptr new_aid.
    Proof.
      intros ptr aid new new_aid m1 m2 [aid' [ms [GET ALLOCATED]]] MEM.
      inversion GET; subst.
      cbn in ALLOCATED.
      destruct ALLOCATED as (ms' & b & ALLOCATED).
      destruct ALLOCATED as [ALLOCATED [C1 C2]]; subst.
      destruct ALLOCATED as [ms'' [ms''' [[C1 C2] ALLOCATED]]]; subst.

      cbn in GET.
      repeat eexists.
      rewrite MEM.
      rewrite set_byte_raw_eq; auto.
      cbn; split; auto.
      apply aid_eq_dec_refl.
    Qed.

    Lemma byte_allocated_set_byte_raw_neq :
      forall ptr aid new_ptr new new_aid m1 m2,
        byte_allocated m1 ptr aid ->
        disjoint_ptr_byte ptr new_ptr ->
        mem_state_memory m2 = set_byte_raw (mem_state_memory m1) (ptr_to_int new_ptr) (new, new_aid) ->
        byte_allocated m2 ptr aid.
    Proof.
      intros ptr aid new_ptr new new_aid m1 m2 [aid' [ms [GET ALLOCATED]]] DISJOINT MEM.
      inversion GET; subst.
      cbn in ALLOCATED.
      destruct ALLOCATED as (ms' & b & ALLOCATED).
      destruct ALLOCATED as [ALLOCATED [C1 C2]]; subst.
      destruct ALLOCATED as [ms'' [ms''' [[C1 C2] ALLOCATED]]]; subst.

      repeat eexists.
      rewrite MEM.
      unfold mem_byte in *.
      rewrite set_byte_raw_neq; auto.
      break_match.
      break_match.
      destruct ALLOCATED.
      cbn; split; auto.
      destruct ALLOCATED.
      match goal with
      | H: true = false |- _ =>
          inv H
      end.
    Qed.

    Lemma byte_allocated_set_byte_raw :
      forall ptr aid ptr_new new m1 m2,
        byte_allocated m1 ptr aid ->
        mem_state_memory m2 = set_byte_raw (mem_state_memory m1) (ptr_to_int ptr_new) new ->
        exists aid2, byte_allocated m2 ptr aid2.
    Proof.
      intros ptr aid ptr_new new m1 m2 ALLOCATED MEM.
      pose proof (Z.eq_dec (ptr_to_int ptr) (ptr_to_int ptr_new)) as [EQ | NEQ].
      - (* EQ *)
        destruct new.
        rewrite <- EQ in MEM.
        eexists.
        eapply byte_allocated_set_byte_raw_eq; eauto.
      - (* NEQ *)
        destruct new.
        subst.
        eexists.
        eapply byte_allocated_set_byte_raw_neq; eauto.
    Qed.

    (** Correctness of the main operations on memory *)
    Lemma read_byte_correct :
      forall ptr, exec_correct (read_byte ptr) (read_byte_MemPropT ptr).
    Proof.
      unfold exec_correct.
      intros ptr ms st VALID.

      Ltac solve_MemMonad_valid_state :=
        solve [auto].

      (* Need to destruct ahead of time so we know if UB happens *)
      destruct (read_byte_raw (mem_state_memory ms) (ptr_to_int ptr)) as [[sbyte aid]|] eqn:READ.
      destruct (access_allowed (address_provenance ptr) aid) eqn:ACCESS.
      - (* Success *)
        right.
        split; [|split].
        + (* Error *)
          do 2 eexists; intros RUN.
          exfalso.
          unfold read_byte, read_byte_MemPropT in *.

          rewrite MemMonad_run_bind in RUN; [| solve_MemMonad_valid_state].
          rewrite MemMonad_get_mem_state in RUN.
          rewrite bind_ret_l in RUN.

          rewrite READ in RUN.
          rewrite ACCESS in RUN.

          rewrite MemMonad_run_ret in RUN; [| solve_MemMonad_valid_state].

          apply MemMonad_eq1_raise_error_inv in RUN; auto.
        + (* OOM *)
          do 2 eexists; intros RUN.
          exfalso.
          unfold read_byte, read_byte_MemPropT in *.

          rewrite MemMonad_run_bind in RUN; [| solve_MemMonad_valid_state].
          rewrite MemMonad_get_mem_state in RUN.
          rewrite bind_ret_l in RUN.

          rewrite READ in RUN.
          rewrite ACCESS in RUN.

          rewrite MemMonad_run_ret in RUN; [| solve_MemMonad_valid_state].

          apply MemMonad_eq1_raise_oom_inv in RUN; auto.
        + (* Success *)
          intros st' ms' x RUN.
          unfold read_byte, read_byte_MemPropT in *.

          rewrite MemMonad_run_bind in RUN; [| solve_MemMonad_valid_state].
          rewrite MemMonad_get_mem_state in RUN.
          rewrite bind_ret_l in RUN.

          rewrite READ in RUN.
          rewrite ACCESS in RUN.

          rewrite MemMonad_run_ret in RUN; [| solve_MemMonad_valid_state].

          apply eq1_ret_ret in RUN; [inv RUN | typeclasses eauto].
          cbn; do 2 eexists.
          rewrite READ; cbn.
          rewrite ACCESS; cbn.
          eauto.
      - (* UB from provenance mismatch *)
        left.
        Ltac solve_read_byte_MemPropT_contra READ ACCESS :=
          solve [repeat eexists; right;
                 repeat eexists; cbn;
                 try rewrite READ in *; cbn in *;
                 try rewrite ACCESS in *; cbn in *;
                 tauto].

        solve_read_byte_MemPropT_contra READ ACCESS.
      - (* UB from accessing unallocated memory *)
        left.
        solve_read_byte_MemPropT_contra READ ACCESS.

        Unshelve.
        all: exact (""%string).
    Qed.

    (* TODO: move this? *)
    Lemma disjoint_ptr_byte_dec :
      forall p1 p2,
        {disjoint_ptr_byte p1 p2} + { ~ disjoint_ptr_byte p1 p2}.
    Proof.
      intros p1 p2.
      unfold disjoint_ptr_byte.
      pose proof Z.eq_dec (ptr_to_int p1) (ptr_to_int p2) as [EQ | NEQ].
      - rewrite EQ.
        right.
        intros CONTRA.
        contradiction.
      - left; auto.
    Qed.

    Lemma write_byte_correct :
      forall ptr byte, exec_correct (write_byte ptr byte) (write_byte_spec_MemPropT ptr byte).
    Proof.
      unfold exec_correct.
      intros ptr byte ms st VALID.

      (* Need to destruct ahead of time so we know if UB happens *)
      destruct (read_byte_raw (mem_state_memory ms) (ptr_to_int ptr)) as [[sbyte aid]|] eqn:READ.
      destruct (access_allowed (address_provenance ptr) aid) eqn:ACCESS.

      - (* Success *)
        right.

        cbn.
        split; [| split].

        + (* Error *)
          eexists. exists ""%string.
          intros RUN.

          unfold write_byte in RUN.

          rewrite MemMonad_run_bind in RUN; [| solve_MemMonad_valid_state].
          rewrite MemMonad_get_mem_state in RUN.
          rewrite bind_ret_l in RUN.

          rewrite READ in RUN.
          rewrite ACCESS in RUN.

          rewrite MemMonad_put_mem_state in RUN.
          apply MemMonad_eq1_raise_error_inv in RUN; auto.
        + (* OOM *)
          eexists. exists ""%string.
          intros RUN.

          unfold write_byte in RUN.

          rewrite MemMonad_run_bind in RUN; [| solve_MemMonad_valid_state].
          rewrite MemMonad_get_mem_state in RUN.
          rewrite bind_ret_l in RUN.

          rewrite READ in RUN.
          rewrite ACCESS in RUN.

          rewrite MemMonad_put_mem_state in RUN.
          apply MemMonad_eq1_raise_oom_inv in RUN; auto.
        + (* Success *)
          intros st' ms' x RUN.

          unfold write_byte in RUN.

          rewrite MemMonad_run_bind in RUN; [| solve_MemMonad_valid_state].
          rewrite MemMonad_get_mem_state in RUN.
          rewrite bind_ret_l in RUN.

          rewrite READ in RUN.
          rewrite ACCESS in RUN.

          rewrite MemMonad_put_mem_state in RUN.
          apply eq1_ret_ret in RUN; [inv RUN | typeclasses eauto].

          split.
          * (* Write is allowed *)
            solve_write_byte_allowed.
          * (* Byte is set in new memory *)
            split.
            -- (* Read byte spec *)
              solve_read_byte_spec.
            -- (* Disjoint bytes are preserved *)
              intros ptr' byte' DISJOINT.
              split; intros READBYTE.
              { split.
                - (* TODO: solve_read_byte_allowed *)
                  apply read_byte_allowed_spec in READBYTE.
                  (* TODO: is there a way to avoid having to do these destructs before eexists? *)
                  destruct READBYTE as [aid' [ALLOCATED ALLOWED]].
                  unfold byte_allocated, byte_allocated_MemPropT in ALLOCATED.
                  cbn in ALLOCATED.
                  destruct ALLOCATED as [ms' [ms'' [[EQ1 EQ2] ALLOCATED]]]; subst.
                  destruct ALLOCATED as [ms'' [a [ALLOCATED [EQ1 EQ2]]]]; subst.
                  destruct ALLOCATED as [ms'' [ms''' [[EQ1 EQ2] ALLOCATED]]]; subst.
                  break_match_hyp.
                  break_match_hyp.
                  { (* Read of ptr' succeeds *)
                    destruct ALLOCATED as [_ AIDEQ].

                    eexists; split.
                    { (* TODO: solve_byte_allocated *)
                      cbn.
                      repeat eexists.
                      cbn.
                      rewrite set_byte_raw_neq; [| solve [eauto]].

                      break_match.
                      - break_match; split; inv Heqo; auto.
                        apply AIDEQ.
                      - inv Heqo.
                    }
                    { (* TODO: solve_access_allowed *)
                      eapply ALLOWED.
                    }
                  }

                  { (* Read fails *)
                    destruct ALLOCATED as [_ EQ].
                    inv EQ.
                  }
                - (* TODO: solve_read_byte_prop. *)
                  apply read_byte_value in READBYTE.
                  (* TODO: is there a way to avoid having to do these destructs before eexists? *)
                  unfold read_byte_prop, read_byte_MemPropT in *.
                  cbn in READBYTE. cbn.
                  destruct READBYTE as [ms' [ms'' [[EQ1 EQ2] READBYTE]]]; subst.

                  repeat eexists.
                  cbn.
                  rewrite set_byte_raw_neq; [| solve [eauto]].
                  break_match; [break_match|].
                  { destruct READBYTE; split; auto.
                  }
                  { firstorder.
                  }
                  { firstorder.
                  }
              }

              { split.
                - (* TODO: solve_read_byte_allowed *)
                  apply read_byte_allowed_spec in READBYTE.
                  (* TODO: is there a way to avoid having to do these destructs before eexists? *)
                  destruct READBYTE as [aid' [ALLOCATED ALLOWED]].
                  unfold byte_allocated, byte_allocated_MemPropT in ALLOCATED.
                  cbn in ALLOCATED.
                  destruct ALLOCATED as [ms' [ms'' [[EQ1 EQ2] ALLOCATED]]]; subst.
                  destruct ALLOCATED as [ms'' [a [ALLOCATED [EQ1 EQ2]]]]; subst.
                  destruct ALLOCATED as [ms'' [ms''' [[EQ1 EQ2] ALLOCATED]]]; subst.
                  break_match_hyp.
                  break_match_hyp.
                  { (* Read of ptr' succeeds *)
                    destruct ALLOCATED as [_ AIDEQ].

                    eexists; split.
                    { (* TODO: solve_byte_allocated *)
                      cbn.
                      repeat eexists.
                      cbn.
                      cbn in Heqo.
                      rewrite set_byte_raw_neq in Heqo; [| solve [eauto]].

                      break_match.
                      - break_match; split; inv Heqo; auto.
                        apply AIDEQ.
                      - inv Heqo.
                    }
                    { (* TODO: solve_access_allowed *)
                      eapply ALLOWED.
                    }
                  }

                  { (* Read fails *)
                    destruct ALLOCATED as [_ EQ].
                    inv EQ.
                  }
                - (* TODO: solve_read_byte_prop. *)
                  apply read_byte_value in READBYTE.
                  (* TODO: is there a way to avoid having to do these destructs before eexists? *)
                  unfold read_byte_prop, read_byte_MemPropT in *.
                  cbn in READBYTE. cbn.
                  destruct READBYTE as [ms' [ms'' [[EQ1 EQ2] READBYTE]]]; subst.

                  repeat eexists.
                  cbn in READBYTE.
                  rewrite set_byte_raw_neq in READBYTE; [| solve [eauto]].
                  break_match; [break_match|].
                  { destruct READBYTE; split; auto.
                  }
                  { firstorder.
                  }
                  { firstorder.
                  }
              }
          * (* TODO: solve_write_byte_operation_invariants *)
            split.
            -- (* Allocations preserved *)
              (* TODO: solve_allocations_preserved *)
              unfold allocations_preserved.
              intros addr aid'.
              split.
              { (* TODO: solve_byte_allocated *)
                intros ALLOC.
                repeat eexists.
                cbn.
                match goal with
                | |- context [ read_byte_raw (set_byte_raw _ ?p1 _) ?p2 ] =>
                    pose proof Z.eq_dec p1 p2 as [NDISJOINT | DISJOINT]
                end.

                - rewrite set_byte_raw_eq; [| solve [eauto]].
                  split; auto.
                  destruct ALLOC as [ms' [ms'' [[EQ1 EQ2] ALLOC]]]; subst.
                  rename ms' into ms.
                  destruct ALLOC as [ms' [b [ALLOC [EQ1 EQ2]]]]; subst.
                  destruct ALLOC as [ms' [ms'' [[EQ1 EQ2] ALLOC]]]; subst.
                  rewrite NDISJOINT in *.
                  rewrite READ in *.
                  destruct ALLOC; auto.
                - rewrite set_byte_raw_neq; [| solve [eauto]].
                  destruct ALLOC as [ms' [ms'' [[EQ1 EQ2] ALLOC]]]; subst.
                  rename ms' into ms.
                  destruct ALLOC as [ms' [b [ALLOC [EQ1 EQ2]]]]; subst.
                  destruct ALLOC as [ms' [ms'' [[EQ1 EQ2] ALLOC]]]; subst.

                  break_match.
                  + break_match.
                    destruct ALLOC; auto.
                  + destruct ALLOC as [_ CONTRA].
                    inv CONTRA.
              }
{ (* TODO: solve_byte_allocated *)
                intros ALLOC.

                repeat eexists.
                cbn.
                cbn in ALLOC.
                destruct ALLOC as [ms' [ms'' [[EQ1 EQ2] ALLOC]]]; subst.
                destruct ALLOC as [ms' [b [ALLOC [EQ1 EQ2]]]]; subst.
                destruct ALLOC as [ms' [ms'' [[EQ1 EQ2] ALLOC]]]; subst.
                cbn in ALLOC.

                match goal with
                | ALLOC : context [ read_byte_raw (set_byte_raw _ ?p1 _) ?p2 ] |- _ =>
                    pose proof Z.eq_dec p1 p2 as [NDISJOINT | DISJOINT]
                end.

                - rewrite NDISJOINT in *.
                  rewrite set_byte_raw_eq in ALLOC; [| solve [eauto]].
                  rewrite READ in *.
                  tauto.
                - rewrite set_byte_raw_neq in ALLOC; [| solve [eauto]].
                  break_match.
                  + break_match. tauto.
                  + tauto.
              }
            -- (* Frame stack preserved *)
              solve_frame_stack_preserved.
            -- (* TODO: solve_read_byte_allowed_all_preserved *)
              unfold read_byte_allowed_all_preserved.
              intros addr.
              split; intros [aid' [ALLOC ALLOWED]]; exists aid'.
              { split; repeat eexists; cbn.
                - match goal with
                  | |- context [ read_byte_raw (set_byte_raw _ ?p1 _) ?p2 ] =>
                      pose proof Z.eq_dec p1 p2 as [NDISJOINT | DISJOINT]
                  end.
                  + rewrite NDISJOINT in *.
                    rewrite set_byte_raw_eq; [| solve [eauto]].
                    split; auto.
                    unfold byte_allocated, byte_allocated_MemPropT in ALLOC.
                    cbn in ALLOC.
                    destruct ALLOC as [ms' [ms'' [[EQ1 EQ2] ALLOC]]]; subst.
                    destruct ALLOC as [ms'' [a [ALLOC [EQ1 EQ2]]]]; subst.
                    destruct ALLOC as [ms'' [ms''' [[EQ1 EQ2] ALLOC]]]; subst.
                    break_match_hyp.
                    break_match_hyp.
                    inversion READ; subst.
                    tauto.
                    destruct ALLOC as [_ CONTRA].
                    inv CONTRA.
                  + rewrite set_byte_raw_neq; [| solve [eauto]].
                    unfold byte_allocated, byte_allocated_MemPropT in ALLOC.
                    cbn in ALLOC.
                    destruct ALLOC as [ms' [ms'' [[EQ1 EQ2] ALLOC]]]; subst.
                    destruct ALLOC as [ms'' [a [ALLOC [EQ1 EQ2]]]]; subst.
                    destruct ALLOC as [ms'' [ms''' [[EQ1 EQ2] ALLOC]]]; subst.
                    break_match_hyp.
                    break_match_hyp.
                    inversion READ; subst.
                    tauto.
                    destruct ALLOC as [_ CONTRA].
                    inv CONTRA.
                - auto.
              }
              { split; repeat eexists; cbn.
                - cbn in ALLOC.
                  destruct ALLOC as [ms' [ms'' [[EQ1 EQ2] ALLOC]]]; subst.
                  destruct ALLOC as [ms'' [a [ALLOC [EQ1 EQ2]]]]; subst.
                  destruct ALLOC as [ms'' [ms''' [[EQ1 EQ2] ALLOC]]]; subst.
                  cbn in ALLOC.
                  match goal with
                  | ALLOC : context [ read_byte_raw (set_byte_raw _ ?p1 _) ?p2 ] |- _ =>
                      pose proof Z.eq_dec p1 p2 as [NDISJOINT | DISJOINT]
                  end.
                  + rewrite NDISJOINT in *.
                    rewrite set_byte_raw_eq in ALLOC; [| solve [eauto]].
                    rewrite READ in *.
                    tauto.
                  + rewrite set_byte_raw_neq in ALLOC; [| solve [eauto]].
                    break_match_hyp.
                    break_match_hyp.
                    tauto.
                    tauto.
                - auto.
              }
            -- (* TODO: solve_write_byte_allowed_all_preserved *)
              intros addr.
              split; intros [aid' [ALLOC ALLOWED]]; exists aid'.
              { split; repeat eexists; cbn.
                - match goal with
                  | |- context [ read_byte_raw (set_byte_raw _ ?p1 _) ?p2 ] =>
                      pose proof Z.eq_dec p1 p2 as [NDISJOINT | DISJOINT]
                  end.
                  + rewrite NDISJOINT in *.
                    rewrite set_byte_raw_eq; [| solve [eauto]].
                    split; auto.
                    unfold byte_allocated, byte_allocated_MemPropT in ALLOC.
                    cbn in ALLOC.
                    destruct ALLOC as [ms' [ms'' [[EQ1 EQ2] ALLOC]]]; subst.
                    destruct ALLOC as [ms'' [a [ALLOC [EQ1 EQ2]]]]; subst.
                    destruct ALLOC as [ms'' [ms''' [[EQ1 EQ2] ALLOC]]]; subst.
                    break_match_hyp.
                    break_match_hyp.
                    inversion READ; subst.
                    tauto.
                    destruct ALLOC as [_ CONTRA].
                    inv CONTRA.
                  + rewrite set_byte_raw_neq; [| solve [eauto]].
                    unfold byte_allocated, byte_allocated_MemPropT in ALLOC.
                    cbn in ALLOC.
                    destruct ALLOC as [ms' [ms'' [[EQ1 EQ2] ALLOC]]]; subst.
                    destruct ALLOC as [ms'' [a [ALLOC [EQ1 EQ2]]]]; subst.
                    destruct ALLOC as [ms'' [ms''' [[EQ1 EQ2] ALLOC]]]; subst.
                    break_match_hyp.
                    break_match_hyp.
                    inversion READ; subst.
                    tauto.
                    destruct ALLOC as [_ CONTRA].
                    inv CONTRA.
                - auto.
              }
              { split; repeat eexists; cbn.
                - cbn in ALLOC.
                  destruct ALLOC as [ms' [ms'' [[EQ1 EQ2] ALLOC]]]; subst.
                  destruct ALLOC as [ms'' [a [ALLOC [EQ1 EQ2]]]]; subst.
                  destruct ALLOC as [ms'' [ms''' [[EQ1 EQ2] ALLOC]]]; subst.
                  cbn in ALLOC.
                  match goal with
                  | ALLOC : context [ read_byte_raw (set_byte_raw _ ?p1 _) ?p2 ] |- _ =>
                      pose proof Z.eq_dec p1 p2 as [NDISJOINT | DISJOINT]
                  end.
                  + rewrite NDISJOINT in *.
                    rewrite set_byte_raw_eq in ALLOC; [| solve [eauto]].
                    rewrite READ in *.
                    tauto.
                  + rewrite set_byte_raw_neq in ALLOC; [| solve [eauto]].
                    break_match_hyp.
                    break_match_hyp.
                    tauto.
                    tauto.
                - auto.
              }
            -- (* TODO: solve_preserve_allocation_ids *)
              unfold preserve_allocation_ids.
              unfold used_provenance_prop.
              intros pr'.
              split; intros LE; cbn in *; auto.
      - (* UB due to provenance *)
        left.
        Ltac solve_write_byte_MemPropT_contra READ ACCESS :=
          solve [repeat eexists; right;
                 repeat eexists; cbn;
                 try rewrite READ in *; cbn in *;
                 try rewrite ACCESS in *; cbn in *;
                 tauto].

        repeat eexists; cbn.
        intros m2 CONTRA.

        (* Access not allowed *)
        inversion CONTRA.
        unfold write_byte_allowed in *.
        unfold byte_allocated, byte_allocated_MemPropT in *.
        unfold addr_allocated_prop in *.
        destruct byte_write_succeeds0 as [aid' [ALLOC ALLOWED]].

        cbn in ALLOC.
        destruct ALLOC as [ms'' [ms''' [[EQ1 EQ2] ALLOC]]]; subst.
        rename ms'' into ms.
        destruct ALLOC as [ms'' [a [ALLOC [EQ1 EQ2]]]]; subst.
        destruct ALLOC as [ms'' [ms''' [[EQ1 EQ2] ALLOC]]]; subst.
        rewrite READ in *.
        destruct ALLOC as [EQ AID_ALLOWED].

        destruct (aid_eq_dec aid' aid); inv AID_ALLOWED.
        rewrite ACCESS in ALLOWED; inv ALLOWED.
      - (* UB from accessing unallocated memory *)
        left.
        repeat eexists; cbn.
        intros m2 CONTRA.

        (* Accessing unallocated memory *)
        inversion CONTRA.
        unfold write_byte_allowed in *.
        unfold byte_allocated, byte_allocated_MemPropT in *.
        unfold addr_allocated_prop in *.
        destruct byte_write_succeeds0 as [aid' [ALLOC ALLOWED]].

        cbn in ALLOC.
        destruct ALLOC as [ms'' [ms''' [[EQ1 EQ2] ALLOC]]]; subst.
        rename ms'' into ms.
        destruct ALLOC as [ms'' [a [ALLOC [EQ1 EQ2]]]]; subst.
        destruct ALLOC as [ms'' [ms''' [[EQ1 EQ2] ALLOC]]]; subst.
        rewrite READ in *.
        destruct ALLOC as [EQ AID_ALLOWED].
        inv AID_ALLOWED.

        Unshelve.
        all: exact ""%string.
    Qed.

    Lemma allocate_bytes_correct :
      forall dt init_bytes, exec_correct (allocate_bytes dt init_bytes) (allocate_bytes_spec_MemPropT dt init_bytes).
    Proof.
      unfold exec_correct.
      intros dt init_bytes ms st VALID.

      (* Need to destruct ahead of time so we know if UB happens *)
      pose proof (dtyp_eq_dec dt DTYPE_Void) as [VOID | NVOID].

      destruct (mem_state_fresh_provenance ms) as [pr' ms_fresh_pr] eqn:FRESH.

      { (* Can't allocate VOID *)
        left.
        repeat eexists; right.
        exists ms_fresh_pr. exists pr'.
        split.
        { (* fresh_provenance *)
          unfold fresh_provenance.
          cbn.
          destruct ms; inversion FRESH; cbn in *; subst.

          (* TODO: separate into lemmas? *)
          cbn.
          split; [|split; [|split; [|split]]].
          - (* TODO: solve_extend_provenance *)
            unfold extend_provenance.
            split.
            intros pr USED.
            { eapply provenance_lt_trans; eauto.
              eapply provenance_lt_next_provenance.
            }

            eapply mem_state_fresh_provenance_fresh; eauto.
          - (* TODO: solve_read_byte_preserved *)
            unfold read_byte_preserved.
            split.
            cbn.
            + (* TODO: solve_read_byte_allowed_all_preserved *)
              unfold read_byte_allowed_all_preserved; intros ptr.
              split; intros [aid [ALLOC ALLOWED]];
                solve_read_byte_allowed.
            + (* TODO: solve_read_byte_prop_all_preserved *)
              unfold read_byte_prop_all_preserved.
              intros ptr byte.
              split; intros PROP; solve_read_byte_prop.
          - (* TODO: solve_write_byte_allowed_all_preserved *)
            unfold write_byte_allowed_all_preserved; intros ptr.
            split; intros [aid [ALLOC ALLOWED]];
              solve_write_byte_allowed.
          - (* TODO: solve_allocations_preserved *)
            unfold allocations_preserved; intros ptr aid.
            split; intros PROP;
              solve_byte_allocated.
          - solve_frame_stack_preserved.
        }
        {
          repeat eexists.
          left. intros m2 ptr ptrs.
          intros SUCC.
          inversion SUCC.
          contradiction.
        }
      }

      { (* dt is non-void, allocation may succeed *)
        right.
        split; [|split].
        - (* Error *)
          (* Always allowed to error *)
          repeat eexists. left.
          cbn. auto.
        - (* OOM *)
          (* Always allowed to oom *)
          repeat eexists. left.
          cbn. auto.
        - (* Success *)
          unfold allocate_bytes_spec_MemPropT.
          intros st_final ms_final alloc_addr RUN.
          unfold allocate_bytes in *.
          destruct (dtyp_eq_dec dt DTYPE_Void); try contradiction.
          destruct (N.eq_dec (sizeof_dtyp dt) (N.of_nat (Datatypes.length init_bytes))) eqn:Hlen.
          2 : {
            rewrite MemMonad_run_raise_ub in RUN.
            apply rbm_raise_ret_inv in RUN; try tauto.
            typeclasses eauto.
          }

          { cbn in RUN.
            rewrite MemMonad_run_bind in RUN; auto.
            rewrite MemMonad_get_mem_state in RUN.
            rewrite bind_ret_l in RUN.
            destruct mem_state_fresh_provenance as [pr' ms'] eqn:FRESH.

            rewrite MemMonad_run_bind in RUN; auto.
            rewrite MemMonad_put_mem_state in RUN.
            rewrite bind_ret_l in RUN.

            assert (@MemMonad_valid_state MemState ExtraState Provenance MemM (itree Eff) MM MRun MPROV MSID MMS SIDFRESH PROVFRESH MERR MUB MOOM RunERR RunUB RunOOM H ms' st) as VALID'.
            { (* TODO: ugh, probably need to change something to make sure I know this info *)
              admit.
            }

            pose proof MemMonad_run_fresh_sid ms' st VALID' as [st' [sid [RUN_FRESH_SID [VALID'' FRESH_SID]]]].
            rewrite MemMonad_run_bind in RUN; [| tauto].
            rewrite RUN_FRESH_SID in RUN.
            rewrite bind_ret_l in RUN.

            rewrite MemMonad_run_bind in RUN; [| tauto].
            rewrite MemMonad_get_mem_state in RUN.
            rewrite bind_ret_l in RUN.

            destruct ms as [ms_stack ms_prov].
            destruct ms_stack as [mem frames].

            cbn in RUN.

            inversion FRESH; subst.

            (* TODO: need to know something about get_consecutive_ptrs *)
            unfold get_consecutive_ptrs in *; cbn in RUN.
            do 2 rewrite MemMonad_run_bind in RUN; auto.
            rewrite bind_bind in RUN.
            destruct (intptr_seq 0 (Datatypes.length init_bytes)) as [NOOM_seq | OOM_seq] eqn:HSEQ.
            { (* no oom *)
              cbn in RUN.
              rewrite MemMonad_run_ret in RUN; auto.
              rewrite bind_ret_l in RUN.

              match goal with
              | RUN : context [Util.map_monad ?f ?s] |- _ =>
                  destruct (Util.map_monad f s) as [ERR | ptrs] eqn:HMAPM
              end.

              { (* Error *)
                cbn in RUN.
                rewrite MemMonad_run_raise_error in RUN.
                rewrite rbm_raise_bind in RUN.
                exfalso.
                symmetry in RUN.
                eapply MemMonad_eq1_raise_error_inv in RUN.
                auto.
                typeclasses eauto.
              }

              (* SUCCESS *)
              cbn in RUN.
              rewrite MemMonad_run_ret in RUN; auto.
              rewrite bind_ret_l in RUN.

              rewrite MemMonad_run_bind in RUN; auto.
              rewrite MemMonad_put_mem_state in RUN.
              rewrite bind_ret_l in RUN.
              rewrite MemMonad_run_ret in RUN; auto.
              2: { (* TODO: solve_MemMonad_valid_state *)
                admit.
              }
              cbn in RUN.

              apply eq1_ret_ret in RUN; [|typeclasses eauto].
              inv RUN.
              (* Done extracting information from RUN. *)

              rename ptrs into ptrs_alloced.
              destruct ptrs_alloced as [ _ | alloc_addr ptrs] eqn:HALLOC_PTRS.
              { (* Empty ptr list... Not a contradiction, can allocate 0 bytes... MAY not be unique. *)
                cbn in HMAPM.
                cbn.
                assert (init_bytes = []) as INIT_NIL.
                { destruct init_bytes; auto.
                  cbn in *.
                  rewrite IP.from_Z_0 in HSEQ.
                  destruct (Util.map_monad IP.from_Z (Zseq 1 (Datatypes.length init_bytes))); inv HSEQ.
                  cbn in HMAPM.
                  rewrite handle_gep_addr_0 in HMAPM.
                  break_match_hyp; inv HMAPM.
                }
                subst.
                cbn in *; inv HSEQ.
                cbn in *.

                (* Size is 0, nothing is allocated... *)
                exists ({| ms_memory_stack := (mem, frames); ms_provenance := (next_provenance ms_prov) |}).
                exists (next_provenance ms_prov).

                split; [solve_fresh_provenance_invariants|].

                eexists.
                set (alloc_addr :=
                       int_to_ptr (next_memory_key (mem, frames))
                                  (allocation_id_to_prov (provenance_to_allocation_id (next_provenance ms_prov)))).
                exists (alloc_addr, []).

                split.
                2: {
                  split; eauto.
                }

                { (* TODO: solve_allocate_bytes_succeeds_spec *)
                  split.
                  - (* allocate_bytes_consecutive *)
                    cbn.
                    repeat eexists.
                  - (* allocate_bytes_address_provenance *)
                    subst alloc_addr.
                    apply int_to_ptr_provenance.
                  - (* allocate_bytes_addresses_provenance *)
                    intros ptr IN.
                    inv IN.
                  - (* allocate_bytes_provenances_preserved *)
                    intros pr'0.
                    unfold used_provenance_prop.
                    cbn.
                    reflexivity.
                  - (* allocate_bytes_was_fresh_byte *)
                    intros ptr IN.
                    inv IN.
                  - (* allocate_bytes_now_byte_allocated *)
                    intros ptr IN.
                    inv IN.
                  - (* allocate_bytes_preserves_old_allocations *)
                    intros ptr aid NIN.
                    reflexivity.
                  - (* alloc_bytes_new_reads_allowed *)
                    intros ptr IN.
                    inv IN.
                  - (* alloc_bytes_old_reads_allowed *)
                    intros ptr' DISJOINT.
                    split; auto.
                  - (* alloc_bytes_new_reads *)
                    intros p ix byte NTH1 NTH2.
                    apply Util.not_Nth_nil in NTH1.
                    contradiction.
                  - (* alloc_bytes_old_reads *)
                    intros ptr' byte DISJOINT.
                    split; auto.
                  - (* alloc_bytes_new_writes_allowed *)
                    intros p IN.
                    inv IN.
                  - (* alloc_bytes_old_writes_allowed *)
                    intros ptr' DISJOINT.
                    split; auto.
                  - (* alloc_bytes_add_to_frame *)
                    intros fs1 fs2 POP ADD.
                    cbn in ADD; subst; auto.
                    unfold mem_state_frame_stack_prop in *.
                    cbn in *.
                    rewrite add_all_to_frame_nil_preserves_frames.
                    cbn.
                    rewrite POP.
                    auto.
                  - (* Non-void *)
                    auto.
                  - (* Length *)
                    cbn; auto.
                }
              }

              (* Non-empty allocation *)
              cbn.

              exists ({| ms_memory_stack := (mem, frames); ms_provenance := (next_provenance ms_prov) |}).
              exists (next_provenance ms_prov).

              split; [solve_fresh_provenance_invariants|].

              Open Scope positive.
              exists ({|
    ms_memory_stack :=
              add_all_to_frame
                (add_all_index
                   (map (fun b : SByte => (b, provenance_to_allocation_id (next_provenance ms_prov)))
                      init_bytes) (next_memory_key (mem, frames)) mem, frames)
                (ptr_to_int alloc_addr :: map ptr_to_int ptrs);
    ms_provenance := next_provenance ms_prov
  |}).
              exists (alloc_addr, (alloc_addr :: ptrs)).

              Close Scope positive.
              assert (int_to_ptr
                        (next_memory_key (mem, frames)) (allocation_id_to_prov (provenance_to_allocation_id (next_provenance ms_prov))) = alloc_addr) as EQALLOC.
              {
                destruct (Datatypes.length init_bytes) eqn:LENBYTES.
                { cbn in HSEQ; inv HSEQ.
                  cbn in *.
                  inv HMAPM.
                }

                rewrite intptr_seq_succ in HSEQ.
                cbn in HSEQ.
                rewrite IP.from_Z_0 in HSEQ.
                destruct (intptr_seq 1 n0); inv HSEQ.

                unfold Util.map_monad in HMAPM.
                inversion HMAPM.
                inversion HMAPM.
                break_match_hyp; inv H1.
                break_match_hyp; inv H2.

                rewrite handle_gep_addr_0 in Heqs.
                inv Heqs.
                reflexivity.
              }

              split.
              { (* TODO: solve_allocate_bytes_succeeds_spec *)
                split.
                - (* allocate_bytes_consecutive *)
                  do 2 eexists.
                  split.
                  + cbn.
                    rewrite HSEQ.
                    cbn.
                    split; reflexivity.
                  + rewrite EQALLOC in HMAPM.
                    rewrite HMAPM.
                    cbn.
                    split; reflexivity.
                - (* allocate_bytes_address_provenance *)
                    subst alloc_addr.
                    apply int_to_ptr_provenance.
                - (* allocate_bytes_addressses_provenance *)
                  (* TODO: Need map_monad lemmas *)
                  Set Nested Proofs Allowed.

                  assert (@inr string (list addr) = ret) as INR.
                  reflexivity.
                  rewrite INR in HMAPM.
                  clear INR.

                  intros ptr IN.
                  pose proof map_monad_err_In _ _ _ _ HMAPM IN as MAPIN.
                  destruct MAPIN as [ip [GENPTR INip]].

                  apply handle_gep_addr_preserves_provenance in GENPTR.
                  rewrite int_to_ptr_provenance in GENPTR.
                  auto.
                - (* allocate_bytes_provenances_preserved *)
                  intros pr'0.
                  split; eauto. (* TODO: not sure about eauto here *)
                - (* allocate_bytes_was_fresh_byte *)
                  intros ptr IN.

                  unfold byte_not_allocated.
                  unfold byte_allocated.
                  unfold byte_allocated_MemPropT.
                  intros aid CONTRA.
                  cbn in CONTRA.
                  destruct CONTRA as [ms' [ms'' [[EQ1 EQ2] CONTRA]]]; subst.
                  destruct CONTRA as [ms' [a CONTRA]].
                  destruct CONTRA as [CONTRA [EQ1 EQ2]]; subst.
                  destruct CONTRA as [ms' [ms'' [[EQ1 EQ2] CONTRA]]]; subst.
                  cbn in CONTRA.
                  break_match_hyp.
                  { (* Read succeeds, should be false. *)
                    destruct m.
                    destruct CONTRA as [CONTRA AID].

                    pose proof map_monad_err_In _ _ _ _ HMAPM IN as MAPIN.
                    destruct MAPIN as [ip [GENPTR INip]].

                    apply handle_gep_addr_preserves_provenance in GENPTR.
                    rewrite int_to_ptr_provenance in GENPTR.

                    admit.
                  }

                  destruct CONTRA as [_ CONTRA].
                  inversion CONTRA.
                - (* allocate_bytes_now_byte_allocated *)
                  (* TODO: solve_byte_allocated *)
                  intros ptr IN.

                  (* New bytes are allocated because the exist in the add_all_index block *)
                  pose proof map_monad_err_In _ _ _ _ HMAPM IN as MAPIN.
                  destruct MAPIN as [ip [GENPTR INip]].

                  repeat eexists.
                  cbn.
                  unfold mem_state_memory.
                  cbn.
                  rewrite add_all_to_frame_preserves_memory.
                  cbn.

                  (* TODO: Might be a nicer lemma to write for this *)
                  erewrite read_byte_raw_add_all_index_in. (* v should be some undef_byte with the right index *)
                  break_match.

                  split; auto.
                  + (* Should hold, comes from `a` comes from the map in add_all_index... *)
                    (* May be better to have an existential read_byte_raw_lemma, like map_monad_err_In... *)

                    admit.
                  + (* TODO: need lemma about handle_gep_addr and ptr_to_int

                       also will likely need to know that ip >= 0 from HSEQ.
                     *)
                    admit.
                  + (* TODO: should hold *)
                    admit.
                - (* allocate_bytes_preserves_old_allocations *)
                  intros ptr aid NIN.
                  (* TODO: not enough for ptr to not be in ptrs list. Must be disjoint.

                     E.g., problem if provenances are different.
                   *)

                  split; intros ALLOC.
                  + repeat eexists; cbn; unfold mem_state_memory; cbn.
                    rewrite add_all_to_frame_preserves_memory.
                    cbn.

                    erewrite read_byte_raw_add_all_index_out.
                    2: admit. (* Bounds *)

                    cbn in ALLOC.
                    destruct ALLOC as [ms'' [ms''' [[EQ1 EQ2] ALLOC]]]; subst.
                    destruct ALLOC as [ms'' [a [ALLOC [EQ1 EQ2]]]]; subst.
                    destruct ALLOC as [ms'' [ms''' [[EQ1 EQ2] ALLOC]]]; subst.
                    cbn in ALLOC.

                    break_match; [break_match|]; split; tauto.
                  + cbn in ALLOC.
                    destruct ALLOC as [ms'' [ms''' [[EQ1 EQ2] ALLOC]]]; subst.
                    destruct ALLOC as [ms'' [a [ALLOC [EQ1 EQ2]]]]; subst.
                    destruct ALLOC as [ms'' [ms''' [[EQ1 EQ2] ALLOC]]]; subst.
                    cbn in ALLOC.

                    unfold mem_state_memory in ALLOC; cbn in ALLOC.
                    rewrite add_all_to_frame_preserves_memory in ALLOC; cbn in ALLOC.

                    erewrite read_byte_raw_add_all_index_out in ALLOC.
                    2: admit. (* Bounds *)

                    repeat eexists.
                    cbn.

                    break_match; [break_match|]; split; tauto.
                - (* alloc_bytes_new_reads_allowed *)
                  intros p IN.
                  (* TODO: solve_read_byte_allowed *)
                  induction IN as [IN | IN]; subst.
                  + (* TODO: solve_read_byte_allowed *)
                    eexists.
                    split.
                    * (* TODO: solve_byte_allocated *)
                      repeat eexists.
                      cbn.
                      unfold mem_state_memory.
                      cbn.
                      rewrite add_all_to_frame_preserves_memory.
                      cbn in *.
                      rewrite ptr_to_int_int_to_ptr.

                      match goal with
                      | H: _ |- context [ read_byte_raw (add_all_index ?l ?z ?mem) ?p ] =>
                          pose proof read_byte_raw_add_all_index_in_exists mem l z p as ?READ
                      end.

                      forward READ.
                      admit. (* Should hold... *)

                      destruct READ as [(byte, aid_byte) [NTH READ]].
                      rewrite list_nth_z_map in NTH.
                      unfold option_map in NTH.
                      break_match_hyp; inv NTH.

                      (* Need this unfold for rewrite >_< *)
                      unfold mem_byte in *.
                      rewrite READ.

                      split; auto.
                      apply aid_eq_dec_refl.
                    * solve_access_allowed.
                  + (* TODO: solve_read_byte_allowed *)
                    repeat eexists.
                    cbn.
                    unfold mem_state_memory.
                    cbn.
                    rewrite add_all_to_frame_preserves_memory.
                    cbn in *.
                    rewrite ptr_to_int_int_to_ptr.

                    match goal with
                    | H: _ |- context [ read_byte_raw (add_all_index ?l ?z ?mem) ?p ] =>
                        pose proof read_byte_raw_add_all_index_in_exists mem l z p as ?READ
                    end.

                    forward READ.
                    admit. (* Should hold... *)

                    destruct READ as [(byte, aid_byte) [NTH READ]].
                    rewrite list_nth_z_map in NTH.
                    unfold option_map in NTH.
                    break_match_hyp; inv NTH.

                    (* Need this unfold for rewrite >_< *)
                    unfold mem_byte in *.
                    rewrite READ.

                    split; auto.
                    apply aid_eq_dec_refl.

                    (* Need to look up provenance via IN *)
                    (* TODO: solve_access_allowed *)
                    eapply map_monad_err_In in HMAPM.
                    2: {
                      cbn; right; eauto.
                    }

                    destruct HMAPM as [ip [GENPTR INip]].
                    apply handle_gep_addr_preserves_provenance in GENPTR.
                    rewrite int_to_ptr_provenance in GENPTR.
                    rewrite <- GENPTR.

                    solve_access_allowed.
                - (* alloc_bytes_old_reads_allowed *)
                  intros ptr' DISJOINT.
                  split; intros ALLOWED.
                  + (* TODO: solve_read_byte_allowed. *)
                    break_access_hyps.
                    (* TODO: move this into break_access_hyps? *)
                    destruct ALLOC as [ms'' [ms''' [[EQ1 EQ2] ALLOC]]]; subst.
                    destruct ALLOC as [ms'' [a [ALLOC [EQ1 EQ2]]]]; subst.
                    destruct ALLOC as [ms'' [ms''' [[EQ1 EQ2] ALLOC]]]; subst.
                    cbn in ALLOC.

                    break_match; [break_match|]; destruct ALLOC as [EQM AID]; subst; [|inv AID].

                    repeat eexists.
                    cbn.
                    unfold mem_state_memory.
                    cbn.
                    rewrite add_all_to_frame_preserves_memory.

                    cbn.
                    rewrite read_byte_raw_add_all_index_out.
                    2: {
                      (* lia. *)
                      admit.
                    }
                    rewrite Heqo; eauto.

                    solve_access_allowed.
                  + (* TODO: solve_read_byte_allowed. *)
                    break_access_hyps.
                    (* TODO: move this into break_access_hyps? *)
                    destruct ALLOC as [ms'' [ms''' [[EQ1 EQ2] ALLOC]]]; subst.
                    destruct ALLOC as [ms'' [a [ALLOC [EQ1 EQ2]]]]; subst.
                    destruct ALLOC as [ms'' [ms''' [[EQ1 EQ2] ALLOC]]]; subst.
                    cbn in ALLOC.

                    break_match; [break_match|]; destruct ALLOC as [EQM AID]; subst; [|inv AID].

                    repeat eexists.
                    cbn.
                    unfold mem_state_memory in *.
                    cbn in *.
                    rewrite add_all_to_frame_preserves_memory in Heqo.
                    cbn in *.

                    rewrite read_byte_raw_add_all_index_out in Heqo.
                    2: {
                      (* lia. *)
                      admit.
                    }
                    rewrite Heqo; eauto.

                    solve_access_allowed.
                - (* alloc_bytes_new_reads *)
                  intros p ix byte ADDR BYTE.
                  cbn.
                  repeat eexists.
                  unfold mem_state_memory.
                  cbn.
                  rewrite add_all_to_frame_preserves_memory.
                  cbn.

                  match goal with
                  | H: _ |- context [ read_byte_raw (add_all_index ?l ?z ?mem) ?p ] =>
                      pose proof read_byte_raw_add_all_index_in_exists mem l z p as ?READ
                  end.

                  forward READ.
                  admit. (* bounds *)

                  destruct READ as [(byte', aid_byte) [NTH READ]].
                  rewrite list_nth_z_map in NTH.
                  unfold option_map in NTH.
                  break_match_hyp; inv NTH.

                  (*
                    ADDR tells me that p is in my pointers list at index `ix`...

                    Should be `next_memory_key ms + ix` basically...

                    So, `ptr_to_int p - next_memory_key (mem, frames) = ix`

                    With that BYTE and Heqo should give me byte = byte'
                   *)
                  assert (byte = byte').
                  { pose proof (map_monad_err_Nth _ _ _ _ _ HMAPM ADDR) as [ix' [GENp NTH_ix']].
                    apply handle_gep_addr_ix in GENp.
                    rewrite ptr_to_int_int_to_ptr in GENp.
                    rewrite GENp in Heqo.

                    (* NTH_ix' -> ix = ix' *)
                    (* Heqo + BYTE *)

                    eapply intptr_seq_nth in NTH_ix'; eauto.
                    apply IP.from_Z_to_Z in NTH_ix'.
                    rewrite NTH_ix' in Heqo.

                    rewrite sizeof_dtyp_i8 in Heqo.
                    replace (next_memory_key (mem, frames) + Z.of_N 1 * ( 0 + Z.of_nat ix) - next_memory_key (mem, frames)) with (Z.of_nat ix) in Heqo by lia.

                    apply Util.Nth_list_nth_z in BYTE.
                    rewrite BYTE in Heqo.
                    inv Heqo; auto.
                  }

                  subst.

                  (* Need this unfold for rewrite >_< *)
                  unfold mem_byte in *.
                  rewrite READ.

                  cbn.
                  break_match.
                  split; auto.

                  apply Util.Nth_In in ADDR.
                  pose proof (map_monad_err_In _ _ _ _ HMAPM ADDR) as [ix' [GENp IN_ix']].

                  apply handle_gep_addr_preserves_provenance in GENp.
                  rewrite <- GENp in Heqb.
                  rewrite int_to_ptr_provenance in Heqb.
                  rewrite access_allowed_refl in Heqb.
                  inv Heqb.
                - (* alloc_bytes_old_reads *)
                  intros ptr' byte DISJOINT.
                  split; intros READ.
                  + (* TODO: solve_read_byte_prop *)
                    cbn.
                    repeat eexists.
                    unfold mem_state_memory.
                    cbn.
                    rewrite add_all_to_frame_preserves_memory.
                    cbn.

                    rewrite read_byte_raw_add_all_index_out.

                    2: {
                      (* Bounds *)
                      admit.
                    }

                    (* TODO: ltac to break this up *)
                    destruct READ as [ms' [ms'' [[EQ1 EQ2] READ]]]; subst.
                    cbn in READ.

                    break_match; [break_match|]; auto.
                    tauto.
                  + (* TODO: solve_read_byte_prop *)

                    (* TODO: ltac to break this up *)
                    destruct READ as [ms' [ms'' [[EQ1 EQ2] READ]]]; subst.
                    cbn in READ.
                    unfold mem_state_memory in READ.
                    cbn in READ.
                    rewrite add_all_to_frame_preserves_memory in READ.
                    cbn in READ.

                    rewrite read_byte_raw_add_all_index_out in READ.
                    2: {
                      (* Bounds *)
                      admit.
                    }

                    cbn.
                    repeat eexists.
                    cbn.
                    break_match; [break_match|]; tauto.
                - (* alloc_bytes_new_writes_allowed *)
                  intros p IN.
                  (* TODO: solve_write_byte_allowed. *)
                  break_access_hyps; eexists; split.
                  + (* TODO: solve_byte_allocated *)
                    repeat eexists.
                    unfold mem_state_memory.
                    cbn.
                    rewrite add_all_to_frame_preserves_memory.
                    cbn.

                  match goal with
                  | H: _ |- context [ read_byte_raw (add_all_index ?l ?z ?mem) ?p ] =>
                      pose proof read_byte_raw_add_all_index_in_exists mem l z p as ?READ
                  end.

                  forward READ.
                  admit. (* bounds *)

                  destruct READ as [(byte', aid_byte) [NTH READ]].
                  rewrite list_nth_z_map in NTH.
                  unfold option_map in NTH.
                  break_match_hyp; inv NTH.

                  unfold mem_byte in *.
                  rewrite READ.

                  split; auto.
                  apply aid_eq_dec_refl.
                  + solve_access_allowed.
                - (* alloc_bytes_old_writes_allowed *)
                  intros ptr' DISJOINT.
                  split; intros WRITE.
                  + (* TODO: solve_write_byte_allowed. *)
                    break_access_hyps.

                    (* TODO: move this into break_access_hyps? *)
                    destruct ALLOC as [ms'' [ms''' [[EQ1 EQ2] ALLOC]]]; subst.
                    destruct ALLOC as [ms'' [a [ALLOC [EQ1 EQ2]]]]; subst.
                    destruct ALLOC as [ms'' [ms''' [[EQ1 EQ2] ALLOC]]]; subst.
                    cbn in ALLOC.

                    break_match_hyp; [break_match_hyp|]; destruct ALLOC as [EQ1 EQ2]; inv EQ2.

                    repeat eexists; eauto.
                    cbn.
                    unfold mem_state_memory.
                    cbn.
                    rewrite add_all_to_frame_preserves_memory.
                    cbn.

                    rewrite read_byte_raw_add_all_index_out.
                    2: {
                      (* Bounds *)
                      admit.
                    }

                    rewrite Heqo; cbn; split; eauto.
                  + (* TODO: solve_write_byte_allowed *)
                    break_access_hyps.

                    (* TODO: move this into break_access_hyps? *)
                    destruct ALLOC as [ms'' [ms''' [[EQ1 EQ2] ALLOC]]]; subst.
                    destruct ALLOC as [ms'' [a [ALLOC [EQ1 EQ2]]]]; subst.
                    destruct ALLOC as [ms'' [ms''' [[EQ1 EQ2] ALLOC]]]; subst.
                    cbn in ALLOC.
                    unfold mem_state_memory in ALLOC.
                    cbn in ALLOC.
                    rewrite add_all_to_frame_preserves_memory in ALLOC.
                    cbn in ALLOC.

                    rewrite read_byte_raw_add_all_index_out in ALLOC.
                    2: {
                      (* Bounds *)
                      admit.
                    }

                    break_match; [break_match|].
                    repeat eexists; eauto.
                    cbn.
                    unfold mem_byte in *.
                    rewrite Heqo.
                    tauto.
                    destruct ALLOC as [_ CONTRA]; inv CONTRA.
                - (* alloc_bytes_add_to_frame *)
                  (* Lemma add_to_frame_add_ptr_to_frame_stack : *)
                  (*   forall ptr (ms : memory_stack) (ms' : memory_stack), *)
                  (*     add_to_frame ms (ptr_to_int ptr) = ms' -> *)
                  (*     add_ptr_to_frame_stack (snd ms) ptr (snd ms'). *)
                  (* Proof. *)
                  (*   intros ptr [m fs] [m' fs'] ADD. *)
                  (*   cbn in *. *)
                  (*   red. *)
                  (*   intros f f' fs1_pop PEEK ADDPROP POP. *)
                  (*   destruct fs; inv POP; inv ADD. *)
                  (*   split; cbn; auto. *)

                  (*   (* peek_frame_stack_prop *) *)
                  (*   destruct ADDPROP. *)
                  (*   cbn in *; subst. *)
                  (*   red in new_frame_lu0. *)

                  (*   (* Should this be another lemma? *) *)
                  (*   unfold frame_eqv. *)
                  (*   intros ptr0; split; intros FP; unfold ptr_in_frame_prop in *; cbn in *. *)
                  (*   + destruct (Z.eq_dec (ptr_to_int ptr) (ptr_to_int ptr0)); [tauto | right]. *)
                  (*     apply PEEK. *)
                  (*     apply old_frame_lu0; eauto. *)
                  (*   + destruct (Z.eq_dec (ptr_to_int ptr) (ptr_to_int ptr0)); [congruence|]. *)
                  (*     destruct FP; [contradiction|]. *)
                  (*     apply PEEK in H13. *)
                  (*     eapply old_frame_lu0; eauto. *)
                  (* Qed. *)

                  Lemma add_all_to_frame_nil :
                    forall ms ms',
                      add_all_to_frame ms [] = ms' ->
                      ms = ms'.
                  Proof.
                    (* TODO: move to pre opaque *)
                    Transparent add_all_to_frame.
                    unfold add_all_to_frame.
                    Opaque add_all_to_frame.
                    cbn; eauto.
                  Qed.

                  Lemma add_all_to_frame_cons_inv :
                    forall ptr ptrs ms ms'',
                      add_all_to_frame ms (ptr :: ptrs) = ms'' ->
                      exists ms',
                        add_to_frame ms ptr = ms' /\
                        add_all_to_frame ms' ptrs = ms''.
                  Proof.
                    (* TODO: move to pre opaque *)
                    Transparent add_all_to_frame.
                    unfold add_all_to_frame.
                    Opaque add_all_to_frame.
                    cbn; eauto.
                  Qed.

                  Lemma add_all_to_frame_cons :
                    forall ptr ptrs ms ms' ms'',
                      add_to_frame ms ptr = ms' ->
                      add_all_to_frame ms' ptrs = ms'' ->
                      add_all_to_frame ms (ptr :: ptrs) = ms''.
                  Proof.
                    (* TODO: move to pre opaque *)
                    Transparent add_all_to_frame.
                    unfold add_all_to_frame.
                    Opaque add_all_to_frame.

                    intros ptr ptrs ms ms' ms'' ADD ADD_ALL.
                    cbn; subst; eauto.
                  Qed.

                  Lemma add_ptrs_to_frame_stack_rev :
                    forall ptrs fs fs' fsr',
                      add_ptrs_to_frame_stack fs ptrs fs' ->
                      add_ptrs_to_frame_stack fs (rev ptrs) fsr' ->
                      frame_stack_eqv fs' fsr'.
                  Proof.
                    induction ptrs;
                      intros fs fs' fsr' ADD ADDREV.
                  Abort.

                  Lemma add_ptrs_to_frame_stack_rev_inv :
                    forall ptrs fs fs',
                      add_ptrs_to_frame_stack fs ptrs fs' ->
                      exists fsr', add_ptrs_to_frame_stack fs (rev ptrs) fsr' /\
                                frame_stack_eqv fs' fsr'.
                  Proof.
                  Abort.

                  Lemma add_to_frame_add_all_to_frame :
                    forall ptr ms,
                      add_to_frame ms ptr = add_all_to_frame ms [ptr].
                  Proof.
                    intros ptr ms.
                    erewrite add_all_to_frame_cons.
                    reflexivity.
                    reflexivity.
                    symmetry.
                    apply add_all_to_frame_nil.
                    reflexivity.
                  Qed.

                  Lemma add_to_frame_swap :
                    forall ptr1 ptr2 ms ms1' ms2' ms1'' ms2'',
                      add_to_frame ms ptr1 = ms1' ->
                      add_to_frame ms1' ptr2 = ms1'' ->
                      add_to_frame ms ptr2 = ms2' ->
                      add_to_frame ms2' ptr1 = ms2'' ->
                      frame_stack_eqv (snd ms1'') (snd ms2'').
                  Proof.
                    intros ptr1 ptr2 ms ms1' ms2' ms1'' ms2'' ADD1 ADD1' ADD2 ADD2'.
                    destruct ms, ms1', ms2', ms1'', ms2''.
                    cbn in *.
                    repeat break_match_hyp; subst;
                      inv ADD1; inv ADD1'; inv ADD2; inv ADD2'.

                    - unfold frame_stack_eqv.
                      intros f n.
                      destruct n; cbn; [|tauto].

                      split; intros EQV.
                      + unfold frame_eqv in *; cbn in *.
                        intros ptr; split; firstorder.
                      + unfold frame_eqv in *; cbn in *.
                        intros ptr; split; firstorder.
                    - unfold frame_stack_eqv.
                      intros f n.
                      destruct n; cbn; [|tauto].

                      split; intros EQV.
                      + unfold frame_eqv in *; cbn in *.
                        intros ptr; split; firstorder.
                      + unfold frame_eqv in *; cbn in *.
                        intros ptr; split; firstorder.
                  Qed.

                  (* TODO: move this *)
                  #[global] Instance ptr_in_frame_prop_int_Proper :
                    Proper (frame_eqv ==> (fun a b => ptr_to_int a = ptr_to_int b) ==> iff) ptr_in_frame_prop.
                  Proof.
                    unfold Proper, respectful.
                    intros x y XY a b AB.
                    unfold frame_eqv in *.
                    unfold ptr_in_frame_prop in *.
                    rewrite AB; auto.
                  Qed.

                  #[global] Instance ptr_in_frame_prop_Proper :
                    Proper (frame_eqv ==> eq ==> iff) ptr_in_frame_prop.
                  Proof.
                    unfold Proper, respectful.
                    intros x y XY a b AB; subst.
                    unfold frame_eqv in *.
                    auto.
                  Qed.

                  #[global] Instance frame_stack_eqv_add_ptr_to_frame_Proper :
                    Proper (frame_eqv ==> eq ==> frame_eqv ==> iff) add_ptr_to_frame.
                  Proof.
                    unfold Proper, respectful.
                    intros x y XY ptr ptr' TU r s RS; subst.

                    split; intros ADD.
                    - (* unfold frame_stack_eqv in *. *)
                      (* unfold FSNth_eqv in *. *)
                      inv ADD.
                      split.
                      + intros ptr'0 DISJOINT.
                        split; intros IN.
                        * rewrite <- RS.
                          apply old_frame_lu0; eauto.
                          rewrite XY.
                          auto.
                        * rewrite <- XY.
                          apply old_frame_lu0; eauto.
                          rewrite RS.
                          auto.
                      + rewrite <- RS.
                        auto.
                    - inv ADD.
                      split.
                      + intros ptr'0 DISJOINT.
                        split; intros IN.
                        * rewrite RS.
                          apply old_frame_lu0; eauto.
                          rewrite <- XY.
                          auto.
                        * rewrite XY.
                          apply old_frame_lu0; eauto.
                          rewrite <- RS.
                          auto.
                      + rewrite RS.
                        auto.
                  Qed.

                  #[global] Instance frame_stack_eqv_add_ptr_to_frame_stack_Proper :
                    Proper (frame_stack_eqv ==> eq ==> frame_stack_eqv ==> iff) add_ptr_to_frame_stack.
                  Proof.
                    unfold Proper, respectful.
                    intros x y XY ptr ptr' TU r s RS; subst.

                    split; intros ADD.
                    - (* unfold frame_stack_eqv in *. *)
                      (* unfold FSNth_eqv in *. *)

                      unfold add_ptr_to_frame_stack in ADD.
                      unfold add_ptr_to_frame_stack.
                      intros f PEEK.

                      rewrite <- XY in PEEK.
                      specialize (ADD f PEEK).
                      destruct ADD as [f' [ADD [PEEK' POP]]].
                      eexists.
                      split; eauto.
                      split; [rewrite <- RS; eauto|].

                      intros fs1_pop.
                      rewrite <- XY.
                      rewrite <- RS.
                      auto.
                    - unfold add_ptr_to_frame_stack in ADD.
                      unfold add_ptr_to_frame_stack.
                      intros f PEEK.

                      rewrite XY in PEEK.
                      specialize (ADD f PEEK).
                      destruct ADD as [f' [ADD [PEEK' POP]]].
                      eexists.
                      split; eauto.
                      split; [rewrite RS; eauto|].

                      intros fs1_pop.
                      rewrite XY.
                      rewrite RS.
                      auto.
                  Qed.

                  #[global] Instance frame_stack_eqv_add_ptrs_to_frame_stack_Proper :
                    Proper (frame_stack_eqv ==> eq ==> frame_stack_eqv ==> iff) add_ptrs_to_frame_stack.
                  Proof.
                    unfold Proper, respectful.
                    intros x y XY ptrs ptrs' TU r s RS; subst.

                    split; intros ADD.
                    - revert x y XY r s RS ADD.
                      induction ptrs' as [|a ptrs];
                        intros x y XY r s RS ADD;
                        subst.
                      + cbn in *; subst.
                        rewrite <- XY.
                        rewrite <- RS.
                        auto.
                      + cbn in *.
                        destruct ADD as [fs' [ADDPTRS ADD]].
                        eexists.
                        rewrite <- RS; split; eauto.

                        eapply IHptrs; eauto.
                        reflexivity.
                    - revert x y XY r s RS ADD.
                      induction ptrs' as [|a ptrs];
                        intros x y XY r s RS ADD;
                        subst.
                      + cbn in *; subst.
                        rewrite XY.
                        rewrite RS.
                        auto.
                      + cbn in *.
                        destruct ADD as [fs' [ADDPTRS ADD]].
                        eexists.
                        rewrite RS; split; eauto.

                        eapply IHptrs; eauto.
                        reflexivity.
                  Qed.

                  Lemma add_ptr_to_frame_inv :
                    forall ptr ptr' f f',
                      add_ptr_to_frame f ptr f' ->
                      ptr_in_frame_prop f' ptr' ->
                      ptr_in_frame_prop f ptr' \/ ptr_to_int ptr = ptr_to_int ptr'.
                  Proof.
                    intros ptr ptr' f f' F F'.
                    inv F.
                    pose proof disjoint_ptr_byte_dec ptr ptr' as [DISJOINT | NDISJOINT].
                    - specialize (old_frame_lu0 _ DISJOINT).
                      left.
                      apply old_frame_lu0; auto.
                    - unfold disjoint_ptr_byte in NDISJOINT.
                      assert (ptr_to_int ptr = ptr_to_int ptr') as EQ by lia.
                      right; auto.
                  Qed.

                  Lemma add_ptr_to_frame_eqv :
                    forall ptr f f1 f2,
                      add_ptr_to_frame f ptr f1 ->
                      add_ptr_to_frame f ptr f2 ->
                      frame_eqv f1 f2.
                  Proof.
                    intros ptr f f1 f2 F1 F2.
                    unfold frame_eqv.
                    intros ptr0.
                    split; intros IN.
                    - eapply add_ptr_to_frame_inv in IN; eauto.
                      destruct IN as [IN | IN].
                      + destruct F2.
                        pose proof disjoint_ptr_byte_dec ptr ptr0 as [DISJOINT | NDISJOINT].
                        * eapply old_frame_lu0; eauto.
                        * unfold disjoint_ptr_byte in NDISJOINT.
                          assert (ptr_to_int ptr = ptr_to_int ptr0) as EQ by lia.
                          unfold ptr_in_frame_prop in *.
                          rewrite <- EQ.
                          auto.
                      + destruct F2.
                        unfold ptr_in_frame_prop in *.
                        rewrite <- IN.
                        auto.
                    - eapply add_ptr_to_frame_inv in IN; eauto.
                      destruct IN as [IN | IN].
                      + destruct F1.
                        pose proof disjoint_ptr_byte_dec ptr ptr0 as [DISJOINT | NDISJOINT].
                        * eapply old_frame_lu0; eauto.
                        * unfold disjoint_ptr_byte in NDISJOINT.
                          assert (ptr_to_int ptr = ptr_to_int ptr0) as EQ by lia.
                          unfold ptr_in_frame_prop in *.
                          rewrite <- EQ.
                          auto.
                      + destruct F1.
                        unfold ptr_in_frame_prop in *.
                        rewrite <- IN.
                        auto.
                  Qed.

                  Lemma add_ptr_to_frame_stack_eqv_S :
                    forall ptr f f' fs fs',
                      add_ptr_to_frame_stack (Snoc fs f) ptr (Snoc fs' f') ->
                      add_ptr_to_frame f ptr f' /\ frame_stack_eqv fs fs'.
                  Proof.
                    intros ptr f f' fs fs' ADD.
                    unfold add_ptr_to_frame_stack in *.
                    specialize (ADD f).
                    forward ADD; [cbn; reflexivity|].
                    destruct ADD as [f1 [ADD [PEEK POP]]].
                    cbn in PEEK.
                    split.
                    - rewrite PEEK in ADD; auto.
                    - cbn in POP.
                      specialize (POP fs').
                      apply POP; reflexivity.
                  Qed.

                  Lemma add_ptr_to_frame_stack_eqv :
                    forall ptr fs fs1 fs2,
                      add_ptr_to_frame_stack fs ptr fs1 ->
                      add_ptr_to_frame_stack fs ptr fs2 ->
                      frame_stack_eqv fs1 fs2.
                  Proof.
                    intros ptr fs fs1 fs2 F1 F2.
                    unfold add_ptr_to_frame_stack in *.
                    intros f n.

                    revert ptr f n fs fs2 F1 F2.
                    induction fs1 as [f1 | fs1 IHF1 f1];
                      intros ptr f n fs fs2 F1 F2;
                      destruct fs2 as [f2 | fs2 f2].

                    - cbn. destruct n; [|reflexivity].
                      destruct fs as [f' | fs' f'].
                      + specialize (F1 f').
                        forward F1; [cbn; reflexivity|].
                        destruct F1 as [f1' [ADD1 [PEEK1 POP1]]].

                        specialize (F2 f').
                        forward F2; [cbn; reflexivity|].
                        destruct F2 as [f2' [ADD2 [PEEK2 POP2]]].

                        cbn in *.
                        pose proof (add_ptr_to_frame_eqv _ _ _ _ ADD1 ADD2) as EQV12.

                        rewrite <- PEEK1.
                        rewrite <- PEEK2.
                        rewrite EQV12.
                        reflexivity.
                      + specialize (F1 f').
                        forward F1; [cbn; reflexivity|].
                        destruct F1 as [f1' [ADD1 [PEEK1 POP1]]].

                        specialize (F2 f').
                        forward F2; [cbn; reflexivity|].
                        destruct F2 as [f2' [ADD2 [PEEK2 POP2]]].

                        cbn in *.
                        pose proof (add_ptr_to_frame_eqv _ _ _ _ ADD1 ADD2) as EQV12.

                        rewrite <- PEEK1.
                        rewrite <- PEEK2.
                        rewrite EQV12.
                        reflexivity.
                    - destruct fs as [f' | fs' f'].
                      + specialize (F2 f').
                        forward F2; [cbn; reflexivity|].
                        destruct F2 as [f2' [ADD2 [PEEK2 POP2]]].

                        cbn in *.
                        exfalso; eapply POP2; reflexivity.
                      + specialize (F1 f').
                        forward F1; [cbn; reflexivity|].
                        destruct F1 as [f1' [ADD1 [PEEK1 POP1]]].

                        cbn in *.
                        exfalso; eapply POP1; reflexivity.
                    - destruct fs as [f' | fs' f'].
                      + specialize (F1 f').
                        forward F1; [cbn; reflexivity|].
                        destruct F1 as [f1' [ADD1 [PEEK1 POP1]]].

                        cbn in *.
                        exfalso; eapply POP1; reflexivity.
                      + specialize (F2 f').
                        forward F2; [cbn; reflexivity|].
                        destruct F2 as [f2' [ADD2 [PEEK2 POP2]]].

                        cbn in *.
                        exfalso; eapply POP2; reflexivity.
                    - destruct fs as [f' | fs' f'].
                      + specialize (F1 f').
                        forward F1; [cbn; reflexivity|].
                        destruct F1 as [f1' [ADD1 [PEEK1 POP1]]].

                        cbn in *.
                        exfalso; eapply POP1; reflexivity.
                      + specialize (F1 f').
                        forward F1; [cbn; reflexivity|].
                        destruct F1 as [f1' [ADD1 [PEEK1 POP1]]].

                        specialize (F2 f').
                        forward F2; [cbn; reflexivity|].
                        destruct F2 as [f2' [ADD2 [PEEK2 POP2]]].

                        pose proof (add_ptr_to_frame_eqv _ _ _ _ ADD1 ADD2) as EQV12.

                        cbn in *.
                        destruct n.
                        * rewrite <- PEEK1.
                          rewrite <- PEEK2.
                          rewrite EQV12; reflexivity.
                        * eapply POP1.
                          eapply POP2.
                          reflexivity.
                  Qed.

                  Lemma add_ptrs_to_frame_eqv :
                    forall ptrs fs fs1 fs2,
                      add_ptrs_to_frame_stack fs ptrs fs1 ->
                      add_ptrs_to_frame_stack fs ptrs fs2 ->
                      frame_stack_eqv fs1 fs2.
                  Proof.
                    induction ptrs;
                      intros fs fs1 fs2 ADD1 ADD2.
                    - cbn in *.
                      rewrite <- ADD1, ADD2.
                      reflexivity.
                    - cbn in *.
                      destruct ADD1 as [fs1' [ADDPTRS1 ADD1]].
                      destruct ADD2 as [fs2' [ADDPTRS2 ADD2]].

                      pose proof (IHptrs _ _ _ ADDPTRS1 ADDPTRS2) as EQV.

                      eapply add_ptr_to_frame_stack_eqv; eauto.
                      rewrite EQV.
                      auto.
                  Qed.

                  #[global] Instance frame_stack_eqv_add_all_to_frame :
                    Proper ((fun ms1 ms2 => frame_stack_eqv (snd ms1) (snd ms2)) ==> eq ==> (fun ms1 ms2 => frame_stack_eqv (snd ms1) (snd ms2))) add_all_to_frame.
                  Proof.
                    unfold Proper, respectful.
                    intros ms1 ms2 EQV y x EQ; subst.

                    revert ms1 ms2 EQV.
                    induction x; intros ms1 ms2 EQV.
                    Transparent add_all_to_frame.
                    unfold add_all_to_frame.
                    cbn in *.
                    auto.
                    Opaque add_all_to_frame.
                    
                    assert (add_all_to_frame ms1 (a :: x) = add_all_to_frame ms1 (a :: x)) as EQ by reflexivity.
                    pose proof (@add_all_to_frame_cons_inv _ _ _ _ EQ)
                      as [ms' [ADD ADD_ALL]].

                    assert (add_all_to_frame ms2 (a :: x) = add_all_to_frame ms2 (a :: x)) as EQ2 by reflexivity.
                    pose proof (@add_all_to_frame_cons_inv _ _ _ _ EQ2)
                      as [ms2' [ADD2 ADD_ALL2]].
                    cbn in *.

                    unfold add_to_frame in *.
                    destruct ms1 as [m1 fs1].
                    destruct ms2 as [m2 fs2].

                    subst.

                    cbn in EQV.

                    pose proof (frame_stack_inv _ _ EQV) as [SNOC | SING].
                    - destruct SNOC as [fs1' [fs2' [f1 [f2 [SNOC1 [SNOC2 [SEQV FEQV]]]]]]].
                      subst.

                      rewrite <- ADD_ALL.
                      rewrite <- ADD_ALL2.

                      eapply IHx.
                      cbn.
                      unfold frame_stack_eqv.
                      intros f n.
                      destruct n.
                      + cbn. rewrite FEQV. reflexivity.
                      + cbn. auto.
                    - destruct SING as [f1 [f2 [SING1 [SING2 FEQV]]]].
                      subst.

                      rewrite <- ADD_ALL.
                      rewrite <- ADD_ALL2.

                      eapply IHx.
                      cbn.
                      unfold frame_stack_eqv.
                      intros f n.
                      destruct n.
                      + cbn. rewrite FEQV. reflexivity.
                      + cbn. tauto.
                  Qed.

                  Lemma add_all_to_frame_cons_swap :
                    forall ptrs ptr ms ms1' ms1'' ms2' ms2'',
                      (* Add individual pointer first *)
                      add_to_frame ms ptr = ms1' ->
                      add_all_to_frame ms1' ptrs = ms1'' ->

                      (* Add ptrs first *)
                      add_all_to_frame ms ptrs = ms2' ->
                      add_to_frame ms2' ptr = ms2'' ->

                      frame_stack_eqv (snd ms1'') (snd ms2'').
                  Proof.
                    induction ptrs;
                      intros ptr ms ms1' ms1'' ms2' ms2'' ADD ADD_ALL ADD_ALL' ADD'.

                    rewrite add_to_frame_add_all_to_frame in *.

                    - apply add_all_to_frame_nil in ADD_ALL, ADD_ALL'; subst.
                      reflexivity.
                    - apply add_all_to_frame_cons_inv in ADD_ALL, ADD_ALL'.
                      destruct ADD_ALL as [msx [ADDx ADD_ALLx]].
                      destruct ADD_ALL' as [msy [ADDy ADD_ALLy]].

                      subst.

                      (* ms + ptr + a ++ ptrs *)
                      (* ms + a ++ ptrs + ptr *)

                      (* ptrs ++ (a :: (ptr :: ms))

                         vs

                         ptr :: (ptrs ++ (a :: ms))

                         I have a lemma that's basically...

                         (ptrs ++ (ptr :: ms)) = (ptr :: (ptrs ++ ms))

                         ptr is generic, ptrs is fixed.

                         Can get...

                         ptrs ++ (a :: (ptr :: ms))
                         a :: (ptrs ++ (ptr :: ms))

                         and then

                         ptr :: (ptrs ++ (a :: ms))
                         ptrs ++ (ptr :: (a :: ms))
                         ptrs ++ (a :: (ptr :: ms))
                         a :: (ptrs ++ (ptr :: ms))
                       *)

                      (*
                         ptrs ++ (a :: (ptr :: ms))
                         a :: (ptrs ++ (ptr :: ms))
                       *)

                      assert (frame_stack_eqv
                                (snd (add_all_to_frame (add_to_frame (add_to_frame ms ptr) a) ptrs))
                                (snd (add_to_frame (add_all_to_frame (add_to_frame ms ptr) ptrs) a))) as EQ1.
                      { eauto.
                      }

                      rewrite EQ1.

                      assert (frame_stack_eqv
                                (snd (add_to_frame (add_all_to_frame (add_to_frame ms a) ptrs) ptr))
                                (snd (add_to_frame (add_all_to_frame (add_to_frame ms ptr) ptrs) a))) as EQ2.
                      { assert (frame_stack_eqv
                                  (snd (add_to_frame (add_all_to_frame (add_to_frame ms a) ptrs) ptr))
                                  (snd (add_all_to_frame (add_to_frame (add_to_frame ms a) ptr) ptrs))) as EQ.
                        { symmetry; eauto.
                        }

                        rewrite EQ.
                        clear EQ.

                        assert (frame_stack_eqv
                                  (snd (add_to_frame (add_to_frame ms a) ptr))
                                  (snd (add_to_frame (add_to_frame ms ptr) a))) as EQ.
                        { 
                          eapply add_to_frame_swap; eauto.
                        }

                        epose proof frame_stack_eqv_add_all_to_frame (add_to_frame (add_to_frame ms a) ptr) (add_to_frame (add_to_frame ms ptr) a) as EQ'.
                        forward EQ'. apply EQ.
                        red in EQ'.
                        specialize (EQ' ptrs ptrs eq_refl).
                        rewrite EQ'.

                        eauto.
                      }

                      rewrite EQ2.

                      reflexivity.
                  Qed.

                  (* Lemma add_ptrs_to_frame_swap : *)
                  (*   forall ptrs1 ptrs2 ms ms1' ms1'' ms2' ms2'', *)
                  (*     (* Add ptrs1 first *) *)
                  (*     add_all_to_frame ms ptrs1 = ms1' -> *)
                  (*     add_all_to_frame ms1' ptrs2 = ms1'' -> *)

                  (*     (* Add ptrs2 first *) *)
                  (*     add_all_to_frame ms ptrs2 = ms2' -> *)
                  (*     add_all_to_frame ms2' ptrs1 = ms2'' -> *)

                  (*     frame_stack_eqv (snd ms1'') (snd ms2''). *)
                  (* Proof. *)
                  (*   induction ptrs1; *)
                  (*     intros ptrs2 ms ms1' ms1'' ms2' ms2'' ADD1 ADD2 ADD3 ADD4. *)

                  (*   - apply add_all_to_frame_nil in ADD1, ADD4; subst. *)
                  (*     reflexivity. *)
                  (*   - apply add_all_to_frame_cons_inv in ADD1, ADD4. *)
                  (*     destruct ADD1 as [msx [ADDx ADD_ALLx]]. *)
                  (*     destruct ADD4 as [msy [ADDy ADD_ALLy]]. *)

                  (*     revert ptrs2 ms ms1' ms1'' ms2' ms2'' ADDx ADD_ALLx ADD2 ADD3 ADDy ADD_ALLy. *)
                  (*     induction ptrs2; *)
                  (*       intros ms ms1' ms1'' ms2' ms2'' ADDx ADD_ALLx ADD2 ADD3 ADDy ADD_ALLy. *)

                  (*     + apply add_all_to_frame_nil in ADD2, ADD3; subst. *)
                  (*       reflexivity. *)
                  (*     + apply add_all_to_frame_cons_inv in ADD2, ADD3. *)
                  (*       destruct ADD2 as [msz [ADDz ADD_ALLz]]. *)
                  (*       destruct ADD3 as [msw [ADDw ADD_ALLw]]. *)

                  (*       subst. *)

                  (*     epose proof (IHptrs1 _ _ _ _ _ _ ADD_ALLx ADD2). *)
                  (*     subst. *)
                  (*     reflexivity. *)
                  (* Qed. *)

                  Lemma add_to_frame_correct :
                    forall ptr (ms ms' : memory_stack),
                      add_to_frame ms (ptr_to_int ptr) = ms' ->
                      add_ptr_to_frame_stack (snd ms) ptr (snd ms').
                  Proof.
                    intros ptr ms ms' ADD.
                    unfold add_ptr_to_frame_stack.
                    intros f PEEK.
                    exists (ptr_to_int ptr :: f).
                    split; [|split].
                    - (* add_ptr_to_frame *)
                      split.
                      + intros ptr' DISJOINT.
                        split; intros IN; cbn; auto.

                        destruct IN as [IN | IN];
                          [contradiction | auto].
                      + cbn; auto.
                    - (* peek_frame_stack_prop *)
                      destruct ms as [m fs].
                      destruct ms' as [m' fs'].
                      cbn in *.

                      break_match_hyp; inv ADD;
                      cbn in *; rewrite PEEK; reflexivity.
                    - (* pop_frame_stack_prop *)
                      destruct ms as [m fs].
                      destruct ms' as [m' fs'].
                      cbn in *.

                      break_match_hyp; inv ADD.
                      + intros fs1_pop; split; intros POP; inv POP.
                      + intros fs1_pop; split; intros POP; cbn in *; auto.
                  Qed.

                  Lemma add_all_to_frame_correct :
                    forall ptrs (ms : memory_stack) (ms' : memory_stack),
                      add_all_to_frame ms (map ptr_to_int ptrs) = ms' ->
                      add_ptrs_to_frame_stack (snd ms) ptrs (snd ms').
                  Proof.
                    induction ptrs;
                      intros ms ms' ADD_ALL.
                    - cbn in *.
                      apply add_all_to_frame_nil in ADD_ALL; subst; auto.
                      reflexivity.
                    - cbn in *.
                      eexists.
                      split.
                      + eapply IHptrs.
                        reflexivity.
                      + destruct ms as [m fs].
                        destruct ms' as [m' fs'].
                        cbn.

                        apply add_all_to_frame_cons_inv in ADD_ALL.
                        destruct ADD_ALL as [ms' [ADD ADD_ALL]].

                        destruct (add_all_to_frame (m, fs) (map ptr_to_int ptrs)) eqn:ADD_ALL'.
                        cbn.

                        assert (add_to_frame (m0, f) (ptr_to_int a) = add_to_frame (m0, f) (ptr_to_int a)) as ADD' by reflexivity.
                        pose proof (add_all_to_frame_cons_swap _ _ _ _ _ _ _ ADD ADD_ALL ADD_ALL' ADD') as EQV.
                        cbn in EQV.
                        rewrite EQV.
                        destruct f.
                        * replace (Singleton f) with (snd (m0, Singleton f)) by reflexivity.
                          eapply add_to_frame_correct.
                          reflexivity.
                        * replace (Snoc f f0) with (snd (m0, Snoc f f0)) by reflexivity.
                          eapply add_to_frame_correct.
                          reflexivity.
                  Qed.

                  intros fs1 fs2 OLDFS ADD.
                  unfold mem_state_frame_stack_prop in *.
                  cbn in OLDFS; subst.
                  cbn.

                  rewrite <- map_cons.

                  match goal with
                  | H: _ |- context [ add_all_to_frame ?ms (map ptr_to_int ?ptrs) ] =>
                      pose proof (add_all_to_frame_correct ptrs ms (add_all_to_frame ms (map ptr_to_int ptrs))) as ADDPTRS
                  end.

                  forward ADDPTRS; [reflexivity|].

                  eapply add_ptrs_to_frame_eqv; eauto.
                  rewrite <- OLDFS in ADD.
                  auto.
                - (* non-void *)
                  auto.
                - (* Length of init bytes matches up *)
                  cbn; auto.
              }
              { split.
                reflexivity.
                auto.
              }
            }

            { (* OOM *)
              cbn in RUN.
              rewrite MemMonad_run_raise_oom in RUN.
              rewrite rbm_raise_bind in RUN.
              exfalso.
              symmetry in RUN.
              eapply MemMonad_eq1_raise_oom_inv in RUN.
              auto.
              typeclasses eauto.
            }
          }
      }

      Unshelve.
      all: try exact ""%string.
    Qed.

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
          mem_state_frame_stack_prop initial_memory_state fs ->
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

End FiniteMemoryModelExecPrimitives.

Module MakeFiniteMemoryModelSpec (LP : LLVMParams) (MP : MemoryParams LP).
  Module FMSP := FiniteMemoryModelSpecPrimitives LP MP.
  Module FMS := MakeMemoryModelSpec LP MP FMSP.

  Export FMSP FMS.
End MakeFiniteMemoryModelSpec.

Module MakeFiniteMemoryModelExec (LP : LLVMParams) (MP : MemoryParams LP).
  Module FMEP := FiniteMemoryModelExecPrimitives LP MP.
  Module FME := MakeMemoryModelExec LP MP FMEP.
End MakeFiniteMemoryModelExec.

Module MakeFiniteMemory (LP : LLVMParams) : Memory LP.
  Import LP.

  Module GEP := GepM.Make ADDR IP SIZEOF Events PTOI PROV ITOP.
  Module Byte := FinByte ADDR IP SIZEOF Events.

  Module MP := MemoryParams.Make LP GEP Byte.

  Module MMEP := FiniteMemoryModelExecPrimitives LP MP.
  Module MEM_MODEL := MakeMemoryModelExec LP MP MMEP.
  Module MEM_SPEC_INTERP := MakeMemorySpecInterpreter LP MP MMEP.MMSP MMEP.MemSpec.
  Module MEM_EXEC_INTERP := MakeMemoryExecInterpreter LP MP MMEP MEM_MODEL MEM_SPEC_INTERP.

  (* Serialization *)
  Module SP := SerializationParams.Make LP MP.

  Export GEP Byte MP MEM_MODEL SP.
End MakeFiniteMemory.

Module LLVMParamsBigIntptr := LLVMParams.MakeBig Addr BigIP FinSizeof FinPTOI FinPROV FinITOP BigIP_BIG.
Module LLVMParams64BitIntptr := LLVMParams.Make Addr IP64Bit FinSizeof FinPTOI FinPROV FinITOP.

Module MemoryBigIntptr := MakeFiniteMemory LLVMParamsBigIntptr.
Module Memory64BitIntptr := MakeFiniteMemory LLVMParams64BitIntptr.
