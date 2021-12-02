From Coq Require Import ZArith String.

From ExtLib Require Import
     Structures.Monads
     Structures.Functor
     Structures.MonadExc
     Data.Monads.EitherMonad
     Data.Monads.StateMonad
     Data.Monads.IdentityMonad.

From Vellvm Require Import
     Utils.Error
     Utils.UBAndErrors
     Semantics.MemoryAddress
     Semantics.DynamicValues
     Semantics.LLVMEvents
     Semantics.Memory.FiniteProvenance
     Semantics.Memory.Sizeof
     Utils.StateMonads
     Utils.Monads
     Utils.MonadExcLaws
     Utils.MonadReturnsLaws
     Utils.Raise.

From ITree Require Import
     ITree
     Basics.Basics
     Events.Exception
     Eq.Eq
     Events.StateFacts
     Events.State.

Import Morphisms.

Import Basics.Basics.Monads.

Import MonadNotation.

(* TODO: Provenance is an issue... *)
Module ERRSID (Addr:ADDRESS) (IP:INTPTR) (SIZEOF:Sizeof) (PROV:PROVENANCE(Addr)).
  Import PROV.

  (* Need failure, UB, state for store_ids, and state for provenances *)
  Inductive ErrSID_T M A := mkErrSID_T { unErrSID_T : @err_ub_oom_T (stateT store_id (stateT Provenance M)) A }.
  Definition ErrSID := ErrSID_T ident.

  Arguments unErrSID_T {_ _} _.
  Arguments mkErrSID_T {_ _} _.

  #[global] Instance Monad_ErrSID_T {M} `{HM : Monad M} : Monad (ErrSID_T M).
  Proof.
    split.
    - exact (fun T t => mkErrSID_T (ret t)).
    - exact (fun A B ma amb =>
               mkErrSID_T (a <- unErrSID_T ma;;
                           unErrSID_T (amb a))).
  Defined.

  #[global] Instance Monad_EQ1_ErrSID_T {M} `{HME : Monad.Eq1 M} : Monad.Eq1 (ErrSID_T M).
  Proof.
    unfold Monad.Eq1.
    refine
      (fun T e1 e2 =>
         match e1, e2 with
         | mkErrSID_T (ERR_UB_OOM e1), mkErrSID_T (ERR_UB_OOM e2) =>
             Monad.eq1 e1 e2
         end
      ).
  Defined.

  #[global] Instance MonadLawsE_ErrSID
    : Monad.MonadLawsE ErrSID.
  Proof.
    split.
    - (* bind_ret_l *)
      intros A B f x.
      cbn.
      destruct (f x) as [[[[[e]]]]].
      reflexivity.
    - (* bind_ret_r *)
      intros A x.
      cbn.
      destruct x as [[[[[e]]]]].
      cbn.

      unfold unIdent.
      unfold Monad.eq1, EqM_eitherT; cbn.
      unfold Monad.eq1, MonadState.Eq1_stateTM; cbn.
      unfold pointwise_relation.

      intros s.
      unfold Monad.eq1.
      intros pr.
      unfold Eq1_ident.

      destruct (e s pr) as [[pr' [s' e']]]; cbn.
      destruct e' as [e_OOM | [e_UB | [[e_ERR] | a]]]; auto.
    - (* bind_bind *)
      intros A B C x f g.
      
      cbn.
      destruct x as [[[[[e]]]]].
      cbn.

      unfold unIdent.
      unfold Monad.eq1, EqM_eitherT; cbn.
      unfold Monad.eq1, MonadState.Eq1_stateTM; cbn.
      unfold pointwise_relation.

      intros s.
      unfold Monad.eq1.
      intros pr.
      unfold Eq1_ident.

      destruct (e s pr) as [[pr' [s' e']]]; cbn.
      destruct e' as [e_OOM | [e_UB | [[e_ERR] | a]]]; cbn; auto.

      destruct (f a) as [FA].
      destruct FA as [[[[FA]]]].
      cbn.
      destruct (FA s' pr') as [[pr'' [s'' e'']]].
      destruct e'' as [e''_OOM | [e''_UB | [[e''_ERR] | a']]]; cbn; auto.
    - (* Proper bind *)
      unfold Proper, respectful.
      intros A B x y XY x0 y0 POINTWISE.
      unfold pointwise_relation in POINTWISE.

      destruct x as [[[[[x]]]]].
      destruct y as [[[[[y]]]]].
      cbn in *.

      unfold Monad.eq1, EqM_eitherT; cbn.
      unfold Monad.eq1, MonadState.Eq1_stateTM; cbn.
      unfold pointwise_relation.

      intros s.
      unfold Monad.eq1.
      intros pr.
      unfold Eq1_ident.

      unfold Monad.eq1, EqM_eitherT, Monad.eq1, MonadState.Eq1_stateTM, pointwise_relation, Monad.eq1, MonadState.Eq1_stateTM, pointwise_relation, Eq1_ident in XY.
      cbn in XY.

      unfold unIdent.
      destruct (x s pr) as [[prx [sx x']]] eqn:Hx; cbn.
      destruct (y s pr) as [[pry [sy y']]] eqn:Hy; cbn.
      destruct x' as [x_OOM | [x_UB | [[x_ERR] | x']]]; cbn; auto;
        destruct y' as [y_OOM | [y_UB | [[y_ERR] | y']]]; cbn; auto;
      assert (x s pr = y s pr) as XY' by auto;
        rewrite Hx, Hy in XY';
        inversion XY'; auto.

      unfold Monad.eq1, Monad_EQ1_ErrSID_T in POINTWISE.
      specialize (POINTWISE y').
      destruct (x0 y') as [[x0y']].
      destruct (y0 y') as [[y0y']].
      specialize (POINTWISE sy pry).
      apply POINTWISE.
  Defined.

  #[global] Instance Reflexive_EQ1_ErrSID {A} : Reflexive (@Monad.eq1 ErrSID _ A).
  Proof.
    unfold Reflexive.
    intros x.
    destruct x.
    cbn.
    destruct unErrSID_T0.
    reflexivity.
  Defined.

  #[global] Instance Transitive_EQ1_ErrSID {A} : Transitive (@Monad.eq1 ErrSID _ A).
  Proof.
    unfold Transitive.
    intros x y z XY YZ.
    destruct x, y, z; cbn in *.
    destruct unErrSID_T0, unErrSID_T1, unErrSID_T2; cbn in *.
    congruence.
  Defined.

  #[global] Instance Symmetric_EQ1_ErrSID {A} : Symmetric (@Monad.eq1 ErrSID _ A).
  Proof.
    unfold Symmetric.
    intros x y XY.
    destruct x, y; cbn in *.
    destruct unErrSID_T0, unErrSID_T1; cbn in *.
    congruence.
  Defined.

  #[global] Instance Eq1Equivalence_EQ1_ErrSID : Monad.Eq1Equivalence ErrSID.
  Proof.
    split; typeclasses eauto.
  Defined.

  #[global] Instance RAISE_ERROR_ErrSID_T {M : Type -> Type} `{Monad M} : RAISE_ERROR (ErrSID_T M)
    := { raise_error := fun _ msg => mkErrSID_T (raise_error msg) }.

  #[global] Instance RAISE_UB_ErrSID_T {M : Type -> Type} `{Monad M} : RAISE_UB (ErrSID_T M)
    := { raise_ub := fun _ msg => mkErrSID_T (raise_ub msg) }.

  #[global] Instance RAISE_OOM_ErrSID_T {M : Type -> Type} `{Monad M} : RAISE_OOM (ErrSID_T M)
    := { raise_oom := fun _ msg => mkErrSID_T (raise_oom msg) }.

  #[global] Instance RaiseBindM_ErrSID : RaiseBindM ErrSID string (@raise_error ErrSID _).
  Proof.
    split.
    intros A B f x.
    reflexivity.
  Defined.

  Definition evalErrSID_T {A} {M} `{Monad M} (m : ErrSID_T M A) (sid : store_id) (prov : Provenance) : M (OOM_MESSAGE + UB (ERR A))%type
    := evalStateT (evalStateT (unEitherT (unEitherT (unEitherT (unERR_UB_OOM (unErrSID_T m))))) sid) prov.

  Definition evalErrSID {A} (m : ErrSID A) (sid : store_id) (prov : Provenance) : OOM_MESSAGE + UB (ERR A)
    := unIdent (evalErrSID_T m sid prov).

  Definition runErrSID_T {A} {M} `{Monad M} (m : ErrSID_T M A) (sid : store_id) (prov : Provenance) : M ((OOM_MESSAGE + UB (ERR A)) * store_id * Provenance)%type
    := runStateT (runStateT (unEitherT (unEitherT (unEitherT (unERR_UB_OOM (unErrSID_T m))))) sid) prov.

  Definition runErrSID {A} (m : ErrSID A) (sid : store_id) (prov : Provenance) : (OOM_MESSAGE + UB (ERR A)) * store_id * Provenance%type
    := unIdent (runErrSID_T m sid prov).

  Definition ErrSID_evals_to {A} (e : ErrSID A) sid pr (x : A) : Prop
    := evalErrSID e sid pr = inr (inr (inr x)).

  Definition ErrSID_runs_to {A} (e : ErrSID A) sid pr (x : A) sid' pr': Prop
    := runErrSID e sid pr = (inr (inr (inr x)), sid', pr').

  Definition fresh_sid : ErrSID store_id
    := mkErrSID_T (lift (modify N.succ)).

  Definition fresh_provenance : ErrSID Provenance
    := mkErrSID_T (lift (lift (modify next_provenance))).

  Definition fresh_allocation_id : ErrSID AllocationId
    := prov <- fresh_provenance;;
       ret (provenance_to_allocation_id prov).

  Definition err_to_ub {A} (e : err A) : ErrSID A
    := match e with
       | inl msg =>
           raise_ub msg
       | inr x => ret x
       end.

  Section Lemmas.
    Lemma ErrSID_evals_to_bind :
      forall {A X} sid prov (m : ErrSID X) k (res : A),
        ErrSID_evals_to (bind m k) sid prov res ->
        exists sid' prov' x,
          ErrSID_runs_to m sid prov x sid' prov' /\
            ErrSID_evals_to (k x) sid' prov' res.
    Proof.
      intros A X sid prov m k res EVAL.

      cbn in EVAL.
      inversion EVAL as [EVAL'].
      clear EVAL.
      rename EVAL' into EVAL.
      cbn in EVAL.

      unfold ErrSID_runs_to.
      unfold runErrSID.
      cbn.

      destruct (IdentityMonad.unIdent (unEitherT (unEitherT (unEitherT (unERR_UB_OOM (unErrSID_T m)))) sid prov)) as (p, p0) eqn:BLAH.
      destruct p0.
      cbn in *.

      destruct m; cbn in *; inversion EVAL.
      destruct unErrSID_T0.
      rename unERR_UB_OOM into foo.
      destruct foo; cbn in *; inversion EVAL.
      destruct unEitherT; cbn in *; inversion EVAL.
      destruct unEitherT; cbn in *; inversion EVAL.
      destruct unEitherT; cbn in *; inversion EVAL.
      destruct unIdent; cbn in *; inversion EVAL.
      inversion BLAH; subst; cbn in *.

      destruct s0; cbn in *; inversion EVAL.
      destruct s0; cbn in *; inversion EVAL.
      destruct s0; cbn in *; inversion EVAL.

      do 3 eexists.
      split.
      {
        reflexivity.
      }
      {
        unfold ErrSID_evals_to.
        cbn.
        auto.
      }
    Qed.

    Lemma ErrSID_runs_to_bind :
      forall {A X} sid prov (m : ErrSID X) k (res : A) sid_final prov_final,
        ErrSID_runs_to (bind m k) sid prov res sid_final prov_final ->
        exists sid' prov' x,
          ErrSID_runs_to m sid prov x sid' prov' /\
            ErrSID_runs_to (k x) sid' prov' res sid_final prov_final.
    Proof.
      intros A X sid prov m k res sid_final prov_final EVAL.

      cbn in EVAL.
      inversion EVAL as [EVAL'].
      clear EVAL.
      rename EVAL' into EVAL.
      cbn in EVAL.

      unfold ErrSID_runs_to.
      unfold runErrSID in *.
      cbn.

      destruct (IdentityMonad.unIdent (unEitherT (unEitherT (unEitherT (unERR_UB_OOM (unErrSID_T m)))) sid prov)) as (p, p0) eqn:BLAH.
      destruct p0.
      cbn in *.

      destruct m; cbn in *; inversion EVAL.
      destruct unErrSID_T0.
      rename unERR_UB_OOM into foo.
      destruct foo; cbn in *; inversion EVAL.
      destruct unEitherT; cbn in *; inversion EVAL.
      destruct unEitherT; cbn in *; inversion EVAL.
      destruct unEitherT; cbn in *; inversion EVAL.
      destruct unIdent; cbn in *; inversion EVAL.
      inversion BLAH; subst; cbn in *.

      destruct s0; cbn in *; inversion EVAL.
      destruct s0; cbn in *; inversion EVAL.
      destruct s0; cbn in *; inversion EVAL.

      do 3 eexists.
      split.
      {
        reflexivity.
      }
      {
        unfold ErrSID_evals_to.
        cbn.
        auto.
      }
    Qed.

    Lemma ErrSID_runs_to_ErrSID_evals_to :
      forall {X} sid prov sid' prov' (m : ErrSID X) (res : X),
        ErrSID_runs_to m sid prov res sid' prov' ->
        ErrSID_evals_to m sid prov res.
    Proof.
      intros X sid prov sid' prov' m res H.
      unfold ErrSID_runs_to in H.
      unfold ErrSID_evals_to.
      cbn.
      unfold runErrSID in H.
      cbn in H.
      match goal with
      |  H: _ |- fst (snd ?x) = _
         => destruct x
      end.
      cbn in H.
      inversion H.
      reflexivity.
    Qed.

    Global Instance proper_eq1_runs_to : forall {A}, Proper (@Monad.eq1 _ _ A ==> eq ==> eq ==> eq ==> eq  ==> eq ==> iff) (ErrSID_runs_to).
    Proof.
      repeat intro; subst. rename H into EQ.

      unfold Monad.eq1, Eq1_eitherT in EQ.
      split; intros RUNS.
      - unfold Monad.eq1 in EQ.
        unfold MonadState.Eq1_stateTM in EQ.
        unfold pointwise_relation in EQ.
        unfold Monad.eq1 in EQ.
        unfold Eq1_ident in EQ.

        cbn in EQ.
        unfold unEitherT in EQ.
        destruct x as [x].
        destruct y as [y].
        destruct x as [x].
        destruct y as [y].

        unfold ErrSID_runs_to, runErrSID, runErrSID_T in *.
        cbn in *.
        rewrite <- EQ.
        auto.
      - unfold Monad.eq1 in EQ.
        unfold MonadState.Eq1_stateTM in EQ.
        unfold pointwise_relation in EQ.
        unfold Monad.eq1 in EQ.
        unfold Eq1_ident in EQ.

        cbn in EQ.
        unfold unEitherT in EQ.
        destruct x as [x].
        destruct y as [y].
        destruct x as [x].
        destruct y as [y].

        unfold ErrSID_runs_to, runErrSID, runErrSID_T in *.
        cbn in *.
        rewrite EQ.
        auto.
    Qed.

  End Lemmas.

End ERRSID.
