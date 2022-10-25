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
     MemPropT
     MemoryInterpreters.

From Vellvm.Utils Require Import
     Util
     Error
     PropT
     Tactics
     IntMaps
     Monads
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
     MemoryModel.

From Vellvm.Handlers.MemoryModules Require Import
     FiniteAddresses
     FiniteIntptr
     FiniteSizeof
     FiniteSpecPrimitives
     FiniteExecPrimitives
     Within.



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

Module Addr := FiniteAddresses.Addr.
Module IP64Bit := FiniteIntptr.IP64Bit.
Module BigIP := FiniteIntptr.BigIP.
Module FinSizeof := FiniteSizeof.FinSizeof.

Module MakeFiniteMemoryModelSpec (LP : LLVMParams) (MP : MemoryParams LP).
  Module FMSP := FiniteMemoryModelSpecPrimitives LP MP.
  Module FMS := MakeMemoryModelSpec LP MP FMSP.

  Export FMSP FMS.
End MakeFiniteMemoryModelSpec.

Module MakeFiniteMemoryModelExec (LP : LLVMParams) (MP : MemoryParams LP).
  Module FMEP := FiniteMemoryModelExecPrimitives LP MP.
  Module FME := MakeMemoryModelExec LP MP FMEP.
End MakeFiniteMemoryModelExec.

Module MakeFiniteMemory (LP : LLVMParams) <: Memory LP.
  Import LP.

  Module GEP := GepM.Make ADDR IP SIZEOF Events PTOI PROV ITOP.
  Module Byte := FinByte ADDR IP SIZEOF Events.

  Module MP := MemoryParams.Make LP GEP Byte.

  Module MMEP := FiniteMemoryModelExecPrimitives LP MP.
  Module MEM_MODEL := MakeMemoryModelExec LP MP MMEP.
  Module MEM_SPEC_INTERP := MakeMemorySpecInterpreter LP MP MMEP.MMSP MMEP.MemSpec MMEP.MemExecM.
  Module MEM_EXEC_INTERP := MakeMemoryExecInterpreter LP MP MMEP MEM_MODEL MEM_SPEC_INTERP.

  (* Concretization *)
  Module CP := ConcretizationParams.Make LP MP.

  Export GEP Byte MP MEM_MODEL CP.
End MakeFiniteMemory.

Module LLVMParamsBigIntptr := LLVMParams.MakeBig Addr BigIP FinSizeof FinPTOI FinPROV FinITOP BigIP_BIG.
Module LLVMParams64BitIntptr := LLVMParams.Make Addr IP64Bit FinSizeof FinPTOI FinPROV FinITOP.

Module MemoryBigIntptr := MakeFiniteMemory LLVMParamsBigIntptr.
Module Memory64BitIntptr := MakeFiniteMemory LLVMParams64BitIntptr.


