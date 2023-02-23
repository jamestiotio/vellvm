From Coq Require Import
     List
     ZArith
     Lia.
Import ListNotations.
From Vellvm Require Import
     Syntax
     Syntax.ScopeTheory
     Utils.Tactics.

Require Import Coqlib.
Require Import Util.
Require Import Datatypes.

Open Scope nat_scope.

(** Misc Tactics *)

(* Clone the hypothesis h *)
Ltac clone_hyp h :=
  let H := fresh "C" in
  assert (C := h).

(* Clone the hypothesis h as a new hypothesis s, and apply the theorem t *)
Ltac capply t h s :=
  assert (s := h) ; apply t in s.

Ltac ceapply t h s :=
  assert (s := h) ; eapply t in s.

Ltac inv_pair :=
  match goal with
  | h : (_,_) = (_, _) |- _ => inv h
  end.

(** Misc lemmas on list *)

Ltac break_list_hyp :=
  match goal with
  | h: context[List.In _ (_ ++ _)] |- _ => repeat (apply in_app_or in h)
  end.

Ltac break_list_goal :=
  try (rewrite Util.list_cons_app) ;
  try (
        match goal with
        | |- context[inputs (_ ++ _)] =>
            repeat (rewrite !ScopeTheory.inputs_app)
        | |- context[outputs (_ ++ _)] =>
            repeat (rewrite !ScopeTheory.outputs_app)
        end ) ;
  try (match goal with
       | |- context[List.In _ (_ ++ _)] => repeat (apply in_or_app)
       end).

Lemma In_singleton : forall {A} (x y : A),
    In x [y] <-> x=y.
Proof.
  intros.
  split ; intro.
  cbn in H; intuition.
  subst; apply in_eq.
Qed.

Lemma hd_In : forall {A} (d : A) (l : list A),
    (length l >= 1)%nat -> In (hd d l) l.
Proof.
  intros.
  induction l.
  now simpl in H.
  simpl ; now left.
Qed.

Lemma List_norepet_singleton : forall {A} (x : A),
    Coqlib.list_norepet [x].
Proof.
  intros.
  apply list_norepet_cons ; auto.
  apply list_norepet_nil.
Qed.

Lemma not_in_app : forall {T} {x : T} l1 l2,
    ~ In x (l1++l2) <-> ~ In x l1 /\ ~ In x l2.
Proof.
  intros.
  intuition.
  apply in_app in H0.
  destruct H0 ; [ now apply H1 | now apply H2].
Qed.

Lemma not_in_incl : forall {T} l l' (x : T),
    incl l' l ->
    ~ In x l ->
    ~ In x l'.
Proof.
  intros.
  unfold incl in H.
  intro. apply H in H1. contradiction.
Qed.

Lemma incl_In :
  forall {T} l sl (y: T), incl sl l -> In y sl -> In y l.
Proof.
  intros.
  now apply H.
Qed.

Lemma incl_disjoint : forall {A} (l1 sl1 l2 : list A),
    List.incl sl1 l1 ->
    list_disjoint l1 l2 ->
    list_disjoint sl1 l2.
Proof.
  intros * INCL DIS.
  unfold incl in INCL.
  induction l2.
  - apply list_disjoint_nil_r.
  - apply list_disjoint_cons_r.
    + unfold list_disjoint ; repeat intro.
      apply INCL in H.
      apply list_disjoint_cons_right in DIS.
      unfold list_disjoint in DIS.
      eapply DIS in H0 ; [|eassumption].
      contradiction.
    + intro. apply INCL in H.
      unfold list_disjoint in DIS.
      apply DIS with (y:=a) in H ; [contradiction|].
      apply in_cns ; intuition.
Qed.

(* NOTE it probably lacks an hypothesis, such as
    (list_norepet sl) *)
Lemma length_incl : forall {T} (l sl : list T) n,
    (length sl >= n)%nat ->
    incl sl l ->
    (length l >= n)%nat.
Proof.
  induction l ; intros.
  - apply incl_l_nil in H0. subst ; lia.
  - simpl in *.
    apply IHl in H. lia.
Admitted.

Lemma list_norepet_cons' : forall {T} (l : list T) x,
    list_norepet (x :: l) -> list_norepet l.
Proof.
  intros.
  rewrite Util.list_cons_app in H.
  eapply list_norepet_append_right ; eassumption.
Qed.

(** Relation between block_id Definition and lemmas about relation between block_id *)
(* Equality and Inequality *)
Definition eqb_bid b b' :=
  match b,b' with
  | Name s, Name s' => String.eqb s s'
  | Anon n, Anon n' => @RelDec.eq_dec int eq_dec_int n n'
  | Raw n, Raw n' => @RelDec.eq_dec int eq_dec_int n n'
  | _ , _ => false
  end.

Lemma eqb_bid_eq : forall b b', eqb_bid b b' = true <-> b=b'.
Proof.
  intros.
  split.
  - destruct b,b' ;
      try (intros ; simpl in H ; discriminate) ;
      simpl ; intros ; f_equal ;
      try (now apply String.eqb_eq) ;
      try (now apply Z.eqb_eq).
  - intros ; subst.
    destruct b' ; simpl ;
      try (now apply String.eqb_eq) ;
      try (now apply Z.eqb_eq).
Qed.

Lemma eqb_bid_neq : forall b b', eqb_bid b b' = false <-> b<>b'.
Proof.
  intros.
  split.
  - destruct b,b' ;
      try (intros ; simpl in H ; discriminate) ;
      simpl ; intros ; intro ;
      try (apply String.eqb_neq in H);
      try (apply Z.eqb_neq in H);
      inv H0 ; contradiction.
  - intros ; subst.
    destruct b,b' ; simpl ; auto;
      try (apply String.eqb_neq) ;
      try (apply Z.eqb_neq) ;
      intro ; subst ;
      contradiction.
Qed.

Lemma eqb_bid_comm : forall b b', eqb_bid b b' = eqb_bid b' b.
  intros.
  destruct b,b' ; simpl ; auto ;
    try (now apply String.eqb_sym) ;
    try (now apply Z.eqb_sym).
Qed.

