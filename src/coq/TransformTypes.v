(* -------------------------------------------------------------------------- *
 *                     Vellvm - the Verified LLVM project                     *
 *                                                                            *
 *     Copyright (c) 2017 Steve Zdancewic <stevez@cis.upenn.edu>              *
 *                                                                            *
 *   This file is distributed under the terms of the GNU General Public       *
 *   License as published by the Free Software Foundation, either version     *
 *   3 of the License, or (at your option) any later version.                 *
 ---------------------------------------------------------------------------- *)

From Coq Require Import
     ZArith Ascii Strings.String Setoid.

From ExtLib Require Import
     Programming.Eqv
     Structures.Monads
     Structures.Functor
     Data.Option.

From Vellvm Require Import
     Error
     Util
     LLVMAst
     AstLib
     CFG.

Import EqvNotation.

Open Scope Z_scope.
Open Scope string_scope.

Section WithTU.
  Variable (T U:Set).
  Variable (f : T -> U).

Definition fmap_pair {X} : (T * X) -> (U * X) := fun '(t, x)=> (f t, x).

Fixpoint fmap_exp (e:exp T) : exp U :=
  let fmap_texp '(t, e) := (f t, fmap_exp e) in
  match e with
  | EXP_Ident id => EXP_Ident id
  | EXP_Integer x => EXP_Integer x
  | EXP_Float x => EXP_Float x
  | EXP_Double x => EXP_Double x
  | EXP_Hex x => EXP_Hex x
  | EXP_Bool x => EXP_Bool x
  | EXP_Null => EXP_Null
  | EXP_Zero_initializer  => EXP_Zero_initializer
  | EXP_Cstring x => EXP_Cstring x
  | EXP_Undef => EXP_Undef
  | EXP_Struct fields =>
    EXP_Struct (List.map fmap_texp fields)
  | EXP_Packed_struct fields =>
    EXP_Packed_struct (List.map fmap_texp fields)
  | EXP_Array elts =>
    EXP_Array (List.map fmap_texp elts)
  | EXP_Vector elts =>
    EXP_Vector (List.map fmap_texp elts)
  | OP_IBinop iop t v1 v2 =>
    OP_IBinop iop (f t) (fmap_exp v1) (fmap_exp v2)
  | OP_ICmp cmp t v1 v2 =>
    OP_ICmp cmp (f t) (fmap_exp v1) (fmap_exp v2)
  | OP_FBinop fop fm t v1 v2 =>
    OP_FBinop fop fm (f t) (fmap_exp v1) (fmap_exp v2)
  | OP_FCmp cmp t v1 v2 =>
    OP_FCmp cmp (f t) (fmap_exp v1) (fmap_exp v2)
  | OP_Conversion conv t_from v t_to =>
    OP_Conversion conv (f t_from) (fmap_exp v) (f t_to)
  | OP_GetElementPtr t ptrval idxs =>
    OP_GetElementPtr (f t) (fmap_texp ptrval) (List.map fmap_texp idxs)
  | OP_ExtractElement vec idx =>
    OP_ExtractElement (fmap_texp vec) (fmap_texp idx)
  | OP_InsertElement  vec elt idx =>
    OP_InsertElement (fmap_texp vec) (fmap_texp elt) (fmap_texp idx)
  | OP_ShuffleVector vec1 vec2 idxmask =>
    OP_ShuffleVector (fmap_texp vec1) (fmap_texp vec2) (fmap_texp idxmask)
  | OP_ExtractValue  vec idxs =>
    OP_ExtractValue  (fmap_texp vec) idxs
  | OP_InsertValue vec elt idxs =>
    OP_InsertValue (fmap_texp vec) (fmap_texp elt) idxs
  | OP_Select cnd v1 v2 =>
    OP_Select (fmap_texp cnd) (fmap_texp v1) (fmap_texp v2)
  | OP_Freeze v => OP_Freeze (fmap_texp v)
  end.

Definition fmap_texp '(t, e) := (f t, fmap_exp e).