Module MemoryBigIntptrInfiniteSpec <: MemoryModelInfiniteSpec LLVMParamsBigIntptr MemoryBigIntptr.MP MemoryBigIntptr.MMEP.MMSP MemoryBigIntptr.MMEP.MemSpec.
  (* Intptrs are "big" *)
  Module LP := LLVMParamsBigIntptr.
  Module MP := MemoryBigIntptr.MP.

  Module MMSP := MemoryBigIntptr.MMEP.MMSP.
  Module MMS := MemoryBigIntptr.MMEP.MemSpec.
  Module MME := MemoryBigIntptr.MEM_MODEL.

  Import LP.Events.
  Import LP.ITOP.
  Import LP.PTOI.
  Import LP.IP_BIG.
  Import LP.IP.
  Import LP.ADDR.
  Import LP.PROV.
  Import LP.SIZEOF.

  Import MMSP.
  Import MMS.
  Import MemHelpers.

  Import Monad.
  Import MapMonadExtra.
  Import MP.GEP.

  Module MSIH := MemStateInfiniteHelpers LP MP MMSP MMS.
  Import MSIH.

  Import MemoryBigIntptr.
  Import MMEP.
  Import MP.BYTE_IMPL.
  Import MemExecM.

  Module MemTheory  := MemoryModelTheory LP MP MMEP MME.
  Import MemTheory.

  Module SpecInterp := MakeMemorySpecInterpreter LP MP MMSP MMS MemExecM.
  Module ExecInterp := MakeMemoryExecInterpreter LP MP MMEP MME SpecInterp.
  Import SpecInterp.
  Import ExecInterp.

  Definition Eff := FailureE +' OOME +' UBE.

  Import Eq.
  Import MMSP.

  (* TODO: Move out of infinite stuff *)
  Lemma find_free_block_never_ub :
    forall sz prov msg,
      raise_ub msg ∉ find_free_block sz prov.
  Proof.
    intros sz prov msg FREE.
    destruct FREE as [ms [ms' FREE]].
    cbn in FREE; auto.
  Qed.

  (* TODO: Move out of infinite stuff *)
  Lemma find_free_block_never_err :
    forall sz prov msg,
      raise_error msg ∉ find_free_block sz prov.
  Proof.
    intros sz prov msg FREE.
    destruct FREE as [ms [ms' FREE]].
    cbn in FREE.
    auto.
  Qed.

  Import MemSpec.MemHelpers.
  Import LLVMParamsBigIntptr.
  Import PROV.

  Lemma find_free_block_can_always_succeed :
    forall ms (len : nat) (pr : Provenance),
    exists ptr ptrs,
      ret (ptr, ptrs) {{ms}} ∈ {{ms}} find_free_block len pr.
  Proof.
    intros ms len pr.
    pose proof (find_free_block_correct len pr (fun _ _ => True) (Eff := Eff) (MemM:=MemStateFreshT (itree Eff))) as GET_FREE.
    red in GET_FREE.
    specialize (GET_FREE ms 0%N).
    forward GET_FREE.
    { (* TODO:

         May not be true, but should be able to find an st where it is
         true... At least when `ms` is finite. *)
      admit.
    }

    specialize (GET_FREE I).
    destruct GET_FREE as [UB | GET_FREE].

    { (* UB in find_free_block *)
      firstorder.
    }

    (* find_free_block doesn't necessarily UB *)
    destruct GET_FREE as [res [st' [ms' [GET_FREE [FIND_FREE POST_FREE]]]]].

    cbn in *.
    red in GET_FREE.
    destruct GET_FREE as [tptrs [IN REST]].
    cbn in *.

    pose proof big_intptr_seq_succeeds 0 len as [seq SEQ].
    rewrite SEQ in REST.
    cbn in REST.
    red in REST.

    destruct ms; cbn in *.
    destruct ms_memory_stack0; cbn in *.

    repeat rewrite bind_ret_l in REST.
    cbn in REST.

    repeat rewrite bind_ret_l in REST.
    cbn in REST.

    destruct_err_ub_oom res.

    { (* OOM *)
      exfalso.
      cbn in *.
      destruct IN as [oom_msg TPTRS].
      rewrite TPTRS in REST.
      setoid_rewrite (@rbm_raise_bind _ _ _ _ _ (RaiseBindM_OOM _)) in REST.

      destruct (map_monad
                  (fun ix : LLVMParamsBigIntptr.IP.intptr =>
                     GEP.handle_gep_addr (DTYPE_I 8)
                       (LLVMParamsBigIntptr.ITOP.int_to_ptr
                          (next_memory_key
                             {|
                               MemoryBigIntptrInfiniteSpec.MMSP.memory_stack_memory :=
                                 memory_stack_memory0;
                               MemoryBigIntptrInfiniteSpec.MMSP.memory_stack_frame_stack :=
                                 memory_stack_frame_stack0;
                               MemoryBigIntptrInfiniteSpec.MMSP.memory_stack_heap :=
                                 memory_stack_heap0
                             |})
                          (LLVMParamsBigIntptr.PROV.allocation_id_to_prov
                             (LLVMParamsBigIntptr.PROV.provenance_to_allocation_id pr)))
                       [LLVMParamsBigIntptr.Events.DV.DVALUE_IPTR ix]) seq) eqn:HMAPM.

      { (* Error, should be contradiction *)
        cbn in REST.
        repeat setoid_rewrite (@rbm_raise_bind _ _ _ _ _ (RaiseBindM_Fail _)) in REST.
        unfold raiseOOM in REST.
        unfold LLVMEvents.raise in REST.
        admit.
      }

      cbn in REST.
      setoid_rewrite bind_ret_l in REST.
      rewrite map_ret in REST.
      cbn in REST.
      symmetry in REST.
      apply raiseOOM_ret_inv_itree in REST.
      auto.
    }

    { (* UB *)
      cbn in *.
      contradiction.
    }

    { (* Error *)
      cbn in *.
      contradiction.
    }

    { (* Success *)
      cbn in *.
      destruct res0 as [ptr ptrs].
      exists ptr. exists ptrs.
      rewrite IN in REST.

      destruct (map_monad
                  (fun ix : LLVMParamsBigIntptr.IP.intptr =>
                     GEP.handle_gep_addr (DTYPE_I 8)
                       (LLVMParamsBigIntptr.ITOP.int_to_ptr
                          (next_memory_key
                             {|
                               MemoryBigIntptrInfiniteSpec.MMSP.memory_stack_memory :=
                                 memory_stack_memory0;
                               MemoryBigIntptrInfiniteSpec.MMSP.memory_stack_frame_stack :=
                                 memory_stack_frame_stack0;
                               MemoryBigIntptrInfiniteSpec.MMSP.memory_stack_heap :=
                                 memory_stack_heap0
                             |})
                          (LLVMParamsBigIntptr.PROV.allocation_id_to_prov
                             (LLVMParamsBigIntptr.PROV.provenance_to_allocation_id pr)))
                       [LLVMParamsBigIntptr.Events.DV.DVALUE_IPTR ix]) seq) eqn:HMAPM.

      { (* Error, should be contradiction *)
        cbn in REST.
        repeat setoid_rewrite (@rbm_raise_bind _ _ _ _ _ (RaiseBindM_Fail _)) in REST.
        unfold raiseOOM in REST.
        unfold LLVMEvents.raise in REST.
        exfalso.
        admit.
      }

      tauto.
    }
  Admitted.

  Lemma allocate_bytes_post_conditions_can_always_be_satisfied :
    forall (ms_init : MemState) dt bytes pr ptr ptrs
      (FIND_FREE : ret (ptr, ptrs) {{ms_init}} ∈ {{ms_init}} find_free_block (length bytes) pr)
      (BYTES_SIZE : sizeof_dtyp dt = N.of_nat (length bytes))
      (NON_VOID : dt <> DTYPE_Void),
    exists ms_final,
      allocate_bytes_post_conditions ms_init dt bytes pr ms_final ptr ptrs.
  Proof.
    intros ms_init dt bytes pr ptr ptrs FIND_FREE BYTES_SIZE NON_VOID.

    (* Memory state pre allocation *)
    destruct ms_init as [mstack mprov] eqn:MSINIT.
    destruct mstack as [mem fs h] eqn:MSTACK.

    pose proof (allocate_bytes_with_pr_correct dt bytes pr (fun _ _ => True) (Eff := Eff) (MemM:=MemStateFreshT (itree Eff))) as ALLOC.
    red in ALLOC.
    specialize (ALLOC ms_init 0%N).
    forward ALLOC.
    { (* TODO:

         May not be true, but should be able to find an st where it is
         true... At least when `ms` is finite. *)
      admit.
    }

    specialize (ALLOC I).

    destruct ALLOC as [UB | ALLOC].

    { (* UB *)
      cbn in UB.
      destruct UB as [ub_ms [ub_msg [CONTRA | REST]]]; try contradiction.
      destruct REST as [ms'' [[ptr' ptrs'] [[MEQ FREE] [[VOID_UB | SIZE_UB] | REST]]]];
        firstorder.
    }

    (* allocate_bytes doesn't necessarily UB *)
    destruct ALLOC as [res [st' [ms' [ALLOC_EXEC [ALLOC_SPEC POST_ALLOC]]]]].

    cbn in ALLOC_EXEC.
    red in ALLOC_EXEC.
    destruct ALLOC_EXEC as [t_alloc [RES_T_ALLOC ALLOC_EXEC]].

    repeat setoid_rewrite bind_ret_l in ALLOC_EXEC.
    cbn in ALLOC_EXEC.
    red in ALLOC_EXEC.

    repeat setoid_rewrite bind_ret_l in ALLOC_EXEC.
    cbn in ALLOC_EXEC.

    pose proof big_intptr_seq_succeeds 0 (Datatypes.length bytes) as [seq SEQ].
    rewrite SEQ in ALLOC_EXEC.
    cbn in ALLOC_EXEC.

    repeat setoid_rewrite bind_ret_l in ALLOC_EXEC.
    cbn in ALLOC_EXEC.

    rewrite MSINIT in ALLOC_EXEC.
    cbn in ALLOC_EXEC.
    repeat setoid_rewrite bind_ret_l in ALLOC_EXEC.
    cbn in ALLOC_EXEC.

    destruct (map_monad
                (fun ix : IP.intptr =>
                   GEP.handle_gep_addr (DTYPE_I 8)
                     (ITOP.int_to_ptr
                        (next_memory_key
                           {|
                             MemoryBigIntptrInfiniteSpec.MMSP.memory_stack_memory := mem;
                             MemoryBigIntptrInfiniteSpec.MMSP.memory_stack_frame_stack :=
                               fs;
                             MemoryBigIntptrInfiniteSpec.MMSP.memory_stack_heap := h
                           |}) (allocation_id_to_prov (provenance_to_allocation_id pr)))
                     [Events.DV.DVALUE_IPTR ix]) seq) eqn:HMAPM.

    { (* Error *)
      cbn in ALLOC_EXEC.
      repeat setoid_rewrite (@rbm_raise_bind _ _ _ _ _ (RaiseBindM_Fail _)) in ALLOC_EXEC.

      destruct_err_ub_oom res.
      - (* OOM *)
        cbn in RES_T_ALLOC.
        destruct RES_T_ALLOC as [oom_msg RES_T_ALLOC].
        rewrite RES_T_ALLOC in ALLOC_EXEC.
        setoid_rewrite (@rbm_raise_bind _ _ _ _ _ (RaiseBindM_OOM _)) in ALLOC_EXEC.
        (* TODO: Contradiction in ALLOC_EXEC *)
        admit.
      - (* UB *)
        cbn in RES_T_ALLOC.
        destruct RES_T_ALLOC as [ub_msg RES_T_ALLOC].
        rewrite RES_T_ALLOC in ALLOC_EXEC.
        setoid_rewrite (@rbm_raise_bind _ _ _ _ _ (RaiseBindM_UB _)) in ALLOC_EXEC.
        (* TODO: Contradiction in ALLOC_EXEC *)
        admit.
      - (* Error *)
        exfalso.
        clear - ALLOC_SPEC.
        cbn in ALLOC_SPEC.
        destruct ALLOC_SPEC as [UB | REST]; [contradiction|].
        destruct REST as [ms''' [[ptr' ptrs'] [[MEQ FREE] [UB | REST]]]];
          firstorder.
      - (* Success *)
        cbn in RES_T_ALLOC.
        rewrite RES_T_ALLOC in ALLOC_EXEC.
        rewrite bind_ret_l in ALLOC_EXEC.
        eapply raise_ret_inv_itree in ALLOC_EXEC.
        contradiction.
    }

    { (* Success *)
      repeat setoid_rewrite bind_ret_l in ALLOC_EXEC.
      cbn in ALLOC_EXEC.
      repeat setoid_rewrite bind_ret_l in ALLOC_EXEC.
      break_match_hyp; [contradiction|].
      break_match_hyp; [|contradiction].
      repeat rewrite bind_ret_l in ALLOC_EXEC.
      cbn in ALLOC_EXEC.
      repeat rewrite bind_ret_l in ALLOC_EXEC.
      cbn in ALLOC_EXEC.

      rewrite map_ret in ALLOC_EXEC.

      destruct_err_ub_oom res.
      - (* OOM *)
        cbn in RES_T_ALLOC.
        destruct RES_T_ALLOC as [oom_msg RES_T_ALLOC].
        rewrite RES_T_ALLOC in ALLOC_EXEC.
        setoid_rewrite (@rbm_raise_bind _ _ _ _ _ (RaiseBindM_OOM _)) in ALLOC_EXEC.
        symmetry in ALLOC_EXEC.
        eapply raiseOOM_ret_inv_itree in ALLOC_EXEC; contradiction.
      - (* UB *)
        cbn in RES_T_ALLOC.
        destruct RES_T_ALLOC as [ub_msg RES_T_ALLOC].
        rewrite RES_T_ALLOC in ALLOC_EXEC.
        setoid_rewrite (@rbm_raise_bind _ _ _ _ _ (RaiseBindM_UB _)) in ALLOC_EXEC.
        symmetry in ALLOC_EXEC.
        eapply raiseUB_ret_inv_itree in ALLOC_EXEC; contradiction.
      - (* Error *)
        exfalso.
        clear - ALLOC_SPEC.
        cbn in ALLOC_SPEC.
        destruct ALLOC_SPEC as [UB | REST]; [contradiction|].
        destruct REST as [ms''' [[ptr' ptrs'] [[MEQ FREE] [UB | REST]]]];
          firstorder.
      - (* Success *)
        cbn in RES_T_ALLOC.
        rewrite RES_T_ALLOC in ALLOC_EXEC.
        rewrite bind_ret_l in ALLOC_EXEC.

        epose proof (@eq1_ret_ret (itree Eff) _ _ _ _ _ _ ALLOC_EXEC) as RETINV.
        inv RETINV.

        cbn in ALLOC_SPEC.
        exists {|
            MemoryBigIntptrInfiniteSpec.MMSP.ms_memory_stack :=
              add_all_to_frame
                {|
                  MemoryBigIntptrInfiniteSpec.MMSP.memory_stack_memory :=
                    add_all_index
                      (map (fun b : SByte => (b, provenance_to_allocation_id pr)) bytes)
                      (PTOI.ptr_to_int
                         (ITOP.int_to_ptr
                            (next_memory_key
                               {|
                                 MemoryBigIntptrInfiniteSpec.MMSP.memory_stack_memory := mem;
                                 MemoryBigIntptrInfiniteSpec.MMSP.memory_stack_frame_stack :=
                                   fs;
                                 MemoryBigIntptrInfiniteSpec.MMSP.memory_stack_heap := h
                               |}) (allocation_id_to_prov (provenance_to_allocation_id pr))))
                      mem;
                  MemoryBigIntptrInfiniteSpec.MMSP.memory_stack_frame_stack := fs;
                  MemoryBigIntptrInfiniteSpec.MMSP.memory_stack_heap := h
                |} (map PTOI.ptr_to_int l);
            MemoryBigIntptrInfiniteSpec.MMSP.ms_provenance := mprov
          |}.

        cbn in ALLOC_SPEC.
        destruct ALLOC_SPEC as [ms_final' [[ptr'' ptrs''] [[MEQ BLOCK_FREE_SPEC] ALLOC_SPEC]]].
        subst ms_final'.
        destruct ALLOC_SPEC as [ms_final' [[ptr''' ptrs'''] [[BYTES_POST [PTREQ PTRSEQ]] [MEQ ALLOC_SPEC]]]].
        subst ms_final' ptr'' ptr''' ptrs'''.

        subst.
        destruct BYTES_POST.
        cbn in FIND_FREE.
        destruct FIND_FREE as [_ BLOCK_FREE].
        clear RES_T_ALLOC n e.
        split; eauto.
        + admit.
        + admit.
        + admit.
        + admit.
        + admit.
    }
  Admitted.

  Section MemoryPrimitives.
    Context {MemM : Type -> Type}.
    Context {Eff : Type -> Type}.
    (* Context `{Monad MemM}. *)
    (* Context `{MonadProvenance Provenance MemM}. *)
    (* Context `{MonadStoreID MemM}. *)
    (* Context `{MonadMemState MemState MemM}. *)
    (* Context `{RAISE_ERROR MemM} `{RAISE_UB MemM} `{RAISE_OOM MemM}. *)
    Context {ExtraState : Type}.
    Context `{MemMonad ExtraState MemM (itree Eff)}.

    (* Lemma find_free_block_always_succeeds : *)
    (*   forall sz prov ms (st : ExtraState), *)
    (*   exists ptr ptrs, *)
    (*     find_free_block sz prov ms (ret (ptr, ptrs)). *)
    (* Proof. *)
    (*   intros sz prov ms st. *)
    (*   pose proof (find_free_block_correct sz prov (fun _ _ => True)) as GET_FREE. *)
    (*   unfold exec_correct in GET_FREE. *)
    (*   specialize (GET_FREE ms st). *)
    (*   forward GET_FREE. admit. *)
    (*   forward GET_FREE; auto. *)

    (*   destruct GET_FREE as [[ub_msg UB] | GET_FREE]. *)
    (*   apply find_free_block_never_ub in UB; inv UB. *)

    (*   destruct GET_FREE as [ERR | [OOM | RET]]. *)
    (*   - destruct ERR as [err_msg [RUN [err_msg_spec ERR]]]. *)
    (*     eapply find_free_block_never_err in ERR; inv ERR. *)
    (*   - cbn in *. *)
    (*     destruct OOM as [oom_msg [RUN _]]. *)
    (*     unfold get_free_block in RUN. *)
    (* Qed. *)

    (* Lemma allocate_bytes_post_conditions_can_always_be_satisfied : *)
    (*   forall (ms_init ms_fresh_pr : MemState) dt bytes pr ptr ptrs *)
    (*     (FRESH_PR : (@fresh_provenance Provenance (MemPropT MemState) _ ms_init (ret (ms_fresh_pr, pr)))) *)
    (*     (FIND_FREE : find_free_block (length bytes) pr ms_fresh_pr (ret (ms_fresh_pr, (ptr, ptrs)))) *)
    (*     (BYTES_SIZE : sizeof_dtyp dt = N.of_nat (length bytes)) *)
    (*     (NON_VOID : dt <> DTYPE_Void), *)
    (*   exists ms_final, *)
    (*     allocate_bytes_post_conditions ms_fresh_pr dt bytes pr ms_final ptr ptrs. *)
    (* Proof. *)
    (*   intros ms_init ms_fresh_pr dt bytes pr ptr ptrs FRESH_PR FIND_FREE BYTES_SIZE NON_VOID. *)

    (*   destruct ms_fresh_pr as [[mem fs h] pr'] eqn:HMS.       *)

    (*   pose proof (allocate_bytes_correct dt bytes (fun _ _ => True) ms_init) as CORRECT. *)
    (*   unfold exec_correct in CORRECT. *)
    (*   assert (ExtraState) as st by admit. *)
    (*   specialize (CORRECT st). *)
    (*   forward CORRECT. admit. *)
    (*   forward CORRECT; auto. *)

    (*   destruct CORRECT as [[ubmsg UB] | CORRECT]. *)
    (*   { cbn in UB. *)
    (*     destruct UB as [UB | UB]; [inv UB|]. *)
    (*     destruct UB as [ms [pr' [FRESH UB]]]. *)
    (*     destruct UB as [UB | UB]; [inv UB|]. *)
    (*     destruct UB as [ms' [[ptr' ptrs'] [[EQ FREE] UB]]]. *)
    (*     subst. *)
    (*     destruct UB as [[UB | UB] | UB]; try contradiction. *)
    (*     destruct UB as [ms'' [[ptr'' ptrs''] [[EQ FREE'] UB]]]. *)
    (*     contradiction. *)
    (*   } *)

    (*   destruct CORRECT as [[errmsg [ERR [errspecmsg ERRSPEC]]] | CORRECT]. *)
    (*   { cbn in ERRSPEC. *)
    (*     destruct ERRSPEC as [UB | UB]; [inv UB|]. *)
    (*     destruct UB as [ms [pr' [FRESH UB]]]. *)
    (*     destruct UB as [UB | UB]; [inv UB|]. *)
    (*     destruct UB as [ms' [[ptr' ptrs'] [[EQ FREE] UB]]]. *)
    (*     subst. *)
    (*     destruct UB as [UB | UB]; try contradiction. *)
    (*     destruct UB as [ms'' [[ptr'' ptrs''] [[EQ FREE'] UB]]]. *)
    (*     contradiction. *)
    (*   } *)

    (*   destruct CORRECT as [[oommsg [OOM [oomspecmsg OOMSPEC]]] | CORRECT]. *)
    (*   { cbn in *. *)
    (*   } *)

    (*   destruct ms_fresh_pr as [[mem fs h] pr'] eqn:HMS. *)
    (*   exists {| *)
    (*     MemoryBigIntptrInfiniteSpec.MMSP.ms_memory_stack := *)
    (*     {| *)
    (*       MemoryBigIntptrInfiniteSpec.MMSP.memory_stack_memory := mem; *)
    (*       MemoryBigIntptrInfiniteSpec.MMSP.memory_stack_frame_stack := fs; *)
    (*       MemoryBigIntptrInfiniteSpec.MMSP.memory_stack_heap := h *)
    (*     |}; *)
    (*     MemoryBigIntptrInfiniteSpec.MMSP.ms_provenance := pr' *)
    (*   |}. *)
    (*   eexists. *)
    (*   split. *)





    (*   assert  *)
    (*   pose proof (@MemMonad_run *)
    (*                 ExtraState MemM _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ H _ *)
    (*                 (allocate_bytes dt bytes) *)
    (*                 ms_fresh_pr *)
    (*                 initial_state (* Probably wrong, not guaranteed to be valid. May need existence lemma *) *)
    (*              ). *)
    (*   (allocate_bytes dt bytes)). *)

    (*   unfold exec_correct in CORRECT. *)
    (*    destruct CORRECT. *)
    (* Qed. *)
    (* Admitted. *)

  End MemoryPrimitives.
End MemoryBigIntptrInfiniteSpec.


Module MemoryBigIntptrInfiniteSpecHelpers :=
  MemoryModelInfiniteSpecHelpers  LLVMParamsBigIntptr MemoryBigIntptr.MP MemoryBigIntptr.MMEP.MMSP MemoryBigIntptr.MMEP.MemSpec MemoryBigIntptrInfiniteSpec.