Lemma eqb_bid_refl : forall b, eqb_bid b b = true.
  intros.
  destruct b ; simpl ; auto ;
    try (now apply String.eqb_refl) ;
    try (now apply Z.eqb_refl).
Qed.

(* Less than - Name _ < Raw _ < Anon _   *)
Require Import String.
Require Import Coq.Structures.OrderedTypeEx.
Definition ltb_bid b b' :=
  match b,b' with
  | Anon n, Anon n' => (n <? n')%Z
  | Raw n, Raw n' => (n <? n')%Z
  | Name s , Name s' =>
      match String_as_OT.cmp s s' with
      | Lt => true
      | _ => false
      end
  | Raw _ , Anon _ => true
  | Name _ , Raw _ => true
  | Name _ , Anon _ => true
  | _ , _ => false
  end.

Definition lt_bid (b b': block_id) : Prop :=
  ltb_bid b b' = true.

Lemma cmp_refl : forall s, String_as_OT.cmp s s = Eq.
Proof.
  intros.
  now apply String_as_OT.cmp_eq.
Qed.

Lemma ltb_bid_irrefl : forall a, ltb_bid a a = false.
  intros.
  unfold ltb_bid.
  destruct a ; try reflexivity ; try lia.
  now rewrite cmp_refl.
Qed.

Lemma lt_bid_irrefl : forall a, ~ lt_bid a a.
  intros.
  unfold lt_bid.
  rewrite ltb_bid_irrefl.
  auto.
Qed.

Lemma lt_bid_trans : forall b1 b2 b3, lt_bid b1 b2 -> lt_bid b2 b3 -> lt_bid b1 b3.
Proof.
  intros.
  unfold lt_bid, ltb_bid in *.
  destruct b1,b2,b3 ; try ( auto ; discriminate).
  destruct ( String_as_OT.cmp s s0) eqn:E1 ; try discriminate.
  destruct ( String_as_OT.cmp s0 s1) eqn:E2 ; try discriminate.
  apply String_as_OT.cmp_lt in E1,E2.
  eapply String_as_OT.lt_trans in E2 ; try eassumption.
  now apply String_as_OT.cmp_lt in E2 ; rewrite E2.
  lia.
  lia.
Qed.

Lemma ltb_bid_true : forall b1 b2, ltb_bid b1 b2 = true <-> lt_bid b1 b2.
Proof.
  intros.
  unfold lt_bid ; tauto.
Qed.

Lemma lt_bid_neq : forall b1 b2, lt_bid b1 b2 -> b1 <> b2.
Proof.
  repeat intro ; subst.
  now apply lt_bid_irrefl in H.
Qed.

Lemma lt_bid_neq' : forall b1 b2, lt_bid b1 b2 -> b2 <> b1.
Proof.
  repeat intro ; subst.
  now apply lt_bid_irrefl in H.
Qed.


Lemma not_lt_string_refl : forall s1 s2,
    String_as_OT.lt s1 s2 -> String_as_OT.lt s2 s1 -> False.
Proof.
  intros.
  eapply String_as_OT.lt_trans in H ; try eassumption.
  apply String_as_OT.lt_not_eq in H.
  now destruct H.
Qed.

Lemma ltb_assym : forall x y ,
    ltb_bid x y = false -> ltb_bid y x = true \/ eqb_bid x y = true.
Proof.
  intros.
  unfold ltb_bid in *.
  destruct x, y; auto.
  destruct (String_as_OT.cmp s s0) eqn:S_S0
  ; destruct (String_as_OT.cmp s0 s) eqn:S0_S
  ; intuition
  ; try (match goal with
         | h: String_as_OT.cmp _ _ = Eq |- _ =>
             apply String_as_OT.cmp_eq in h ; subst
         end
         ; cbn ; rewrite eqb_eq ; intuition).
  apply OrderedTypeEx.String_as_OT.compare_helper_gt in S_S0, S0_S.
  exfalso ; eapply not_lt_string_refl ; eassumption.
  all :
    (rewrite eqb_bid_eq
     ; destruct ((n =? n0)%Z) eqn:E
     ; [ rewrite Z.eqb_eq in E ; subst ; now right
       | left ; lia
    ]).
Qed.

(* Less or equal than *)
Definition leb_bid b b' :=
  orb (ltb_bid b b') (eqb_bid b b').

Definition le_bid b b' := (leb_bid b b' = true).

Lemma leb_bid_refl : forall a, leb_bid a a = true.
  intros.
  unfold leb_bid.
  destruct a
  ; simpl
  ; try (now rewrite String.eqb_refl)
  ; try ( rewrite Z.eqb_refl )
  ; try reflexivity.
  rewrite eqb_refl.
  all : apply Bool.orb_true_r.
Qed.

Lemma leb_bid_true : forall b1 b2, leb_bid b1 b2 = true <-> le_bid b1 b2.
Proof.
  intros.
  unfold le_bid ; tauto.
Qed.

Lemma le_bid_refl : forall a, le_bid a a.
  intros.
  unfold le_bid.
  apply leb_bid_refl.
Qed.

Lemma le_bid_trans : forall b1 b2 b3, le_bid b1 b2 -> le_bid b2 b3 -> le_bid b1 b3.
Proof.
  intros.
  unfold le_bid, leb_bid in *.
  apply Bool.orb_true_iff in H,H0 ; apply Bool.orb_true_iff.
  rewrite ltb_bid_true in * ; rewrite eqb_bid_eq in *.
  intuition ; try (subst ; intuition).
  left ; eapply lt_bid_trans ; eassumption.
Qed.

Lemma le_bid_antisym : forall x y, le_bid x y -> le_bid y x -> x=y.
Proof.
  intros.
  unfold le_bid,leb_bid in *.
  rewrite orb_true_iff in *.
  destruct H,H0 ;
    try (
    match goal with
    | h: eqb_bid _ _ = true |- _ =>
        now rewrite eqb_bid_eq in h
    end).
  - eapply lt_bid_trans in H ; try eassumption.
    now apply lt_bid_irrefl in H.
Qed.

