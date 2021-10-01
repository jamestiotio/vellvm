From Coq Require Import
     Lia
     List
     String
     ZArith.

From ExtLib Require Import FMapAList.

From ITree Require Import
     ITree
     ITreeFacts.

From Vellvm Require Import
     Handlers.Handlers
     Semantics
     Syntax
     Syntax.ScopeTheory
     Utils.AListFacts
     Utils.PostConditions
     Utils.Tactics.
From Imp2Vir Require Import Fin Imp.

From Imp2Vir Require Import Utils Relabel Vec Unique CvirCombinators CvirCombinatorsWF CompileExpr Imp2Cvir.

(* Denotation of a [cvir] construct. *)

Definition denote_cvir_gen {ni no} (ir : cvir ni no) vi vo vt (bid bid' : fin ni) :=
  denote_ocfg (convert_typ nil (blocks ir vi vo vt)) (nth vi bid', nth vi bid).

(*
NOTE: we should be able to take any three disjoint sets
of names [vi,vo,vt] to feed our [ir].
One way is to take as a "canonical" name the first integers:
this is what the current version does with [build_map].
Another would be to be parameterized by three such sets ---
lemmas about it would assume that they are disjoint.
We currently suspect that the later formulation might be
necessary to express generic lemmas, even if "at the top level"
we will always use the canonical naming. It is not yet clear though.
*)

Definition build_map a b := map Anon (map Z.of_nat (seq a b)).

Definition blocks_default {ni no} (ir : cvir ni no) :=
  let vi := build_map 0 ni in
  let vo := build_map ni no in
  let vt := build_map (ni + no) (n_int ir) in
  blocks ir vi vo vt.

Definition denote_cvir {ni no} (ir : cvir ni no) bid bid' :=
  let vi := build_map 0 ni in
  let vo := build_map ni no in
  let vt := build_map (ni + no) (n_int ir) in
  denote_cvir_gen ir vi vo vt bid bid'.

(* In particular: can we have a reasoning principle to prove that two
  cvir are related?
  That is a lemma that would allow us to conclude something along the lines of:
  [eutt R (denote_cvir ir1 n org) (denote_cvir ir2 m org)]
  by chosing an invariant I and having two proof obligations:
  - I holds initially (of n m and org?)
  - If we start from arguments in I, then we prove something about
  ir1.(blocks) and ir2.(blocks) at these arguments.

This lemma would likely be based on and ressemble the low level lemma on [iter],
but could be more precise since we are here considering bodies of a specific shape:

Lemma eutt_iter_gen :
forall {F : Type -> Type} {A B : Type} {R : A -> A -> Prop} {S : B -> B -> Prop},
  forall body1 body2,
   (forall a a', R a a' -> eutt (sum_rel R S) (body1 a) (body2 a')) ->
   forall  a a', R a a' -> eutt S (iter body1 a) (iter body2 a')

The drafted proof below of [denote_cvir_merge] uses [eutt_iter_gen] but
leads to some non-trivial arithmetic and reasoning on renaming.
Maybe using this hypothetical higher level lemma could sooth the pain.
 *)

Lemma firstn_build_map : forall i n m,
firstn n (build_map i (n + m)) = build_map i n.
Proof.
  intros.
  unfold firstn, build_map, seq, map.
  apply vector_proj1_unique.
  simpl.
  rewrite !firstn_map.
  f_equal. f_equal.
  apply firstn_seq.
Qed.

Lemma skipn_build_map : forall i n m,
skipn n (build_map i (n + m)) = build_map (i + n) m.
Proof.
  intros.
  apply vector_proj1_unique.
  simpl.
  rewrite !skipn_map.
  do 2 f_equal.
  apply skipn_seq.
Qed.

Lemma nth_build_map : forall i n k,
  nth (build_map i n) k = Anon (Z.of_nat(i + proj1_sig k)).
Proof.
  intros.
  unfold build_map, seq.
  erewrite nth_destruct.
  destruct k.
  simpl.
  rewrite !List.map_nth.
  rewrite List.seq_nth ; try auto.
  Unshelve. exact O.
Qed.

Lemma cvir_inputs_build_map : forall {ni no} ir fi fo ft n,
  cvir_ids_WF ir ->
  cvir_inputs_used ir ->
  List.In (Anon (Z.of_nat n)) (inputs (blocks ir (build_map fi ni) (build_map fo no) (build_map ft (n_int ir)))) <->
  (n >= fi /\ n < fi + ni)%nat \/ (n >= ft /\ n < ft + n_int ir)%nat.
Proof.
  split; intros.
  - apply cvir_inputs in H1; try assumption.
    apply List.in_app_iff in H1.
    simpl in H1.
    rewrite 2 List.map_map in H1.
    setoid_rewrite List.in_map_iff in H1.
    destruct H1 as [(? & ? & ?) | (? & ? & ?)];
    inv H1;
    apply Nat2Z.inj in H4; subst x;
    apply List.in_seq in H2;
    tauto.
  - apply cvir_inputs; try assumption.
    apply vector_in_app_iff.
    cbn.
    rewrite !List.map_map.
    setoid_rewrite List.in_map_iff.
    setoid_rewrite List.in_seq.
    destruct H1; [ left | right ];
    exists n;
    tauto.
Qed.

Lemma cvir_outputs_build_map' : forall {ni no} ir fi fo ft o,
  cvir_ids_WF ir ->
  List.In o (outputs (blocks ir (build_map fi ni) (build_map fo no) (build_map ft (n_int ir)))) ->
  exists n,
    o = Anon (Z.of_nat n) /\
    ((n >= fi /\ n < fi + ni)%nat \/ (n >= fo /\ n < fo + no)%nat \/ (n >= ft /\ n < ft + n_int ir)%nat).
Proof.
  intros.
  unfold build_map in H0.
  apply cvir_outputs in H0; try assumption.
  cbn in H0.
  rewrite !List.in_app_iff in H0.
  rewrite !List.map_map in H0.
  rewrite !List.in_map_iff in H0.
  setoid_rewrite List.in_seq in H0.
  destruct H0 as [(? & ? & ?) | [(? & ? & ?) | (? & ? & ?)]];
  exists x; subst o;
  tauto.
Qed.

Lemma cvir_outputs_build_map : forall {ni no} ir fi fo ft n,
  cvir_ids_WF ir ->
  List.In (Anon (Z.of_nat n)) (outputs (blocks ir (build_map fi ni) (build_map fo no) (build_map ft (n_int ir)))) ->
  (n >= fi /\ n < fi + ni)%nat \/ (n >= fo /\ n < fo + no)%nat \/ (n >= ft /\ n < ft + n_int ir)%nat.
Proof.
  intros.
  apply cvir_outputs_build_map' in H0; try assumption.
  destruct H0 as (? & ? & ?). inv H0.
  apply Nat2Z.inj in H3. subst x.
  tauto.
Qed.

From Coq Require Import Morphisms.
Require Import ITree.Basics.HeterogeneousRelations.
Import ITreeNotations.
(*Import SemNotations.*)


Lemma unique_vector_build_map :
  forall fi fo ft ni no nt,
  (fi + ni <= fo)%nat ->
  (fo + no <= ft)%nat ->
  unique_vector (build_map fi ni ++ build_map fo no ++ build_map ft nt).
Admitted.

Lemma unique_vector_build_map' :
  forall fi fo ni no,
  (fi + ni <= fo)%nat ->
  unique_vector (build_map fi ni ++ build_map fo no).
Proof.
  intros.
  eapply unique_vector_app1 with (v2 := build_map (fo + no) 0).
  apply unique_vector_assoc.
  apply unique_vector_build_map; lia.
Qed.

Theorem cvir_relabel : forall {ni no} (ir : cvir ni no) vi vi' vo vo' vt vt',
  cvir_relabel_WF ir ->
  unique_vector (vi ++ vo ++ vt) ->
  unique_vector (vi' ++ vo' ++ vt') ->
  blocks ir vi' vo' vt' =
  ocfg_relabel (vec_build_map (vi++vo++vt) (vi'++vo'++vt')) (blocks ir vi vo vt).
Proof.
  intros.
  apply H; try assumption.
Qed.

(* If a CVIR is WF, its denotation is equivalent to itself modulo relabeling *)
Theorem eutt_cvir_relabel : forall {ni no} (ir : cvir ni no) vi vi' vo vo' vt vt' bid bid',
  cvir_WF ir ->
  unique_vector (vi ++ vo ++ vt) ->
  unique_vector (vi' ++ vo' ++ vt') ->
  eutt (ocfg_relabel_helper_rel (vec_build_map (vi++vo++vt) (vi'++vo'++vt')))
    (denote_cvir_gen ir vi vo vt bid bid')
    (denote_cvir_gen ir vi' vo' vt' bid bid').
Proof.
  intros * H H2 H3.
  unfold cvir_WF in H. destruct H as [_ [H' [H'' [H0 H1]]]].
  assert (H : cvir_ids_WF ir).
  { apply cvir_combine_in_out_ids_WF ; auto. }
  unfold denote_cvir_gen.
  rewrite (cvir_relabel ir vi vi' vo vo' vt vt'); try assumption.
  erewrite <- ocfg_relabel_convert_typ.
  apply eutt_ocfg_relabel; try assumption.
  - apply unique_vector_app1 in H2, H3.
    split; intro; [ apply H2 in H4 | apply H3 in H4 ]; now subst.
  - admit. (* by definition *)
  - admit.
  - admit.
  - unfold defined_map.
    intros.
    rewrite convert_typ_inputs in H4.
    apply cvir_inputs in H4; try assumption.
    apply key_in_alist_find; [ apply RelDec.RelDec_Correct_eq_typ |].
    unfold vec_build_map.
    rewrite combine_split.
    + simpl. rewrite !in_app_iff. rewrite !vector_in_app_iff in H4. tauto.
    + now rewrite 2 vector_length.
  - unfold defined_map.
    intros.
    rewrite convert_typ_outputs in H4.
    apply cvir_outputs in H4; try assumption.
    apply key_in_alist_find; [ apply RelDec.RelDec_Correct_eq_typ |].
    unfold vec_build_map.
    rewrite combine_split.
    + simpl. rewrite !in_app_iff. rewrite !vector_in_app_iff in H4. tauto.
    + now rewrite 2 vector_length.
  - admit.
Admitted.

(* TODO rewrite with has_post *)
Theorem denote_terminator_has_post_block_id :
  forall (I : block_id -> block_id -> Prop) bk,
  (forall (bid : block_id), List.In bid (successors bk) -> I bid bid) ->
  eutt (sum_rel I eq) (denote_terminator (blk_term bk)) (denote_terminator (blk_term bk)).
Proof.
  intros.
  unfold successors in H.
  unfold denote_terminator. simpl bind.
  break_match; try (apply eutt_eq_bind; tauto).
  - break_let.
    apply eutt_eq_bind.
    intro.
    apply eutt_Ret.
    now right.
  - apply eutt_Ret.
    now right.
  - break_let.
    apply eutt_eq_bind.
    intro.
    apply eutt_eq_bind.
    intro.
    break_match; try (apply eutt_eq_bind; tauto).
    break_match; apply eutt_Ret; left; apply H; cbn; tauto.
  - apply eutt_Ret. left. apply H. cbn. tauto.
  - admit. (* TERM_Switch *)
Admitted.

Theorem denote_cvir_merge_l' : forall
  ni1 no1 ni2 no2 (ir1 : cvir ni1 no1) (ir2 : cvir ni2 no2) bid,
  cvir_WF ir1 ->
  cvir_WF ir2 ->
  eutt eq
    (denote_cvir (merge_cvir ir1 ir2) (L ni2 bid) (L ni2 bid))
    (denote_cvir_gen ir1 (build_map 0 ni1) (build_map (ni1+ni2) no1) (build_map (ni1+ni2+(no1+no2)) (n_int ir1)) bid bid).
Proof.
  intros.
  unfold cvir_WF in H; destruct H as [WF31 [WF11' [WF11'' [WF21 _]]]].
  unfold cvir_WF in H0; destruct H0 as [WF32 [WF12' [WF12'' [WF22 _]]]].
  assert (WF11 : cvir_ids_WF ir1).
  { apply cvir_combine_in_out_ids_WF ; auto. }
  assert (WF12 : cvir_ids_WF ir2).
  { apply cvir_combine_in_out_ids_WF ; auto. }
  assert (WF3 : wf_ocfg_bid (blocks_default (merge_cvir ir1 ir2))). {
    apply unique_bid_wf_ocfg_bid.
    apply merge_cvir_unique; assumption.
    apply unique_vector_build_map'; lia.
  }
  cbn in WF3. rewrite !firstn_build_map, !skipn_build_map in WF3.
  (* case analysis on which subgraph we are in: *)
  - unfold denote_cvir, denote_cvir_gen.
    unfold merge_cvir.
    cbn.
    rewrite !firstn_build_map.
    rewrite !skipn_build_map.
    (* the invariant on the block identifiers we encounter during the computation *)
    (* maybe stating a higher level property on build_map or seq would be simpler? *)
    set (I := (fun (bid bid' : block_id) =>
      bid = bid' /\
      exists k, bid = Anon (Z.of_nat k) /\
      ((k >= 0 /\ k < 0+ni1) \/ (k >= ni1+ni2 /\ k < ni1+ni2+no1) \/ (k >= ni1+ni2+(no1+no2) /\ k < ni1+ni2+(no1+no2)+n_int ir1)))%nat).
    set (I' := (fun (fto fto' : block_id * block_id) =>
      fto = fto' /\
      I (snd fto) (snd fto'))).
    (* we apply [eutt_iter_gen] with this invariant *)
    apply (@KTreeFacts.eutt_iter_gen _ _ _ I').
    + (* We need to prove that it is indeed an invariant *)
      simpl bind.
      intros [? ?b1] [? ?b2] HI.
      destruct HI as (? & ? & ? & ?). inv H. clear H0.
      unfold convert_typ, ConvertTyp_list, tfmap, TFunctor_list' in *.
      rewrite !find_block_map'; try tauto.
      unfold option_map.
      repeat break_match; try discriminate.
      * apply find_block_app_wf in Heqo2; try assumption.
        destruct Heqo2. 2: {
          apply find_block_Some_In_inputs in H. destruct H1. simpl in H0. subst b2.
          apply cvir_inputs_build_map in H; try assumption. lia.
        }
        rewrite H in Heqo1. inv Heqo1.
        rewrite Heqo in Heqo0. inv Heqo0.
        apply eutt_clo_bind with (UU := sum_rel I eq).
        unfold denote_block.
        apply eutt_eq_bind. intros _.
        apply eutt_eq_bind. intros _.
        apply eutt_translate_gen.
        (* hard part: the terminator *)
        apply denote_terminator_has_post_block_id. {
          intros.
          unfold I.
          split; try reflexivity.
          inv Heqo.
          fold (ConvertTyp_block nil b3) in H0. rewrite convert_typ_successors in H0.
          apply cvir_outputs_build_map'; try assumption.
          eapply successors_outputs; try eassumption.
          apply find_block_In' in H. assumption.
        }
        intros.
        repeat break_match; apply eutt_Ret; try easy.
        -- left. unfold I', I. inv H0. unfold I in H4. simpl. split; f_equal; tauto.
        -- right. now inv H0.
      * exfalso.
        clear Heqo Heqo0.
        eapply find_block_app_wf in Heqo2; [| assumption ].
        destruct Heqo2; try now rewrite H in Heqo1.
        apply find_block_Some_In_inputs in H.
        destruct H1. simpl in H0. inv H0.
        apply cvir_inputs_build_map in H; try assumption. lia.
      * eapply find_block_some_app in Heqo1.
        now rewrite Heqo1 in Heqo2.
      * apply eutt_Ret.
        now right.
    + unfold I', I.
      rewrite !nth_build_map.
      destruct bid.
      intuition.
      exists x.
      intuition.
Qed.

Theorem denote_cvir_merge_r' : forall ni1 no1 ni2 no2 (ir1 : cvir ni1 no1) (ir2 : cvir ni2 no2) bid,
  cvir_WF ir1 ->
  cvir_WF ir2 ->
  eutt eq
    (denote_cvir (merge_cvir ir1 ir2) (R ni1 bid) (R ni1 bid))
    (denote_cvir_gen ir2 (build_map ni1 ni2) (build_map (ni1+ni2+no1) no2) (build_map (ni1+ni2+(no1+no2)+n_int ir1) (n_int ir2)) bid bid).
Admitted.

Theorem denote_cvir_merge_l : forall ni1 no1 ni2 no2 (ir1 : cvir ni1 no1) (ir2 : cvir ni2 no2) bid,
  cvir_WF ir1 ->
  cvir_WF ir2 ->
  eutt
    (ocfg_relabel_helper_rel (vec_build_map
      ((build_map 0 ni1) ++ (build_map (ni1+ni2) no1) ++ (build_map (ni1+ni2+(no1+no2)) (n_int ir1)))
      ((build_map 0 ni1) ++ (build_map ni1 no1) ++ (build_map (ni1+no1) (n_int ir1)))
    ))
    (denote_cvir (merge_cvir ir1 ir2) (L _ bid) (L _ bid))
    (denote_cvir ir1 bid bid).
Proof.
  intros.
  rewrite denote_cvir_merge_l'; try assumption.
  eapply eutt_cvir_relabel; try assumption ;
  apply unique_vector_build_map; lia.
Qed.

Theorem denote_cvir_merge_r : forall ni1 no1 ni2 no2 (ir1 : cvir ni1 no1) (ir2 : cvir ni2 no2) bid,
  cvir_WF ir1 ->
  cvir_WF ir2 ->
  eutt
    (ocfg_relabel_helper_rel (vec_build_map
      ((build_map ni1 ni2) ++ (build_map (ni1+ni2+no1) no2) ++ (build_map (ni1+ni2+(no1+no2)+n_int ir1) (n_int ir2)))
      ((build_map 0 ni2) ++ (build_map ni2 no2) ++ (build_map (ni2+no2) (n_int ir2)))
    ))
    (denote_cvir (merge_cvir ir1 ir2) (R _ bid) (R _ bid))
    (denote_cvir ir2 bid bid).
Proof.
  intros.
  rewrite denote_cvir_merge_r'; try assumption.
  eapply eutt_cvir_relabel; try assumption;
  apply unique_vector_build_map; lia.
Qed.

(* Theorem merge_cvir_correct : forall *)
(*   ni1 no1 ni2 no2 (ir1 : cvir ni1 no1) (ir2 : cvir ni2 no2) bid bid', *)
(*   cvir_WF ir1 -> *)
(*   cvir_WF ir2 -> *)
(*   eutt eq *)
(*     (denote_cvir (merge_cvir ir1 ir2) bid bid') *)
(*     (bimap (denote_cvir ir1 bid bid) (denote_cvir ir2 bid' bid')). *)

(* NOTE shouldn't it be in Fin.v ? *)
Definition sym_fin {n1 n2 n3 : nat} (f : fin (n1 + (n2 + n3))) : fin (n1 + (n3 + n2)) :=
  match split_fin_sum _ _ f with
  | inl l => L (n3 + n2) l
  | inr r => R n1 (
    match split_fin_sum _ _ r with
    | inl l => R _ l
    | inr r => L _ r
    end
  )
  end.

Theorem denote_cvir_sym_i : forall {ni1 ni2 ni3 no : nat} (ir : cvir (ni1 + (ni2 + ni3)) no) bid bid',
  cvir_ids_WF ir ->
  unique_bid ir ->
  eutt eq
    (denote_cvir ir bid bid')
    (denote_cvir (sym_i_cvir ir) (sym_fin bid) (sym_fin bid)).
Proof.
  intros.
  unfold denote_cvir, denote_cvir_gen, sym_i_cvir, sym_fin.
  cbn.
  rewrite !skipn_build_map.
  rewrite !firstn_build_map.
  cbn.
  destruct (split_fin_sum _ _ _) eqn:?.
  apply split_fin_sum_inl in Heqs. subst bid.
Admitted.

(* NOTE denote_cvir_block ? *)
(* NOTE denote_cvir_branch ? *)
(* NOTE denote_cvir_sym ? *)
(* NOTE denote_cvir_cast ? *)
(* NOTE denote_cvir_focus ? *)
(* NOTE denote_cvir_loop ? *)
(* NOTE denote_cvir_loop_open ? *)
(* NOTE denote_cvir_seq ? *)
(* NOTE denote_cvir_join ? *)


(* Relation between Imp env and vellvm env *)

Definition Rmem (vmap : StringMap.t int)(env : Imp.env) (venv : local_env) (vmem : memory_stack) : Prop :=
  forall k v, alist_find k env = Some v <-> (
    exists reg, StringMap.find k vmap = Some reg /\
      exists addr, alist_find (Anon reg) venv = Some (UVALUE_Addr addr) /\
        exists v32, read vmem addr (DTYPE_I (Npos 32%positive)) = inr (UVALUE_I32 v32) /\
          Int32.intval v32 = Z.of_nat v
  ).

Definition Rimpvir
  (vmap : StringMap.t int)
  (env1 : Imp.env * unit)
  (env2 : memory_stack * (local_env * (global_env * (block_id * block_id + uvalue)))) :
  Prop :=
  Rmem vmap (fst env1) (fst (snd env2)) (fst env2).

(* NOTE it misses the induction hypothesus on l and r *)
Theorem compile_seq_correct : forall next_reg l r env next_reg' env' ir mem bid genv lenv vmem,
  compile next_reg (Seq l r) env = Some(next_reg', env', ir) ->
  eutt (Rimpvir env)
  (interp_imp (denote_imp (Seq l r)) mem)
  (interp_cfg3 (denote_cvir ir f0 bid) genv lenv vmem).
Abort.

Fail Theorem compile_assign_correct : TODO.
Fail Theorem compile_if_correct : TODO.
Fail Theorem compile_while_correct : TODO.
Fail Theorem compile_skip_correct : TODO.


Import ITreeNotations.
Import SemNotations.


Theorem compile_correct : forall (next_reg : int) env (p : stmt)
                            (next_reg': int) env' (ir : cvir 1 1)
                            mem bid genv lenv vmem,

  (* The environments of Imp and Cvir are related *)
  Rmem env mem lenv vmem ->
  (* The compilation of p with env produce a new env' and an ir *)
  compile next_reg p env = Some(next_reg', env', ir) ->

  eutt (Rimpvir env')
       (interp_imp (denote_imp p) mem)
       (interp_cfg3 (denote_cvir ir f0 bid) genv lenv vmem).

Proof.
  induction p ; intros.
  - (* Assign *)
    simpl.
    simpl in *.
    break_match_hyp ; inv H0.
    destruct p ;  destruct p.
    inv H2.
    unfold compile_assign in *.
    cbn in *.
    break_match_hyp ; inv Heqo.
    destruct p. inv H1.
    break_match_hyp ; inv H2.
    (* unfold compile_expr in Heqo0. *)
    (* cbn in *. *)
    (* destruct e. *)
    (* Focus 2. *)
    (* inv Heqo0. *)
    (* cbn. *)
    (* rewrite interp_imp_bind. *)
    (* unfold interp_imp. *)
    (* unfold MapDefault.interp_map. *)
    (* unfold State.interp_state. *)
    (* rewrite interp_ret. *)

    (* need denote_block_cvir here *)
    admit. admit.

  - (* Seq *)
    simpl. simpl in *.
    break_match_hyp ; inv H0.
    destruct p ;  destruct p.
    break_match_hyp ; inv H2.
    destruct p ;  destruct p.
    inv H1.
    rewrite interp_imp_bind.
    (* need denote_seq_cvir here *)
    admit.

  - (* If *)
    simpl ; simpl in *.
    break_match_hyp ; inv H0. destruct p.
    break_match_hyp ; inv H2. destruct p ; destruct p.
    break_match_hyp ; inv H1. destruct p ; destruct p.
    inv H2.
    (* need denote_seq_cvir, denote_join_cvir, denote_branch_cvir here *)

    admit.
  - (* While *)
    simpl ; simpl in *.
    break_match_hyp ; inv H0. destruct p0.
    break_match_hyp ; inv H2. destruct p0; destruct p0.
    inv H1.
    (* need denote_loop_open_cvir, denote_focus_output_cvir, denote_branch_cvir, denote_seq_cvir here *)

    admit.
  - (* Skip *)
    simpl.
    simpl in *.
    inv H0.

    cbn.
    unfold denote_cvir, denote_cvir_gen.
    cbn. simpl.
    unfold tfmap.

    (* need denote_block_cvir here *)
    admit.
Admitted.