Definition fmap_phi (p:phi T) : phi U :=
  match p with
  | Phi t args => Phi (f t) (List.map (fun '(b,e) => (b, fmap_exp e)) args)
  end.

Definition fmap_instr (ins:instr T) : instr U :=
  match ins with
  | INSTR_Op op => INSTR_Op (fmap_exp op)
  | INSTR_Call fn args => INSTR_Call (fmap_texp fn) (List.map fmap_texp args)
  | INSTR_Alloca t nb align =>
    INSTR_Alloca (f t) (fmap fmap_texp nb) align
  | INSTR_Load volatile t ptr align =>
    INSTR_Load volatile (f t) (fmap_texp ptr) align
  | INSTR_Store volatile val ptr align =>
    INSTR_Store volatile (fmap_texp val) (fmap_texp ptr) align
  | INSTR_Comment c => INSTR_Comment c
  | INSTR_Fence => INSTR_Fence
  | INSTR_AtomicCmpXchg => INSTR_AtomicCmpXchg
  | INSTR_AtomicRMW => INSTR_AtomicRMW
  | INSTR_Unreachable => INSTR_Unreachable
  | INSTR_VAArg => INSTR_VAArg
  | INSTR_LandingPad => INSTR_LandingPad
  end.

Definition fmap_terminator (trm:terminator T) : terminator U :=
  match trm with
  | TERM_Ret  v => TERM_Ret (fmap_texp v)
  | TERM_Ret_void => TERM_Ret_void
  | TERM_Br v br1 br2 => TERM_Br (fmap_texp v) br1 br2
  | TERM_Br_1 br => TERM_Br_1 br
  | TERM_Switch  v default_dest brs =>
    TERM_Switch (fmap_texp v) default_dest (List.map (fun '(e,b) => (fmap_texp e, b)) brs)
  | TERM_IndirectBr v brs =>
    TERM_IndirectBr (fmap_texp v) brs
  | TERM_Resume v => TERM_Resume (fmap_texp v)
  | TERM_Invoke fnptrval args to_label unwind_label =>
    TERM_Invoke (fmap_pair fnptrval) (List.map fmap_texp args) to_label unwind_label
  end.

Definition fmap_global (g:global T) : (global U) :=
  mk_global
      (g_ident g)
      (f (g_typ g))
      (g_constant g)
      (fmap fmap_exp (g_exp g))
      (g_linkage g)
      (g_visibility g)
      (g_dll_storage g)
      (g_thread_local g)
      (g_unnamed_addr g)
      (g_addrspace g)
      (g_externally_initialized g)
      (g_section g)
      (g_align g).

Definition fmap_declaration (d:declaration T) : declaration U :=
  mk_declaration
     (dc_name d)
     (f (dc_type d))
     (dc_param_attrs d)
     (dc_linkage d)
     (dc_visibility d)
     (dc_dll_storage d)
     (dc_cconv d)
     (dc_attrs d)
     (dc_section d)
     (dc_align d)
     (dc_gc d).

Definition fmap_code (c:code T) : code U :=
  List.map (fun '(id, i) => (id, fmap_instr i)) c.

Definition fmap_phis (phis:list (local_id * phi T)) : list (local_id * phi U) :=
  List.map (fun '(id, p) => (id, fmap_phi p)) phis.

Definition fmap_block (b:block T) : block U :=
  mk_block (blk_id b)
           (fmap_phis (blk_phis b))
           (fmap_code (blk_code b))
           (fst (blk_term b), fmap_terminator (snd (blk_term b)))
           (blk_comments b).


Definition fmap_definition {X Y:Set} (g : X -> Y) (d:definition T X) : definition U Y :=
  mk_definition _
    (fmap_declaration (df_prototype d))
    (df_args d)
    (g (df_instrs d)).

Fixpoint fmap_metadata (m:metadata T) : metadata U :=
  match m with
  | METADATA_Const  tv => METADATA_Const (fmap_texp tv)
  | METADATA_Null => METADATA_Null
  | METADATA_Id id => METADATA_Id id
  | METADATA_String str => METADATA_String str
  | METADATA_Named strs => METADATA_Named strs
  | METADATA_Node mds => METADATA_Node (List.map fmap_metadata mds)
  end.


Definition fmap_toplevel_entity {X Y:Set} (g : X -> Y) (tle:toplevel_entity T X) : toplevel_entity U Y :=
  match tle with
  | TLE_Comment msg => TLE_Comment msg
  | TLE_Target tgt => TLE_Target tgt
  | TLE_Datalayout layout => TLE_Datalayout layout
  | TLE_Declaration decl => TLE_Declaration (fmap_declaration decl)
  | TLE_Definition defn => TLE_Definition (fmap_definition g defn)
  | TLE_Type_decl id t => TLE_Type_decl id (f t)
  | TLE_Source_filename s => TLE_Source_filename s
  | TLE_Global g => TLE_Global (fmap_global g)
  | TLE_Metadata id md => TLE_Metadata id (fmap_metadata md)
  | TLE_Attribute_group id attrs => TLE_Attribute_group id attrs
  end.

Definition fmap_modul {X Y:Set} (g : X -> Y) (m:modul T X) : modul U Y :=
  mk_modul _
    (m_name m)
    (m_target m)
    (m_datalayout m)
    (List.map (fun '(i,t) => (i, f t)) (m_type_defs m))
    (List.map fmap_global (m_globals m))
    (List.map fmap_declaration (m_declarations m))
    (List.map (fmap_definition g) (m_definitions m)).

Definition fmap_cfg (CFG:cfg T) : cfg U :=
  mkCFG _
        (init _ CFG)
        (List.map fmap_block (blks _ CFG))
        (args _ CFG).

Definition fmap_mcfg := fmap_modul fmap_cfg.

End WithTU.