Lemma lt_le : forall b1 b2, lt_bid b1 b2 -> le_bid b1 b2.
Proof.
  intros.
  unfold le_bid, leb_bid, lt_bid in *.
  now rewrite H.
Qed.

Lemma lt_bid_trans_le : forall b1 b2 b3, le_bid b1 b2 -> lt_bid b2 b3 -> lt_bid b1 b3.
Proof.
  intros.
  unfold le_bid, leb_bid in *.
  apply Bool.orb_true_iff in H ; destruct H as [H | H] ;
  try rewrite ltb_bid_true in * ; try (rewrite eqb_bid_eq in * ; subst).
  - eapply lt_bid_trans ; eassumption.
  - assumption.
Qed.

Lemma lt_bid_trans_le2 : forall b1 b2 b3, lt_bid b1 b2 -> le_bid b2 b3 -> lt_bid b1 b3.
Proof.
  intros.
  unfold le_bid, leb_bid in *.
  apply Bool.orb_true_iff in H0 ; destruct H0 as [H0 | H0] ;
  try rewrite ltb_bid_true in * ; try (rewrite eqb_bid_eq in * ; subst).
  - eapply lt_bid_trans ; eassumption.
  - assumption.
Qed.

Lemma not_le_lt : forall x y, leb_bid x y = false -> ltb_bid y x = true.
Proof.
  intros.
  unfold leb_bid in H.
  apply Bool.orb_false_elim in H ; destruct H.
  apply ltb_assym in H ; destruct H ; auto.
  rewrite H in H0 ; discriminate.
Qed.

Definition bot := Name "".

Lemma le_bid_bot : forall b, le_bid bot b.
Proof.
  intros.
  destruct b ; unfold le_bid ; auto.
  induction s.
  apply leb_bid_refl.
  unfold leb_bid.
  apply Bool.orb_true_iff ; intuition.
Qed.
Close Scope string_scope.

(* Max and min for block_id *)

Definition max b b' := if (leb_bid b b') then b' else b.
Definition min b b' := if (leb_bid b b') then b else b'.

Fixpoint max_bid' (l : list block_id) b :=
  match l with
  | [] => b
  | h :: t => max_bid' t (max b h)
  end.

Fixpoint min_bid' (l : list block_id) b :=
  match l with
  | [] => b
  | h :: t => min_bid' t (min b h)
  end.

Definition max_bid (l : list block_id) :=
  match (hd_error l) with
  | None => bot
  | Some h => max_bid' l h
  end.

Definition min_bid (l : list block_id) :=
  min_bid' l (hd bot l).

Lemma max_refl : forall x, max x x = x.
Proof.
  intros.
  unfold max ; now rewrite leb_bid_refl.
Qed.

Lemma min_refl : forall x, min x x = x.
Proof.
  intros.
  unfold min ; now rewrite leb_bid_refl.
Qed.

Ltac eq_neq_le_bid :=
  repeat (match goal with
          | h:context[leb_bid _ _ = false] |- _=>
              apply not_le_lt in h
              ; rewrite ltb_bid_true in h
     | h:context[leb_bid _ _ = true] |- _=> rewrite leb_bid_true in h
          end).

Lemma max_comm : forall x y, max x y = max y x.
Proof.
  intros.
  unfold max.
  destruct (leb_bid x y) eqn:X_Y
  ; destruct (leb_bid y x) eqn:Y_X
  ; auto.
  apply le_bid_antisym ; assumption.
  apply not_le_lt in X_Y, Y_X
  ; eapply lt_bid_trans in X_Y ; try eassumption.
  now apply lt_bid_irrefl in X_Y.
Qed.

Lemma max_assoc : forall x y z,
    max x (max y z) = max y (max x z).
Proof.
  intros.
  unfold max.
  destruct (leb_bid y z) eqn:Y_Z
  ; destruct (leb_bid x z) eqn:X_Z
  ; destruct (leb_bid x y) eqn:X_Y
  ; destruct (leb_bid y x) eqn:Y_X
  ; try (rewrite Y_Z)
  ; try (rewrite X_Z)
  ; try (rewrite X_Y)
  ; try (rewrite Y_X)
  ; try reflexivity
  ; eq_neq_le_bid
  ; try discriminate
  ; repeat (match goal with
    | h : lt_bid _ _ |- _ => apply lt_le in h
    end)
  ; try (apply le_bid_eq
         ; try assumption
         ; try (eapply le_bid_trans ; eassumption)
         ; try now apply lt_le)
  ; try (apply le_bid_antisym ; assumption).
  - eapply le_bid_trans in X_Z ; try eassumption.
    apply le_bid_antisym ; assumption.
  - eapply le_bid_trans in Y_Z ; try eassumption.
    apply le_bid_antisym ; assumption.
Qed.


