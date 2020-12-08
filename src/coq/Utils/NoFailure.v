From ITree Require Import
     Eq.Eq
     ITree
     FailFacts
     Events.Exception.

From Vellvm Require Import 
     Utils.PostConditions
     Utils.PropT.

From Paco Require Import paco.

From ExtLib Require Import
     Structures.Monad.

From Coq Require Import
     Morphisms.

Import ITreeNotations.
Local Open Scope itree.

(* MOVE itree *)
Lemma interp_state_iter :
  forall {A R S : Type} (E F : Type -> Type) (s0 : S) (a0 : A) (h : E ~> Monads.stateT S (itree F)) f,
    State.interp_state (E := E) (T := R) h (ITree.iter f a0) s0 ≈
                 @Basics.iter _ MonadIter_stateT0 _ _ (fun a s => State.interp_state h (f a) s) a0 s0.
Proof.
  unfold iter, CategoryKleisli.Iter_Kleisli, Basics.iter, MonadIter_stateT0, Basics.iter, MonadIter_itree in *; cbn.
  einit. ecofix CIH; intros.
  rewrite 2 unfold_iter; cbn.
  rewrite !Eq.bind_bind.
  setoid_rewrite bind_ret_l.
  rewrite StateFacts.interp_state_bind.
  ebind; econstructor; eauto.
  - reflexivity.
  - intros [s' []] _ []; cbn.
    + rewrite StateFacts.interp_state_tau.
      estep.
    + rewrite StateFacts.interp_state_ret; apply reflexivity.
Qed.

Lemma interp_fail_iter :
  forall {A R : Type} (E F : Type -> Type) (a0 : A) (h : E ~> failT (itree F)) f,
    interp_fail (E := E) (T := R) h (ITree.iter f a0) ≈
                @Basics.iter _ failT_iter _ _ (fun a => interp_fail h (f a)) a0.
Proof.
  unfold Basics.iter, failT_iter, Basics.iter, MonadIter_itree in *; cbn.
  einit. ecofix CIH; intros *.
  rewrite 2 unfold_iter; cbn.
  rewrite !Eq.bind_bind.
  rewrite interp_fail_bind.
  ebind; econstructor; eauto.
  reflexivity.
  intros [[a1|r1]|] [[a2|r2]|] EQ; inv EQ.
  - rewrite bind_ret_l.
    rewrite interp_fail_tau.
    estep.
  - rewrite bind_ret_l, interp_fail_ret.
    eret.
  - rewrite bind_ret_l.
    eret.
Qed.

Lemma translate_iter :
  forall {A R : Type} (E F : Type -> Type) (a0 : A) (h : E ~> F) f,
    translate (E := E) (F := F) (T := R) h (ITree.iter f a0) ≈
              ITree.iter (fun a => translate h (f a)) a0.
Proof.
  intros; revert a0.
  einit; ecofix CIH; intros.
  rewrite 2 unfold_iter; cbn.
  rewrite TranslateFacts.translate_bind.
  ebind; econstructor; eauto.
  - reflexivity.
  - intros [|] [] EQ; inv EQ.
    + rewrite TranslateFacts.translate_tau; estep.
    + rewrite TranslateFacts.translate_ret; apply reflexivity.
Qed.

Section Handle_Fail.

  Definition h_fail {T E} : exceptE T ~> failT (itree E) :=
    fun _ _ => Ret None.

  Definition trigger_fail {E} : E ~> failT (itree E)
    := fun _ e => Vis e (fun x => Ret (Some x)).

  (* TODO: Use [over], or possibly [exceptE -< E] *)
  Definition run_fail {E T}
    : itree (exceptE T +' E) ~> failT (itree E)
    := interp_fail (case_ h_fail trigger_fail).

End Handle_Fail.

Lemma post_returns : forall {E X} (t : itree E X), t ⤳ fun a => Returns a t.
Proof.
  intros; eapply eqit_mon; eauto.
  2: eapply PropT.eutt_Returns.
  intros ? ? [<- ?]; auto.
Qed.

Lemma eutt_clo_bind_returns {E R1 R2 RR U1 U2 UU}
      (t1 : itree E U1) (t2 : itree E U2)
      (k1 : U1 -> itree E R1) (k2 : U2 -> itree E R2)
      (EQT: @eutt E U1 U2 UU t1 t2)
      (EQK: forall u1 u2, UU u1 u2 -> Returns u1 t1 -> Returns u2 t2 -> eutt RR (k1 u1) (k2 u2)):
  eutt RR (x <- t1;; k1 x) (x <- t2;; k2 x).
Proof.
  intros; eapply eutt_post_bind_gen; eauto using post_returns.
Qed.

Section No_Failure.

  (* We are often interested in assuming that a computation does not fail.
     This file develop ways to assert and reason about such a fact assuming that
     the tree has been interpreted into the [failT (itree E)] monad.
     Note: nothing in this file is specific to Vellvm, it should eventually be
     moved to the itree library.
   *)

  Definition no_failure {E X} (t : itree E (option X)) : Prop :=
    t ⤳ fun x => ~ x = None.

  Global Instance no_failure_eutt {E X} : Proper (eutt eq ==> iff) (@no_failure E X).
  Proof.
    intros t s EQ; unfold no_failure; split; intros ?; [rewrite <- EQ | rewrite EQ]; auto.
  Qed.

  (* This is a non-trivial proof, not a direct consequence of an inversion lemma.
     This states essentially that if `no_failure` holds at the end of the execution,
     then it is an invariant of the execution.
   *)
  Lemma no_failure_bind_prefix : forall {E X Y} (t : itree E (option X)) (k : X -> itree E (option Y)),
      no_failure (bind (m := failT (itree E)) t k) ->
      no_failure t.
  Proof.
    unfold no_failure,has_post; intros E X Y.
    einit; ecofix CIH.
    intros * NOFAIL.
    cbn in NOFAIL. rewrite unfold_bind in NOFAIL.
    rewrite itree_eta.
    destruct (observe t) eqn:EQt.
    - eret.
      cbn in *.
      destruct r; [intros abs; inv abs | exfalso]. 
      apply eutt_Ret in NOFAIL; apply NOFAIL; auto.
    - estep.
      cbn in *.
      ebase; right; eapply CIH.
      rewrite <- tau_eutt; eauto.
    - estep.
      cbn in *.
      intros ?; ebase.
      right; eapply CIH0.
      eapply eqit_Vis in NOFAIL; eauto.
  Qed.

  Lemma no_failure_bind_cont : forall {E X Y} (t : _ X) (k : X -> _ Y),
      no_failure (bind (m := failT (itree E)) t k) ->
      forall u, Returns (E := E) (Some u) t -> 
              no_failure (k u).
  Proof.
    intros * NOFAIL * ISRET.
    unfold no_failure in *.
    cbn in *.
    eapply PropT.eqit_bind_Returns_inv in NOFAIL; eauto. 
    apply NOFAIL.
  Qed.

  Lemma no_failure_Ret :
    forall E T X x, @no_failure E X (@run_fail E T X (Ret x)).
  Proof.
    intros.
    unfold run_fail, no_failure.
    cbn.
    rewrite interp_fail_Ret.
    apply eutt_Ret; intros abs; inv abs.
  Qed.

  Lemma failure_throw : forall E Err X (s: Err),
      ~ no_failure (E := E) (X := X) (@run_fail E Err X (throw (E := _ +' E) s)).
  Proof.
    intros * abs.
    unfold no_failure, throw, run_fail in *.
    rewrite interp_fail_vis in abs.
    cbn in *.
    unfold h_fail in *; rewrite  !bind_ret_l in abs.
    eapply eutt_Ret in abs.
    apply abs; auto.
  Qed.

End No_Failure.
