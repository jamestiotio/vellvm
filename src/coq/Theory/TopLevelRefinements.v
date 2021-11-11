(* begin hide *)
From ITree Require Import
     ITree
     ITreeFacts
     Basics.HeterogeneousRelations
     Events.State
     Events.StateFacts
     InterpFacts
     KTreeFacts
     Eq.Eq.

From Vellvm Require Import
     Utilities
     Syntax
     Semantics
     Theory.Refinement
     Theory.InterpreterMCFG
     Theory.InterpreterCFG.

From ExtLib Require Import
     Structures.Functor.

From Coq Require Import
     RelationClasses
     Strings.String
     Logic
     Morphisms
     Relations
     List.

From ITree Require Import
     Basics.Monad
     Basics.MonadState.

Require Import Paco.paco.

Import ListNotations.
Import ITree.Basics.Basics.Monads.

Module Type TopLevelRefinements (IS : InterpreterStack) (TOP : LLVMTopLevel IS).
  Export TOP.
  Export IS.
  Export IS.LLVM.
  Export IS.LLVM.SP.SER.

  Import SemNotations.

  Module R := Refinement.Make LP LLVM.
  Import R.
  (* end hide *)

  (** *)
  (*    This file is currently a holdall. *)
  (*    In here, we have: *)
  (*    * partial interpreters to each levels; *)
  (*    * hierarchies of refinements of mcfgs and proofs of inclusions; *)
  (*    * lemmas for each partial interpreter of commutation with bind and ret; *)
  (*    * some misc proper instances; *)
  (*    * admitted statement of inclusion of the intepreter into the model; *)
  (*  **)

  (** The module _Refinement.Make_ defines a series of refinements between *)
  (*     [itree]s at the various signatures of events a Vellvm goes through during *)
  (*     the chain of interpretations leading to the definition of the model. *)
  (*     These refinements state set inclusion of the concretization of the *)
  (*     returned under-defined values, but impose no constraints on the states. *)

  (*     In this module, we show that these refinements define a chain of growing *)
  (*     relations when composed with the bits of interpretations relating each *)
  (*     level. *)

  (*     Finally, this allows us to lift these relations on [itree]s to a growing *)
  (*     chain of relations on [mcfg typ]. *)
  (*  *)

  (** BEGIN TO MOVE *)
  Lemma subrelation_R_TT:
    forall A (R : relation A), subrelation R TT.
  Proof. firstorder. Qed.

  Lemma subrelation_prod_left :
    forall A B (R R' : relation A) (R2 : relation B), subrelation R R' -> subrelation (R × R2) (R' × R2).
  Proof.
    intros A B R R' R2 H.
    unfold subrelation in *.
    intros x y HRR2.
    inversion HRR2; firstorder.
  Qed.

  Lemma eutt_tt_to_eq_prod :
    forall X R (RR : relation R) E (t1 t2 : itree E (X * R)),
      eutt (eq × RR) t1 t2 -> eutt (TT × RR) t1 t2.
  Proof.
    intros X R RR E t1 t2 Heutt.
    unfold eutt.
    apply (eqit_mon (eq × RR) (TT × RR) true true true true); trivial.
    intros x0 x1 PR.
    eapply subrelation_prod_left. apply subrelation_R_TT. all: apply PR.
  Qed.

  Import AlistNotations.
  Lemma alist_find_eq_dec_local_env :
    forall k (m1 m2 : local_env),
      {m2 @ k = m1 @ k} + {m2 @ k <> m1 @ k}.
  Proof.
    intros; eapply alist_find_eq_dec.
  Qed.


  #[global] Instance interp_state_proper {T E F S}
   (h: forall T : Type, E T -> Monads.stateT S (itree F) T)
    : Proper (eutt Logic.eq ==> Monad.eq1) (State.interp_state h (T := T)).
  Proof.
    einit. ecofix CIH. intros.

    rewrite !unfold_interp_state. punfold H0. red in H0.
    induction H0; intros; subst; simpl; pclearbot.
    - eret.
    - etau.
    - ebind. econstructor; [reflexivity|].
      intros; subst.
      etau. ebase.
    - rewrite tau_euttge, unfold_interp_state; eauto.
    - rewrite tau_euttge, unfold_interp_state; eauto.
  Qed.

  #[export] Hint Unfold TT : core.
  Instance TT_equiv :
    forall A, Equivalence (@TT A).
  Proof.
    intros A; split; repeat intro; auto.
  Qed.

  (** END TO MOVE *)

  Section REFINEMENT.
    
    (** We first prove that the [itree] refinement at level [i] entails the *)
    (*     refinement at level [i+1] after running the [i+1] level of interpretation *)
    (*    *)

    (* Lemma 5.7  *)
    (*      See the related definition of [refine_L0] in Refinement.v. (Search for Lemma 5.7) *)

    (*      The similar results mentioned in the paper are listed below. *)
    (*   *)
    Lemma refine_01: forall t1 t2 g,
        refine_L0 t1 t2 -> refine_L1 (interp_global t1 g) (interp_global t2 g).
    Proof.
      intros t1 t2 g H.
      apply eutt_tt_to_eq_prod, eutt_interp_state; auto.
    Qed.

    Lemma refine_12 : forall t1 t2 l,
        refine_L1 t1 t2 -> refine_L2 (interp_local_stack t1 l) (interp_local_stack t2 l).
    Proof.
      intros t1 t2 l H.
      apply eutt_tt_to_eq_prod, eutt_interp_state; auto.
    Qed.

    Lemma refine_23 : forall t1 t2 m,
        refine_L2 t1 t2 -> refine_L3 (interp_memory t1 m) (interp_memory t2 m).
    Proof.
      intros t1 t2 m H.
      apply eutt_tt_to_eq_prod, eutt_interp_state; auto.
    Qed.

    (* Things are different for L4 and L5: we get into the [Prop] monad. *)
    Lemma refine_34 : forall t1 t2,
        refine_L3 t1 t2 -> refine_L4 (model_undef refine_res3 t1) (model_undef refine_res3 t2).
    Proof.
      intros t1 t2 H t Ht.
      exists t; split.
      - unfold model_undef in *.
        unfold L3 in *.
        match goal with |- PropT.interp_prop ?x _ _ _ _ => remember x as h end.
        eapply interp_prop_Proper_eq in Ht.
        apply Ht.
        + apply prod_rel_refl; typeclasses eauto.
        + apply prod_rel_trans; typeclasses eauto.
        + assumption.
        + reflexivity.
      - reflexivity.
    Qed.

    Lemma refine_45 : forall Pt1 Pt2,
        refine_L4 Pt1 Pt2 -> refine_L5 (model_UB refine_res3 Pt1) (model_UB refine_res3 Pt2).
    Proof.
      intros Pt1 Pt2 HR t2 HM.
      exists t2; split; [| reflexivity].
      destruct HM as (t2' & HPt2 & HPT2).
      apply HR in HPt2; destruct HPt2 as (t1' & HPt1 & HPT1).
      exists t1'; split; auto.
      match type of HPT2 with | PropT.interp_prop ?h' ?t _ _ _ => remember h' as h end.
      eapply interp_prop_Proper_eq with (RR := refine_res3); eauto.
      - typeclasses eauto.
      - typeclasses eauto.
    Qed.


    Variable ret_typ : dtyp.
    Variable entry : string.
    Variable args : list uvalue.

    Definition denote_vellvm_init := denote_vellvm ret_typ entry args.
    
    (** *)
    (*    In particular, we can therefore define top-level models *)
    (*    short-circuiting the interpretation early. *)
    (*    *)

    Definition model_to_L1  (prog: mcfg dtyp) :=
      let L0_trace := denote_vellvm_init prog in
      ℑs1 L0_trace [].

    Definition model_to_L2 (prog: mcfg dtyp) :=
      let L0_trace := denote_vellvm_init prog in
      ℑs2 L0_trace [] ([],[]).

    Definition model_to_L3 (prog: mcfg dtyp) :=
      let L0_trace := denote_vellvm_init prog in
      ℑs3 L0_trace [] ([],[]) emptyMemState.

    Definition model_to_L4 (prog: mcfg dtyp) :=
      let L0_trace := denote_vellvm_init prog in
      ℑs4 (refine_res3) L0_trace [] ([],[]) emptyMemState.

    Definition model_to_L5 (prog: mcfg dtyp) :=
      let L0_trace := denote_vellvm_init prog in
      ℑs5 (refine_res3) L0_trace [] ([],[]) emptyMemState.

    (** *)
    (*    Which leads to five notion of equivalence of [mcfg]s. *)
    (*    Note that all reasoning is conducted after conversion to [mcfg] and *)
    (*    normalization of types. *)
    (*    *)
    Definition refine_mcfg_L1 (p1 p2: mcfg dtyp): Prop :=
      R.refine_L1 (model_to_L1 p1) (model_to_L1 p2).

    Definition refine_mcfg_L2 (p1 p2: mcfg dtyp): Prop :=
      R.refine_L2 (model_to_L2 p1) (model_to_L2 p2).

    Definition refine_mcfg_L3 (p1 p2: mcfg dtyp): Prop :=
      R.refine_L3 (model_to_L3 p1) (model_to_L3 p2).

    Definition refine_mcfg_L4 (p1 p2: mcfg dtyp): Prop :=
      R.refine_L4 (model_to_L4 p1) (model_to_L4 p2).

    Definition refine_mcfg  (p1 p2: mcfg dtyp): Prop :=
      R.refine_L5 (model_to_L5 p1) (model_to_L5 p2).

    (** *)
    (*    The chain of refinements is monotone, legitimating the ability to *)
    (*    conduct reasoning before interpretation when suitable. *)
    (*    *)
    Lemma refine_mcfg_L1_correct: forall p1 p2,
        refine_mcfg_L1 p1 p2 -> refine_mcfg p1 p2.
    Proof.
      intros p1 p2 HR.
      apply refine_45, refine_34, refine_23, refine_12, HR.
    Qed.

    Lemma refine_mcfg_L2_correct: forall p1 p2,
        refine_mcfg_L2 p1 p2 -> refine_mcfg p1 p2.
    Proof.
      intros p1 p2 HR.
      apply refine_45, refine_34, refine_23, HR.
    Qed.

    Lemma refine_mcfg_L3_correct: forall p1 p2,
        refine_mcfg_L3 p1 p2 -> refine_mcfg p1 p2.
    Proof.
      intros p1 p2 HR.
      apply refine_45, refine_34, HR.
    Qed.

    Lemma refine_mcfg_L4_correct: forall p1 p2,
        refine_mcfg_L4 p1 p2 -> refine_mcfg p1 p2.
    Proof.
      intros p1 p2 HR.
      apply refine_45, HR.
    Qed.

    (* MOVE *)
    Ltac flatten_goal :=
      match goal with
      | |- context[match ?x with | _ => _ end] => let Heq := fresh "Heq" in destruct x eqn:Heq
      end.

    Ltac flatten_hyp h :=
      match type of h with
      | context[match ?x with | _ => _ end] => let Heq := fresh "Heq" in destruct x eqn:Heq
      end.

    Ltac flatten_all :=
      match goal with
      | h: context[match ?x with | _ => _ end] |- _ => let Heq := fresh "Heq" in destruct x eqn:Heq
      | |- context[match ?x with | _ => _ end] => let Heq := fresh "Heq" in destruct x eqn:Heq
      end.

    Lemma UB_handler_correct: handler_correct UB_handler UB_exec.
    Proof.
      unfold UB_handler. unfold UB_exec.
      unfold handler_correct.
      intros. auto.
    Qed.

    Lemma OOM_handler_correct:
      forall E F, handler_correct (@OOM_handler E F) OOM_exec.
    Proof.
      intros E F.
      unfold OOM_handler. unfold OOM_exec.
      unfold handler_correct.
      intros. auto.
    Qed.

  Lemma interp_prop_correct_exec':
    forall {E F} (h_spec: E ~> PropT F) (h: E ~> itree F),
      handler_correct h_spec h ->
      forall R RR `{Reflexive _ RR} t t', t ≈ t' -> interp_prop h_spec R RR t (interp h t').
  Proof.
    intros.
    revert t t' H1.
    pcofix CIH.
    intros t t' eq.
    pstep.
    red.
    unfold interp, Basics.iter, MonadIter_itree.
    rewrite (itree_eta t) in eq. 
    destruct (observe t).
    - econstructor. reflexivity. rewrite <- eq. rewrite unfold_iter. cbn. rewrite Eq.bind_ret_l. cbn.  reflexivity.
    - econstructor. right.
      eapply CIH. rewrite tau_eutt in eq. rewrite eq. reflexivity.
    - econstructor. 
      2 : { rewrite <- eq. rewrite unfold_iter. cbn.
            unfold ITree.map. rewrite Eq.bind_bind.
            setoid_rewrite Eq.bind_ret_l at 1. cbn. setoid_rewrite tau_eutt.
            reflexivity. }
      apply H.
      intros a. cbn.  
      right.
      unfold interp, Basics.iter, MonadIter_itree in CIH. unfold fmap, Functor_itree, ITree.map in CIH.
      specialize (CIH (k a) (k a)).
      apply CIH.
      reflexivity.
  Qed.

  Lemma interp_prop_correct_exec_flip:
    forall {E} (h_spec: E ~> PropT E) (h: E ~> itree E),
      handler_correct h_spec h ->
      forall R RR `{Reflexive _ RR} t t', t ≈ t' -> interp_prop h_spec R RR (interp h t') t.
  Proof.
    intros.
    revert t' t H1.
    pcofix CIH.
    intros t' t eq.
    pstep.
    red.
    unfold interp, Basics.iter, MonadIter_itree.
    rewrite (itree_eta t') in eq.
    replace t' with ({| _observe := observe t' |}) by admit.
    destruct (observe t') eqn:T'; cbn.
    - cbn. econstructor. reflexivity. rewrite <- eq. reflexivity.
    - econstructor. right.
      eapply CIH. rewrite tau_eutt in eq. rewrite eq. reflexivity.
    - unfold handler_correct in H.
      set (f := (fun t0 : itree (fun H1 : Type => E H1) R =>
           match observe t0 with
           | RetF r0 => Ret (inr r0)
           | TauF t1 => Ret (inl t1)
           | @VisF _ _ _ X0 e0 k0 => ITree.map (fun x : X0 => inl (k0 x)) (h X0 e0)
           end)).

      set (x := (Vis e k)).
      replace (ITree.iter f x) with (ITree.bind (f x)
                                                (fun lr =>
                                                   match lr with
                                                   | inl l => Tau (ITree.iter f l)
                                                   | inr r => Ret r
                                                   end)) by admit.

      subst f.
      subst x.
      cbn.

      (* I know (h X e) is in h_spec *)
      (* l = (r <- h X e;; ret (inl (k r))) *)
      match goal with
      | H : _ |- context [ ITree.bind (ITree.map ?f ?t) ?k ]
        => replace (ITree.bind (ITree.map f t) k) with (ITree.bind t (fun x => k (f x))) by admit
      end.

      pose proof (H X e).      
  Admitted.


    Set Printing Implicit.
    Lemma refine_UB
      : forall E F G `{LLVMEvents.FailureE -< E +' F +' G} T TT (HR: Reflexive TT)
               (x : _ -> Prop)
               (y : itree (E +' F +' UBE +' G) T),
        x y -> model_UB TT x (exec_UB y).
    Proof.
      intros E F G H T TT HR x y H0.
      unfold model_UB. unfold exec_UB.
      exists y. split. assumption.
      apply interp_prop_correct_exec.
      intros.
      apply case_prop_handler_correct.
      unfold handler_correct. intros. reflexivity.
      apply case_prop_handler_correct.
      unfold handler_correct. intros. reflexivity.
      apply case_prop_handler_correct.
      apply UB_handler_correct.
      unfold handler_correct. intros. reflexivity.
      assumption. reflexivity.
    Qed.

    Lemma Pick_handler_correct :
      forall E `{FailureE -< E} `{UBE -< E} `{OOME -< E},
        handler_correct (@Pick_handler E _ _ _) concretize_picks.
    Proof.
      unfold handler_correct.
      intros.
      destruct e.
      cbn. apply PickD with (res := concretize_uvalue u).
      - apply Pick.concretize_u_concretize_uvalue.
      - reflexivity.
    Qed.
    
    Lemma refine_undef
      : forall (E F:Type -> Type) T TT (HR: Reflexive TT)  `{UBE -< F} `{FailureE -< F} `{OOME -< F}
               (x : itree _ T),
        model_undef TT x (@exec_undef E F _ _ _ _ x).
    Proof.
      intros E F H H0 T TT HR OOM x.
      cbn in *.
      unfold model_undef.
      unfold exec_undef.
      apply interp_prop_correct_exec.
      apply case_prop_handler_correct.
      unfold handler_correct. intros. reflexivity.
      apply case_prop_handler_correct.
      apply Pick_handler_correct.

      unfold handler_correct. intros. reflexivity.
      assumption. reflexivity.
    Qed.

    Lemma refine_oom
      : forall E F T TT (HR: Reflexive TT)
               (x : _ -> Prop)
               (y : itree (E +' OOME +' F) T),
        x y -> model_OOM TT x (exec_OOM y).
    Proof.
      intros E F T TT HR x y H0.
      unfold model_OOM, model_OOM_h.
      unfold exec_OOM.
      exists y. split. assumption.
      Set Printing Notations.
      Unset Printing Implicit.

      unfold case_.
      unfold Case_sum1_Handler.
      unfold Handler.case_.
      cbn.

      
      setoid_rewrite Eq.bind_ret_r. ITree.bind_ret_r.
      
      apply interp_prop_correct_exec _flip.
      intros.
      apply case_prop_handler_correct.
      unfold handler_correct. intros. reflexivity.
      apply case_prop_handler_correct.
      apply OOM_handler_correct.
      unfold handler_correct. intros. reflexivity.
      assumption. reflexivity.
    Qed.

    (** *)
    (*    Theorem 5.8: We prove that the interpreter belongs to the model. *)
    (*    *)

    (* refine (model p1) (model p2) 

       refine := forall t, model p2 t -> model p1 t
     *)
    Theorem interpreter_sound: forall p, model p (interpreter p).
    Proof.
      intros p.
      unfold model, model_gen.
      unfold interpreter, interpreter_gen.
      unfold ℑs5.
      unfold interp_mcfg6_exec.
      apply refine_oom. auto.
      apply refine_UB. auto.
      apply refine_undef. auto.
    Qed.

  End REFINEMENT.

  (** *)
  (*    Each interpreter commutes with [bind] and [ret]. *)
  (*  **)

  (** We hence can also commute them at the various levels of interpretation *)

  Lemma interp2_bind:
    forall {R S} (t: itree L0 R) (k: R -> itree L0 S) s1 s2,
      ℑs2 (ITree.bind t k) s1 s2 ≈
          (ITree.bind (ℑs2 t s1 s2) (fun '(s1',(s2',x)) => ℑs2 (k x) s2' s1')).
  Proof.
    intros.
    unfold ℑs2.
    rewrite interp_intrinsics_bind, interp_global_bind, interp_local_stack_bind.
    apply eutt_clo_bind with (UU := Logic.eq); [reflexivity | intros ? (? & ? & ?) ->; reflexivity].
  Qed.

  Lemma interp2_ret:
    forall (R : Type) s1 s2 (x : R),
      ℑs2 (Ret x) s1 s2 ≈ Ret (s2, (s1, x)).
  Proof.
    intros; unfold ℑs2.
    rewrite interp_intrinsics_ret, interp_global_ret, interp_local_stack_ret; reflexivity.
  Qed.

  Definition interp_cfg {R: Type} (trace: itree instr_E R) g l m :=
    let uvalue_trace   := interp_intrinsics trace in
    let L1_trace       := interp_global uvalue_trace g in
    let L2_trace       := interp_local L1_trace l in
    let L3_trace       := interp_memory L2_trace m in
    let L4_trace       := model_undef eq L3_trace in
    let L5_trace       := model_UB eq L4_trace in
    L5_trace.

  Definition model_to_L5_cfg (prog: cfg dtyp) :=
    let trace := denote_cfg prog in
    interp_cfg trace [] [] emptyMemState.

  Definition refine_cfg_ret: relation (PropT L5 (memory_stack * (local_env * (global_env * uvalue)))) :=
    fun ts ts' => forall t, ts t -> exists t', ts' t' /\ eutt  (TT × (TT × (TT × refine_uvalue))) t t'.

End TopLevelRefinements.