Lemma max_bid'_cons : forall l x d,
    le_bid x d ->
    le_bid x (max_bid' l d).
Proof.
  induction l ; intros ; simpl.
  assumption.
  destruct (leb_bid d a) eqn:E ; unfold max ; rewrite E.
  - apply IHl.
    unfold leb_bid in E.
    apply Bool.orb_prop in E ; destruct E as [E | E].
    rewrite ltb_bid_true in E.
    eapply lt_bid_trans_le in H; try eassumption. now apply lt_le.
    now rewrite eqb_bid_eq in E ; subst.
  - now apply IHl.
Qed.

Corollary max_bid'_cons_refl : forall x l,
    le_bid x (max_bid' l x).
Proof.
  intros.
  apply max_bid'_cons.
  apply leb_bid_refl.
Qed.

Lemma le_bid_max_cons_eq : forall x l, le_bid x (max_bid (x::l)).
Proof.
  intros.
  cbn.
  rewrite max_refl.
  apply max_bid'_cons_refl.
Qed.

Lemma max_bid_bot_l : forall b, max bot b = b.
Proof.
  intros.
  unfold max.
  pose proof (BOT:= le_bid_bot b) ; unfold le_bid in BOT
  ; rewrite BOT ; clear BOT.
  reflexivity.
Qed.

Lemma leb_bid_bot_r : forall b, le_bid b bot -> b = bot.
Proof.
  intros.
  pose proof (BOT:= le_bid_bot b).
  apply le_bid_antisym ; assumption.
Qed.

Lemma max_bid_bot_r : forall b, max b bot = b.
Proof.
  intros.
  unfold max.
  destruct ( leb_bid b bot ) eqn:E ; auto.
  rewrite leb_bid_true in E.
  apply leb_bid_bot_r in E. auto.
Qed.

Lemma max_bid'_app : forall l1 l2 x y,
    max_bid' (l1 ++ l2) (max x y) = max (max_bid' l1 x) (max_bid' l2 y).
Proof.
  intros l1 l2.
  induction l1 as [| z l1 IH] ; intros.
  - cbn.
    generalize dependent y.
    induction l2 ; intros.
    + reflexivity.
    + cbn. rewrite <- IHl2.
      replace (max (max x y) a) with (max x (max y a)).
      reflexivity.
      rewrite (max_comm _ a).
      rewrite max_assoc.
      now rewrite (max_comm a _).
  -  cbn.
     replace (max (max x y) z) with (max (max x z) y).
     rewrite IH. reflexivity.
     rewrite max_comm.
     rewrite (max_comm x z).
     rewrite max_assoc.
     rewrite max_comm.
     now rewrite (max_comm y x).
Qed.

Lemma max_bid'_app_l : forall l1 l2 x y,
    le_bid y x ->
    max_bid' (l1 ++ l2) x = max (max_bid' l1 x) (max_bid' l2 y).
Proof.
  intros.
  replace x with (max x y) at 1.
  apply max_bid'_app.
  unfold max.
  destruct (leb_bid x y) eqn:E ; auto.
  apply le_bid_antisym ; try assumption.
Qed.

Lemma max_bid'_app_r : forall l1 l2 x y,
    le_bid x y ->
    max_bid' (l1 ++ l2) y = max (max_bid' l1 x) (max_bid' l2 y).
Proof.
  intros.
  replace y with (max x y) at 1.
  apply max_bid'_app.
  unfold max.
  now apply leb_bid_true in H ; rewrite H.
Qed.

Lemma max_bid_app : forall l1 l2,
    max_bid (l1++l2) = max (max_bid l1) (max_bid l2).
Proof.
  intros.
  unfold max_bid.
Admitted.

Lemma max_bid_app' : forall l1 l2,
    max_bid (l1++l2) = (max_bid l1) \/ max_bid (l1++l2) = (max_bid l2).
Proof.
  intros.
  rewrite max_bid_app.
  unfold max.
  destruct (leb_bid (max_bid l1) (max_bid l2)) eqn:E ; intuition.
Qed.

Lemma le_bid_max_trans : forall x y z,
    le_bid x y ->
    le_bid x (max z y).
Proof.
  intros.
  unfold max.
  destruct (leb_bid z y) eqn:E ; try assumption.
  apply not_le_lt in E.
  assert (lt_bid y z ) by (now unfold lt_bid) ; clear E.
  apply lt_le.
  eapply lt_bid_trans_le in H0 ; eassumption.
Qed.

Theorem max_bid_spec : forall l,
    Forall (fun b => le_bid b (max_bid l)) l.
Proof.
  induction l ; intros.
  - apply Forall_nil.
  - apply Forall_cons.
    + apply le_bid_max_cons_eq.
    + rewrite Forall_forall in *.
      intros * IN ; apply IHl in IN.
      rewrite Util.list_cons_app.
      rewrite max_bid_app. cbn.
      rewrite max_refl.
      now apply le_bid_max_trans.
Qed.

Lemma max_bid_spec_intro : forall l max,
    (max_bid l) = max ->
    Forall (fun b => le_bid b max) l.
Proof.
  intros.
  rewrite <- H.
  apply max_bid_spec.
Qed.

Require Import List.
Lemma non_nil : forall {T} (l : list T),
    (length l >= 1)%nat ->
    exists h t, l = h::t.
Proof.
  intros.
  induction l.
  simpl in H ; lia.
  eexists.
  eexists. reflexivity.
Qed.

Lemma min_bid'_cons : forall l x d,
    le_bid d x ->
    le_bid (min_bid' l d) x.
Proof.
  induction l ; intros ; simpl.
  assumption.
  unfold min ; destruct (leb_bid d a) eqn:E.
  - now apply IHl.
  - apply IHl.
    unfold leb_bid in E.
    apply orb_false_iff in E ; destruct E.
    apply ltb_assym in H0 ; destruct H0.
    rewrite ltb_bid_true in H0.
    apply lt_le in H0. eapply le_bid_trans ; eassumption.
    rewrite H0 in H1 ; discriminate.
Qed.

Corollary min_bid'_cons_refl : forall x l,
    le_bid (min_bid' l x) x.
Proof.
  intros.
  apply min_bid'_cons.
  apply le_bid_refl.
Qed.

Lemma le_bid_min_cons_eq :
forall (x : raw_id) (l : list raw_id), le_bid (min_bid (x :: l)) x.
Proof.
  intros.
  cbn.
  rewrite min_refl.
  apply min_bid'_cons_refl.
Qed.


Lemma min_bid_app :
  forall l1 l2 : list block_id,
    min_bid (l1 ++ l2) = min (min_bid l1) (min_bid l2).
Admitted.

Lemma le_bid_min_trans : forall x y z,
    le_bid y x ->
    le_bid (min z y) x.
Proof.
  intros.
  unfold min.
  destruct (leb_bid z y) eqn:E ; try assumption.
  rewrite leb_bid_true in E.
  eapply le_bid_trans ; eassumption.
Qed.

Theorem min_bid_spec : forall l,
    Forall (fun b => le_bid (min_bid l) b) l.
Proof.
  induction l ; intros.
  - apply Forall_nil.
  - apply Forall_cons.
    + apply le_bid_min_cons_eq.
    + rewrite Forall_forall in *.
      intros * IN ; apply IHl in IN.
      rewrite Util.list_cons_app.
      rewrite min_bid_app. cbn.
      rewrite min_refl.
      now apply le_bid_min_trans.
Qed.


Lemma min_bid_spec_intro : forall l m,
    (min_bid l) = m ->
    Forall (fun b => le_bid m b) l.
Proof.
  intros.
  rewrite <- H.
  apply min_bid_spec.
Qed.

Lemma le_min_max' : forall l dmin dmax,
    le_bid dmin dmax -> le_bid (min_bid' l dmin) (max_bid' l dmax).
Proof.
  induction l.
  - now simpl.
  - intros.
    simpl.
    unfold min, max.
    apply IHl.
    destruct ( leb_bid dmin a ) eqn:Emin, ( leb_bid dmax a ) eqn:Emax
    ; try rewrite leb_bid_true in *
    ; try assumption.
    + apply le_bid_refl.
    + apply not_le_lt in Emin,Emax.
      rewrite ltb_bid_true in Emax.
      now apply lt_le.
Qed.

Lemma le_min_max : forall l, le_bid (min_bid l) (max_bid l).
Proof.
  intros.
  unfold min_bid, max_bid.
  induction l.
  - simpl ; apply le_bid_refl.
  - simpl ; rewrite min_refl, max_refl.
    apply le_min_max'.  apply le_bid_refl.
Qed.




Lemma lt_bid_false :
  forall x y, lt_bid x y -> lt_bid y x -> False.
Proof.
  intros.
  unfold lt_bid,ltb_bid in *.
  destruct x,y ; try discriminate.
  destruct (String_as_OT.cmp s s0) eqn:S_S0
  ; destruct (String_as_OT.cmp s0 s) eqn:S0_S
  ; try discriminate.
  rewrite String_as_OT.cmp_lt in *.
  eapply not_lt_string_refl ; eassumption.
  lia.
  lia.
Qed.

Lemma le_bid_eq :
  forall x y, le_bid x y -> le_bid y x -> x=y.
Proof.
  intros.
  unfold le_bid,leb_bid in *.
  apply orb_true_iff in H,H0.
  rewrite ltb_bid_true in *.
  rewrite eqb_bid_eq in *.
  intuition.
  apply lt_bid_false in H1 ; try auto ; try contradiction.
Qed.

Lemma le_lt_bid :
  forall x y, le_bid x y -> lt_bid y x -> False.
Proof.
  intros.
  unfold le_bid, leb_bid in H.
  apply orb_true_iff in H.
  rewrite ltb_bid_true in *.
  rewrite eqb_bid_eq in *.
  destruct H.
  apply lt_bid_false in H ; auto.
  subst.
  now apply lt_bid_irrefl in H0.
Qed.

Lemma leb_bid_neq :
  forall x y, leb_bid x y = false -> x <> y.
Proof.
  repeat intro ; subst.
  now rewrite leb_bid_refl in H.
Qed.

Lemma max_max_commmute :
  forall n1 n2 m1 m2, max (max n1 n2) (max m1 m2) = max (max n1 m1) (max n2 m2).
Proof.
  intros.
  unfold max.
  destruct (leb_bid n1 n2) eqn:N1_N2
  ; destruct (leb_bid n2 m2) eqn:N2_M2
  ; destruct (leb_bid m1 m2) eqn:M1_M2
  ; destruct (leb_bid n1 m1) eqn:N1_M1
  ; destruct (leb_bid m1 n2) eqn:M1_N2
  ; destruct (leb_bid m2 n1) eqn:M2_N1
  ; destruct (leb_bid n1 m2) eqn:N1_M2
  ; destruct (leb_bid n2 m1) eqn:N2_M1
  ; try (rewrite N1_N2)
  ; try (rewrite M1_M2)
  ; try (rewrite N2_M2)
  ; try (rewrite M1_N2)
  ; try reflexivity
  ; eq_neq_le_bid
  ; try discriminate
  ; repeat (match goal with
    | h : lt_bid _ _ |- _ => apply lt_le in h
    end)
  ; try (apply le_bid_eq
         ; try assumption
         ; try (eapply le_bid_trans ; eassumption)
         ; try now apply lt_le).
Qed.

Lemma min_min_commmute :
  forall n1 n2 m1 m2, min (min n1 n2) (min m1 m2) = min (min n1 m1) (min n2 m2).
Proof.
  intros.
  unfold min.
  destruct (leb_bid n1 n2) eqn:N1_N2
  ; destruct (leb_bid n2 m2) eqn:N2_M2
  ; destruct (leb_bid m1 m2) eqn:M1_M2
  ; destruct (leb_bid n1 m1) eqn:N1_M1
  ; destruct (leb_bid m1 n2) eqn:M1_N2
  ; destruct (leb_bid m2 n1) eqn:M2_N1
  ; destruct (leb_bid n1 m2) eqn:N1_M2
  ; destruct (leb_bid n2 m1) eqn:N2_M1
  ; try (rewrite N1_N2)
  ; try (rewrite M1_M2)
  ; try (rewrite N2_M2)
  ; try (rewrite M1_N2)
  ; try reflexivity
  ; eq_neq_le_bid
  ; try discriminate
  ; repeat (match goal with
    | h : lt_bid _ _ |- _ => apply lt_le in h
    end)
  ; try (apply le_bid_eq
         ; try assumption
         ; try (eapply le_bid_trans ; eassumption)
         ; try now apply lt_le)
  ; try (eapply le_bid_trans ; [| eassumption] ; eassumption).
Qed.

Definition mk_anon (n : nat) := Anon (Z.of_nat n).
Lemma neq_mk_anon : forall n1 n2, mk_anon n1 <> mk_anon n2 <-> n1 <> n2.
Proof.
  intros.
  unfold mk_anon.
  split ; intro.
  - intros ->. now destruct H.
  - apply inj_neq in H.
    unfold Zne in H.
    intro.
    injection H0.
    intro.
    rewrite H1 in H .
    contradiction.
Qed.

Definition name := mk_anon.
Lemma neq_name : forall n1 n2, name n1 <> name n2 <-> n1 <> n2.
Proof.
  intros.
  unfold name. now apply neq_mk_anon.
Qed.

Definition is_anon (b : block_id) : Prop :=
  exists n, b = Anon n.

Lemma is_anon_name : forall n, is_anon (name n).
Proof.
  intros.
  unfold name, mk_anon.
  unfold is_anon.
  now eexists.
Qed.

Definition next_anon (b : block_id) :=
  match b with
  | Name s => Name s
  | Raw n => Raw (n+1)%Z
  | Anon n => Anon (n+1)%Z
  end.

Lemma next_anon_name : forall n, next_anon (name n) = name (n+1).
Proof.
  intros.
  unfold next_anon, name, mk_anon.
  rewrite Nat2Z.inj_add.
  reflexivity.
Qed.

Lemma lt_bid_S : forall n m,
    lt_bid m (name n) -> lt_bid m (name (S n)).
Proof.
  intros.
  unfold name, mk_anon in *.
  unfold lt_bid, ltb_bid in *.
  destruct m ; auto.
  rewrite Nat2Z.inj_succ.
  rewrite Zaux.Zlt_bool_true ; auto.
  lia.
Qed.

Lemma lt_bid_next : forall b, is_anon b -> lt_bid b (next_anon b).
Proof.
  intros.
  unfold next_anon, is_anon in *.
  destruct H ; subst.
  unfold lt_bid.
  unfold ltb_bid.
  lia.
Qed.

Lemma name_neq : forall cb cb',
    cb <> cb' -> (name cb <> name cb').
Proof.
  intros. intro.
  unfold name,mk_anon in H0.
  injection H0 ; intro.
  rewrite Nat2Z.inj_iff in H1.
  subst. contradiction.
Qed.

Lemma lt_bid_name : forall (n n' : nat),
    (n < n')%nat -> lt_bid (name n) (name n').
Proof.
  intros.
  unfold lt_bid, name, mk_anon.
  simpl.
  lia.
Qed.

Lemma le_bid_name : forall (n n' : nat),
    (n <= n')%nat -> le_bid (name n) (name n').
Proof.
  intros.
  unfold le_bid, leb_bid, name, mk_anon.
  simpl.
  lia.
Qed.

Lemma max_name : forall n1 n2, max (name n1) (name n2) = name (Max.max n1 n2).
Proof.
  intros.
  unfold max.
  destruct (leb_bid (name n1) (name n2)) eqn:E.
  - unfold leb_bid in E.
    unfold name, mk_anon in *.
    apply orb_true_iff in E ; destruct E as [E | E]
    ; [ unfold ltb_bid in E
      | apply eqb_bid_eq in E ; injection E ; intros]
    ; now replace (Z.of_nat (Nat.max n1 n2)) with (Z.of_nat n2) by lia.
  - apply not_le_lt in E.
    unfold ltb_bid in E.
    unfold name, mk_anon in *.
    now replace (Z.of_nat (Nat.max n1 n2)) with (Z.of_nat n1) by lia.
Qed.

Lemma min_name : forall n1 n2, min (name n1) (name n2) = name (Min.min n1 n2).
Proof.
  intros.
  unfold min.
  destruct (leb_bid (name n1) (name n2)) eqn:E.
  - unfold leb_bid in E.
    unfold name, mk_anon in *.
    apply orb_true_iff in E ; destruct E as [E | E]
    ; [ unfold ltb_bid in E
      | apply eqb_bid_eq in E ; injection E ; intros]
    ; now replace (Z.of_nat (Nat.min n1 n2)) with (Z.of_nat n1) by lia.
  - apply not_le_lt in E.
    unfold ltb_bid in E.
    unfold name, mk_anon in *.
    now replace (Z.of_nat (Nat.min n1 n2)) with (Z.of_nat n2) by lia.
Qed.

Lemma le_max_cons : forall x l, le_bid (max_bid l) (max_bid (x :: l)).
Proof.
  intros.
Admitted.

Theorem notin_lt_max : forall l f,
    lt_bid (max_bid l) f -> ~ In f l.
Proof.
  induction l as [| x l' Hl' ] ; intros.
  - apply in_nil.
  - apply not_in_cons.
    split.
    + apply lt_bid_neq'. eapply lt_bid_trans_le ; try eassumption. apply max_bid'_cons_refl.
    + eapply Hl'.
      eapply lt_bid_trans_le ; try eassumption.
      apply le_max_cons.
Qed.

Lemma eqv_dec_p_eq : forall b b' r,
    eqb_bid b b' = r <-> (if Eqv.eqv_dec_p b b' then true else false) = r.
  intros.
  destruct r eqn:R.
  - destruct (Eqv.eqv_dec_p b b') eqn:E.
    + unfold Eqv.eqv,eqv_raw_id in e ; subst.
      now rewrite eqb_bid_refl.
    + unfold Eqv.eqv,eqv_raw_id in n.
      rewrite eqb_bid_eq.
      split ; intros ; subst. contradiction. inversion H.
  - destruct (Eqv.eqv_dec_p b b') eqn:E.
    + unfold Eqv.eqv,eqv_raw_id in e ; subst.
      now rewrite eqb_bid_refl.
    + unfold Eqv.eqv,eqv_raw_id in n ; subst.
      rewrite eqb_bid_neq.
      split ; intros ; auto.
Qed.

Lemma eqv_dec_p_refl : forall (b : block_id),
    (if Eqv.eqv_dec_p b b then true else false) = true.
Proof.
  intros.
  destruct (Eqv.eqv_dec_p b b) ; auto.
  unfold Eqv.eqv,eqv_raw_id in n ; auto.
Qed.

Lemma eqv_dec_p_eq_true : forall {T} b b' (xT xF : T),
    eqb_bid b b' = true -> (if Eqv.eqv_dec_p b b' then xT else xF) = xT.
Proof.
  intros ; destruct (Eqv.eqv_dec_p b b') eqn:E.
  - reflexivity.
  - unfold Eqv.eqv,eqv_raw_id in n ; subst.
    rewrite eqb_bid_eq in H. now apply n in H.
Qed.

Lemma eqv_dec_p_eq_false : forall {T} b b' (xT xF : T),
    eqb_bid b b' = false -> (if Eqv.eqv_dec_p b b' then xT else xF) = xF.
Proof.
  intros ; destruct (Eqv.eqv_dec_p b b') eqn:E.
  - unfold Eqv.eqv,eqv_raw_id in e ; subst.
    rewrite eqb_bid_neq in H. contradiction.
  - reflexivity.
Qed.

(** Definition and lemmas for remove specitic to block_id*)
Fixpoint remove_bid (x : block_id) (l : list block_id) :=
  match l with
  | [] => []
  | h::t => if (eqb_bid x h) then remove_bid x t else h::(remove_bid x t)
  end.

Lemma remove_spec : forall a l, ~ In a (remove_bid a l).
Proof.
  induction l.
  - simpl ; auto.
  - simpl.
    destruct (eqb_bid a a0) eqn:E.
    + assumption.
    + apply not_in_cons. rewrite eqb_bid_neq in E.
      intuition.
Qed.

Lemma remove_ListRemove :
  forall b l, remove_bid b l = List.remove Eqv.eqv_dec_p b l.
Proof.
  intros.
  induction l ; try reflexivity.
  simpl.
  destruct (eqb_bid b a) eqn:E ;
    match goal with
    | |- context[if (_ ?b1 ?b2) then ?xT else ?xF] =>
        try apply (eqv_dec_p_eq_true b1 b2 xT xF) in E
        ; try apply (eqv_dec_p_eq_false b1 b2 xT xF) in E
    end ; setoid_rewrite E.
  - assumption.
  - now f_equal.
Qed.

Lemma in_remove : forall l x y, List.In x (remove_bid y l) -> List.In x l.
Proof. intros.
       rewrite remove_ListRemove in H
       ; apply in_remove in H.
       intuition.
Qed.

Ltac in_list_rem :=
  match goal with
  | h: List.In _ _  |- _ => apply in_remove in h
  end.

Lemma remove_disjoint : forall (x : block_id) (l1 l2 : list block_id),
    l1 ⊍ l2 -> (remove_bid x l1) ⊍ l2.
Proof.
  intros.
  induction l1.
  now simpl.
  simpl.
  destruct (eqb_bid x a).
  - apply IHl1. now apply list_disjoint_cons_left in H.
  - apply list_disjoint_cons_l_iff in H ; destruct H.
    apply list_disjoint_cons_l.
    now apply IHl1. assumption.
Qed.

Lemma remove_notin : forall a l, ~ In a l -> (remove_bid a l) = l.
Proof.
  intros.
  rewrite remove_ListRemove.
  now apply notin_remove.
Qed.

Lemma remove_disjoint_remove : forall (x : block_id) (l1 l2 : list block_id),
    (remove_bid x l1) ⊍ (remove_bid x l2) <->
(remove_bid x l1) ⊍ l2.
Proof.
  induction l2 ; intros ; split ; simpl ; intros
  ; try apply list_disjoint_nil_r
  ; destruct (eqb_bid x a) eqn:E
  ; try (rewrite eqb_bid_eq in E ; subst)
  ; try (rewrite eqb_bid_neq in E).
  - apply list_disjoint_cons_r.
    apply IHl2 ; assumption.
    apply remove_spec.
  - apply list_disjoint_sym in H
    ; apply list_disjoint_cons_l_iff in H
    ; destruct H
    ; apply list_disjoint_sym in H.
    apply list_disjoint_cons_r
    ; [ apply IHl2 |]
    ; assumption.
  - apply list_disjoint_sym, remove_disjoint
    ; apply list_disjoint_sym.
    now apply list_disjoint_cons_right in H.
  - apply list_disjoint_sym in H
    ; apply list_disjoint_cons_l_iff in H
    ; destruct H
    ; apply list_disjoint_sym in H.
    apply list_disjoint_cons_r
    ; [ apply IHl2 |]
    ; assumption.
Qed.

Lemma remove_app:
  forall (x : block_id) (l1 l2 : list block_id),
    remove_bid x (l1 ++ l2) = remove_bid x l1 ++ remove_bid x l2.
Proof.
  intros.
  rewrite !remove_ListRemove.
  apply remove_app.
Qed.

Lemma remove_no_repet :
  forall a l,
    list_norepet (a::l) -> (remove_bid a (a::l)) = l.
Proof.
  intros.
  simpl.
  rewrite eqb_bid_refl.
  pose proof (remove_spec a l).
  assert (~ In a l).
  {
     intro.
     rewrite Util.list_cons_app in H ; apply list_norepet_app in H
     ; destruct H as [_ [_ ?]].
     unfold list_disjoint in H.
     assert (In a [a]) by (apply in_cns ; intuition).
     eapply H in H2 ; [|eassumption] ; contradiction.
  }
  apply remove_notin in H1.
  assumption.
Qed.

Lemma length_remove_hd_no_repet :
  forall l d,
    list_norepet l ->
    length (remove_bid (hd d l) l) = ((length l)-1)%nat.
Proof.
  intros.
  induction l. now simpl.
  apply remove_no_repet in H.
  replace (hd d (a :: l)) with a by now simpl.
  rewrite H.
  simpl ; lia.
Qed.

Lemma list_norepet_remove : forall l a,
    list_norepet l ->
    list_norepet (remove_bid a l).
Proof.
  intros.
  induction l ; try auto.
  simpl.
  destruct (eqb_bid a a0) ;
    [| apply list_norepet_cons ;
       [intro
        ; apply CFGC_Utils.in_remove in H0
        ; now inversion H|]]
  ; apply IHl
  ; rewrite list_cons_app in H
  ; eapply list_norepet_append_right
  ; eassumption.
Qed.


(* Misc lemmas related to vellvm *)

Lemma find_block_none_singleton :
  forall c term phis comm b b' , b<>b' <->
find_block
   (convert_typ []
                [{|
                      blk_id := b;
                   blk_phis := phis;
                   blk_code := c;
                   blk_term := term;
                   blk_comments := comm
                   |}]) b' = None.
Proof.
  intros.
  split; intros.
  - apply find_block_not_in_inputs.
    simpl; intuition.
  - simpl in H.
    unfold endo, Endo_id in H.
    destruct (if Eqv.eqv_dec_p b b' then true else false) eqn:E.
    + discriminate.
    + now rewrite <- eqv_dec_p_eq in E ; rewrite <- eqb_bid_neq.
Qed.



(* The following three are copied from vellvm,
   but with heterogeneous types T and T' for use with convert_typ *)

Lemma find_block_map_some' :
  forall {T T'} (f : block T -> block T') G b bk,
    (forall bk, blk_id (f bk) = blk_id bk) ->
    find_block G b = Some bk ->
    find_block (List.map f G) b = Some (f bk).
Proof.
  intros * ID; induction G as [| hd G IH]; intros FIND ; [inv FIND |].
  cbn in *.
  rewrite ID.
  break_match_goal; break_match_hyp; intuition.
  inv FIND; auto.
Qed.

Lemma find_block_map_none' :
  forall {T T'} (f : block T -> block T') G b,
    (forall bk, blk_id (f bk) = blk_id bk) ->
    find_block G b = None ->
    find_block (List.map f G) b = None.
Proof.
  intros * ID; induction G as [| hd G IH]; intros FIND; [reflexivity |].
  cbn in *.
  rewrite ID.
  break_match_goal; break_match_hyp; intuition.
  inv FIND; auto.
Qed.

Lemma find_block_map' :
  forall {T T'} (f : block T -> block T') G b,
    (forall bk, blk_id (f bk) = blk_id bk) ->
    find_block (List.map f G) b = option_map f (find_block G b).
Proof.
  intros.
  destruct (find_block G b) eqn:EQ.
  eapply find_block_map_some' in EQ; eauto.
  eapply find_block_map_none' in EQ; eauto.
Qed.

Lemma find_app :
  forall {A} (l1 l2 : list A) f x,
    List.find f (l1 ++ l2) = Some x ->
    List.find f l1 = Some x \/ List.find f l2 = Some x.
Proof.
  intros.
  induction l1.
  - now right.
  - simpl in *.
    break_match; tauto.
Qed.



Lemma find_block_app_wf :
  forall {T : Set} (x : block_id) [b : block T] (bs1 bs2 : ocfg T),
    wf_ocfg_bid (bs1 ++ bs2)%list ->
    find_block (bs1 ++ bs2) x = Some b ->
    find_block bs1 x = Some b \/ find_block bs2 x = Some b .
Proof.
  intros.
  unfold find_block in H0.
  now apply find_app.
Qed.

Lemma outputs_successors : forall {typ} (cfg : ocfg typ) o,
    List.In o (outputs cfg) ->
    exists bk, List.In bk cfg /\ List.In o (successors bk).
Proof.
  induction cfg; intros.
  - destruct H.
  - cbn in H. rewrite outputs_acc in H.
    apply List.in_app_iff in H. destruct H.
    + exists a. simpl. tauto.
    + apply IHcfg in H.
      destruct H. exists x.
      simpl. tauto.
Qed.

Lemma successors_outputs : forall {typ} (cfg : ocfg typ) o bk,
    List.In bk cfg ->
    List.In o (successors bk) ->
    List.In o (outputs cfg).
Proof.
  induction cfg; intros.
  - destruct H.
  - cbn. rewrite outputs_acc.
    apply List.in_app_iff.
    destruct H.
    + left. now subst a.
    + right. apply IHcfg in H0; assumption.
Qed.

Lemma convert_typ_inputs : forall bk,
    inputs (convert_typ nil bk) = inputs bk.
Proof.
  intros.
  unfold inputs, convert_typ, ConvertTyp_list, tfmap, TFunctor_list'.
  rewrite List.map_map.
  reflexivity.
Qed.

Lemma convert_typ_successors : forall (bk : block typ),
    successors (convert_typ nil bk) = successors bk.
Proof.
  intros.
  apply convert_typ_terminator_outputs.
Qed.

Notation conv := (convert_typ []).

Lemma find_block_some_conv :
  forall g bid bk,
    find_block g bid = Some bk ->
    find_block (conv g) bid = Some (conv bk).
Proof.
  intros.
  unfold conv in *.
  unfold ConvertTyp_list, tfmap, TFunctor_list'.
  apply (find_block_map_some' _ g bid bk) ; [|assumption].
  apply blk_id_convert_typ.
Qed.

Lemma find_block_none_conv :
  forall g bid,
    find_block g bid = None ->
    find_block (conv g) bid = None.
Proof.
  intros.
  unfold conv in *.
  unfold ConvertTyp_list, tfmap, TFunctor_list'.
  apply (find_block_map_none' _ g bid) ; [|assumption].
  apply blk_id_convert_typ.
Qed.


Ltac find_block_conv :=
  match goal with
  | h:context[ find_block _ _ = None ] |- _ =>
      apply find_block_none_conv in h
  | h:context[ find_block _ _ = Some _ ] |- _ =>
      apply find_block_some_conv in h
  end.


Lemma no_reentrance_conv :
  forall g1 g2,
    no_reentrance g1 g2 <-> no_reentrance (conv g1) (conv g2).
Proof.
  intros.
  unfold no_reentrance.
  now rewrite convert_typ_outputs, convert_typ_inputs.
Qed.

Lemma no_duplicate_bid_conv :
  forall g1 g2,
    no_duplicate_bid g1 g2 <-> no_duplicate_bid (conv g1) (conv g2).
Proof.
  intros.
  unfold no_duplicate_bid.
  now rewrite 2 convert_typ_inputs.
Qed.

Lemma independent_flows_conv :
  forall g1 g2,
    independent_flows g1 g2 <-> independent_flows (conv g1) (conv g2).
Proof.
  intros.
  unfold independent_flows.
  rewrite <- 2 no_reentrance_conv.
  now rewrite no_duplicate_bid_conv.
Qed.

Lemma inputs_app : forall {T} (g1 g2 : ocfg T), inputs (g1++g2) = inputs g1 ++ inputs g2.
Proof.
  intros.
  unfold inputs.
  apply Coqlib.list_append_map.
Qed.

Lemma typ_to_dtyp_pair :
  forall (t : typ) (e : exp typ),
    (typ_to_dtyp [] t, convert_typ [] e) = tfmap (typ_to_dtyp []) (t, e).
Proof.
  intros.
  now unfold tfmap, TFunctor_texp, convert_typ, ConvertTyp_exp, tfmap.
Qed.