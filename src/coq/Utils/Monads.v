From Coq Require Import
     List
     Morphisms.

From ExtLib Require Import
     Structures.Monads
     Data.Monads.EitherMonad
     Data.Monads.IdentityMonad.

From ITree Require Import
     Basics.Monad Basics.MonadState.

From Vellvm Require Import
     Utils.Util.

Import Monads.

Import MonadNotation.
Import ListNotations.

Open Scope monad.

(* Monads ------------------------------------------------------------------- *)
(* TODO: Add to ExtLib *)

Section monad.
  Variable m : Type -> Type.
  Variable M : Monad m.
  
  Fixpoint monad_fold_right {A B} (f : B -> A -> m B) (l:list A) (b : B) : m B :=
    match l with
    | [] => ret b
    | x::xs => 
      r <- monad_fold_right f xs b ;;
      f r x
    end.

Definition monad_app_fst {A B C} (f : A -> m C) (p:A * B) : m (C * B)%type :=
  let '(x,y) := p in
  z <- f x ;;
  ret (z,y).

Definition monad_app_snd {A B C} (f : B -> m C) (p:A * B) : m (A * C)%type :=
  let '(x,y) := p in
  z <- f y ;;
  ret (x,z).

Definition map_monad {m : Type -> Type} {H : Monad m} {A B} (f:A -> m B) : list A -> m (list B) :=
  fix loop l :=
    match l with
    | [] => ret []
    | a::l' =>
      b <- f a ;;
      bs <- loop l' ;;
      ret (b::bs)  
    end.

Definition map_monad_ {A B}
  (f: A -> m B) (l: list A): m unit :=
  map_monad f l;; ret tt.

Fixpoint sequence {a} (ms : list (m a)) : m (list a)
  := map_monad id ms.

Fixpoint foldM {a b} (f : b -> a -> m b ) (acc : b) (l : list a) : m b
  := match l with
     | [] => ret acc
     | (x :: xs) =>
       b <- f acc x;;
       foldM f b xs
     end.

End monad.
Arguments monad_fold_right {_ _ _ _}.
Arguments monad_app_fst {_ _ _ _ _}.
Arguments monad_app_snd {_ _ _ _ _}.
Arguments map_monad {_ _ _ _}.
Arguments map_monad_ {_ _ _ _}.
Arguments sequence {_ _ _}.
Arguments foldM {_ _ _ _}.




Global Instance EqM_sum {E} : Monad.Eq1 (sum E) :=
  fun (a : Type) (x y : sum E a) => x = y.


Global Instance EqMProps_sum {E} : Monad.Eq1Equivalence (sum E).
constructor; intuition.
repeat intro. etransitivity; eauto.
Defined.


Global Instance MonadLaws_sum {T} : Monad.MonadLawsE (sum T).
  constructor.
  - intros. repeat red. cbn. auto.
  - intros. repeat red. cbn. destruct x eqn: Hx; auto.
  - intros. repeat red. cbn.
    destruct x; auto.
  - repeat intro. repeat red. cbn. repeat red in H. rewrite H.
    repeat red in H0. destruct y; auto.
Qed.


Global Instance EqM_eitherT {E} {M} `{Monad.Eq1 M} : Monad.Eq1 (eitherT E M)
  := fun (a : Type) x y => Monad.eq1 (unEitherT x) (unEitherT y).


Global Instance Eq1Equivalence_eitherT :
  forall {M : Type -> Type} {H : Monad M} {H0 : Monad.Eq1 M} E,
    Monad.Eq1Equivalence M -> Monad.Eq1Equivalence (eitherT E M).
Proof.
  constructor; intuition;
  repeat intro.
  - unfold Monad.eq1, EqM_eitherT.
    reflexivity.
  - unfold Monad.eq1, EqM_eitherT.
    symmetry.
    auto.
  - unfold Monad.eq1, EqM_eitherT.
    etransitivity; eauto.
Qed.

(* TODO: move this *)

Global Instance Eq1_ident : Monad.Eq1 IdentityMonad.ident
  := {eq1 := fun A => Logic.eq}.


Global Instance Eq1Equivalence_ident : Monad.Eq1Equivalence IdentityMonad.ident.
Proof.
  split; red.
  - intros x.
    reflexivity.
  - intros x y H.
    rewrite H.
    reflexivity.
  - intros x y z H H0.
    rewrite H. rewrite H0.
    reflexivity.
Defined.


Global Instance MonadLawsE_ident : Monad.MonadLawsE IdentityMonad.ident.
Proof.
  split; intros *.
  - reflexivity.
  - destruct x; reflexivity.
  - cbn. reflexivity.
  - unfold Proper, respectful.
    intros x y H x0 y0 H0.
    cbn.
    rewrite H.
    rewrite H0.
    reflexivity.
Defined.

Lemma match_ret_sum :
  forall {X Y M} `{HM: Monad M} `{EQM : Eq1 M} `{EQV : @Eq1Equivalence M HM EQM} (ma : (X + Y)%type),
    match ma with
    | inl a => ret (inl a)
    | inr a => ret (inr a)
    end ≈ @ret M _ _ ma.
Proof.
  intros X Y M HM EQM EQV ma.
  destruct ma; reflexivity.
Qed.


Global Instance MonadLaws_eitherT {E} {M} `{HM : Monad M} `{EQM : Eq1 M} `{EQV : @Eq1Equivalence M HM EQM} `{@Monad.MonadLawsE M EQM _} : Monad.MonadLawsE (eitherT E M).
Proof.
  split; intros *.
  - cbn.
    destruct H.
    do 2 red.
    cbn. intros.

    rewrite bind_ret_l.
    reflexivity.
  - cbn.
    do 2 red.
    cbn.
    destruct x as [x].
    cbn.

    setoid_rewrite match_ret_sum.
    rewrite bind_ret_r.
    reflexivity.
  - cbn.
    do 2 red.
    destruct x as [x].
    cbn.

    rewrite bind_bind.
    
    assert (forall v : (E + A)%type,
              xM <- match v with
                   | inl x0 => ret (inl x0)
                   | inr x0 => unEitherT (f x0)
                   end;;
              match xM with
              | inl x0 => ret (inl x0)
              | inr x0 => unEitherT (g x0)
              end ≈
                  match v with
                  | inl x0 => ret (inl x0)
                  | inr x0 =>
                    xM0 <- unEitherT (f x0);;
                    match xM0 with
                    | inl x1 => ret (inl x1)
                    | inr x1 => unEitherT (g x1)
                    end
                  end).
    { intros [e | a].
      rewrite bind_ret_l; reflexivity.
      reflexivity.
    }

    setoid_rewrite H0.
    reflexivity.
  - unfold Proper, respectful.
    intros x y H0 x0 y0 H1.
    cbn.
    do 2 red.
    cbn.

    do 2 red in H0.
    destruct H.

    do 3 red in H1.
    
    unfold Proper, respectful in Proper_bind.
    apply Proper_bind; eauto.
    intros a.
    destruct a; eauto.
    reflexivity.
Defined.


Global Existing Instance MonadState.MonadLawsE_stateTM.



