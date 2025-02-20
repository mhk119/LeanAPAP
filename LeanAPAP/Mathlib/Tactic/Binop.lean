/-
Copyright (c) 2021 Microsoft Corporation. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Leonardo de Moura
-/
import Lean.Elab.App
import Lean.Elab.BuiltinNotation

/-! # Auxiliary elaboration functions: AKA custom elaborators -/

/-
Overrides to Lean/Elab/Extra.lean by Kyle Miller

Includes elaborators for left and right actions (for `HPow.hPow`).
-/

namespace Lean.Elab.Term
open Meta

namespace OpV2
/-!

The elaborator for `binop%`, `binop_lazy%`, and `unop%` terms.

It works as follows:

1- Expand macros.
2- Convert `Syntax` object corresponding to the `binop%` (`binop_lazy%` and `unop%`) term into a
  `Tree`. The `toTree` method visits nested `binop%` (`binop_lazy%` and `unop%`) terms and
  parentheses.
3- Synthesize pending metavariables without applying default instances and using the
   `(mayPostpone := true)`.
4- Tries to compute a maximal type for the tree computed at step 2.
   We say a type α is smaller than type β if there is a (nondependent) coercion from α to β.
   We are currently ignoring the case we may have cycles in the coercion graph.
   If there are "uncomparable" types α and β in the tree, we skip the next step.
   We say two types are "uncomparable" if there isn't a coercion between them.
   Note that two types may be "uncomparable" because some typing information may still be missing.
5- We traverse the tree and inject coercions to the "maximal" type when needed.

Recall that the coercions are expanded eagerly by the elaborator.

Properties:

a) Given `n : Nat` and `i : Nat`, it can successfully elaborate `n + i` and `i + n`. Recall that
  Lean 3 fails on the former.

b) The coercions are inserted in the "leaves" like in Lean 3.

c) There are no coercions "hidden" inside instances, and we can elaborate
```
axiom Int.add_comm (i j : Int) : i + j = j + i

example (n : Nat) (i : Int) : n + i = i + n := by
  rw [Int.add_comm]
```
Recall that the `rw` tactic used to fail because our old `binop%` elaborator would hide
coercions inside of a `HAdd` instance.

Remarks:

In the new `binop%` and related elaborators the decision whether a coercion will be inserted or not
is made at `binop%` elaboration time. This was not the case in the old elaborator.
For example, an instance, such as `HAdd Int ?m ?n`, could be created when executing
the `binop%` elaborator, and only resolved much later. We try to minimize this problem
by synthesizing pending metavariables at step 3.

For types containing heterogeneous operators (e.g., matrix multiplication), step 4 will fail
and we will skip coercion insertion. For example, `x : Matrix Real 5 4` and `y : Matrix Real 4 8`,
there is no coercion `Matrix Real 5 4` from `Matrix Real 4 8` and vice-versa, but
`x * y` is elaborated successfully and has type `Matrix Real 5 8`.
-/

section
open Parser

/-- Left action; the right argument can participate in the operator coercion elaborator. -/
syntax (name := leftact) "leftact% " ident ppSpace term:max ppSpace term:max : term

/-- Right action; the left argument can participate in the operator coercion elaborator. -/
syntax (name := rightact) "rightact% " ident ppSpace term:max ppSpace term:max : term

end

private inductive Tree where
  /--
  Leaf of the tree.
  We store the `infoTrees` generated when elaborating `val`. These trees become
  subtrees of the infotree nodes generated for `op` nodes.
  -/
  | term (ref : Syntax) (infoTrees : PersistentArray InfoTree) (val : Expr)
  /--
  `ref` is the original syntax that expanded into `binop%`.
  -/
  | binop (ref : Syntax) (lazy : Bool) (f : Expr) (lhs rhs : Tree)
  /--
  `ref` is the original syntax that expanded into `unop%`.
  -/
  | unop (ref : Syntax) (f : Expr) (arg : Tree)
  /--
  `ref` is the original syntax that expanded into `action%`.
  `right` is whether this is a right action (vs a left action); if it is a right (resp. left)
  action, then the `rhs` (resp. `lhs`) is not processed.
  -/
  | action (ref : Syntax) (right : Bool) (f : Expr) (lhs rhs : Tree)
  /--
  Used for assembling the info tree. We store this information
  to make sure "go to definition" behaves similarly to notation defined without using `binop%`
  helper elaborator.
  -/
  | macroExpansion (macroName : Name) (stx stx' : Syntax) (nested : Tree)


private partial def toTree (s : Syntax) : TermElabM Tree := do
  /-
  Remark: ew used to use `expandMacros` here, but this is a bad idiom
  because we do not record the macro expansion information in the info tree.
  We now manually expand the notation in the `go` function, and save
  the macro declaration names in the `op` nodes.
  -/
  let result ← go s
  synthesizeSyntheticMVars (mayPostpone := true)
  return result
where
  go (s : Syntax) := do
    match s with
    | `(binop% $f $lhs $rhs) => processBinOp (lazy := false) s f lhs rhs
    | `(binop_lazy% $f $lhs $rhs) => processBinOp (lazy := true) s f lhs rhs
    | `(unop% $f $arg) => processUnOp s f arg
    | `(leftact% $f $lhs $rhs) => processAction (right := false) s f lhs rhs
    | `(rightact% $f $lhs $rhs) => processAction (right := true) s f lhs rhs
    | `(($e)) =>
      if hasCDot e then
        processLeaf s
      else
        go e
    | _ =>
      withRef s do
        match (← liftMacroM <| expandMacroImpl? (← getEnv) s) with
        | some (macroName, s?) =>
          let s' ← liftMacroM <| liftExcept s?
          withPushMacroExpansionStack s s' do
            return .macroExpansion macroName s s' (← go s')
        | none => processLeaf s

  processBinOp (ref : Syntax) (f lhs rhs : Syntax) (lazy : Bool) := do
    let some f ← resolveId? f | throwUnknownConstant f.getId
    return .binop (lazy := lazy) ref f (← go lhs) (← go rhs)

  processUnOp (ref : Syntax) (f arg : Syntax) := do
    let some f ← resolveId? f | throwUnknownConstant f.getId
    return .unop ref f (← go arg)

  processAction (ref : Syntax) (f lhs rhs : Syntax) (right : Bool) := do
    let some f ← resolveId? f | throwUnknownConstant f.getId
    if right then
      return .action ref right f (← go lhs) (← processLeaf rhs)
    else
      return .action ref right f (← processLeaf lhs) (← go rhs)

  processLeaf (s : Syntax) := do
    let e ← elabTerm s none
    let info ← getResetInfoTrees
    return .term s info e

-- Auxiliary function used at `analyze`
private def hasCoe (fromType toType : Expr) : TermElabM Bool := do
  if (← getEnv).contains ``CoeT then
    withLocalDeclD `x fromType fun x => do
    match ← coerceSimple? x toType with
    | .some _ => return true
    | .none   => return false
    | .undef  => return false -- TODO: should we do something smarter here?
  else
    return false

private structure AnalyzeResult where
  max?            : Option Expr := none
  -- `true` if there are two types `α` and `β` where we don't have coercions in any direction.
  hasUncomparable : Bool := false

private def isUnknow : Expr → Bool
  | .mvar ..        => true
  | .app f _        => isUnknow f
  | .letE _ _ _ b _ => isUnknow b
  | .mdata _ b      => isUnknow b
  | _               => false

private def analyze (t : Tree) (expectedType? : Option Expr) : TermElabM AnalyzeResult := do
  let max? ←
    match expectedType? with
    | none => pure none
    | some expectedType =>
      let expectedType ← instantiateMVars expectedType
      if isUnknow expectedType then pure none else pure (some expectedType)
  (go t *> get).run' { max? }
where
   go (t : Tree) : StateRefT AnalyzeResult TermElabM Unit := do
     unless (← get).hasUncomparable do
       match t with
       | .macroExpansion _ _ _ nested => go nested
       | .binop _ _ _ lhs rhs => go lhs; go rhs
       | .unop _ _ arg => go arg
       | .action _ right _ lhs rhs => if right then go lhs else go rhs
       | .term _ _ val =>
         let type ← instantiateMVars (← inferType val)
         unless isUnknow type do
           match (← get).max? with
           | none     => modify fun s => { s with max? := type }
           | some max =>
             unless (← withNewMCtxDepth <| isDefEqGuarded max type) do
               if (← hasCoe type max) then
                 return ()
               else if (← hasCoe max type) then
                 modify fun s => { s with max? := type }
               else
                 trace[Elab.binop] "uncomparable types: {max}, {type}"
                 modify fun s => { s with hasUncomparable := true }

private def mkBinOp (lazy : Bool) (f : Expr) (lhs rhs : Expr) : TermElabM Expr := do
  let mut rhs := rhs
  if lazy then
    rhs ← mkFunUnit rhs
  elabAppArgs f #[] #[Arg.expr lhs, Arg.expr rhs] (expectedType? := none) (explicit := false)
    (ellipsis := false) (resultIsOutParamSupport := false)

private def mkUnOp (f : Expr) (arg : Expr) : TermElabM Expr := do
  elabAppArgs f #[] #[Arg.expr arg] (expectedType? := none) (explicit := false) (ellipsis := false)
    (resultIsOutParamSupport := false)

private def toExprCore (t : Tree) : TermElabM Expr := do
  match t with
  | .term _ trees e =>
    modifyInfoState (fun s => { s with trees := s.trees ++ trees }); return e
  | .binop ref lazy f lhs rhs =>
    withRef ref <| withInfoContext' ref (mkInfo := mkTermInfo .anonymous ref) do
      mkBinOp lazy f (← toExprCore lhs) (← toExprCore rhs)
  | .unop ref f arg =>
    withRef ref <| withInfoContext' ref (mkInfo := mkTermInfo .anonymous ref) do
      mkUnOp f (← toExprCore arg)
  | .action ref _ f lhs rhs =>
    withRef ref <| withInfoContext' ref (mkInfo := mkTermInfo .anonymous ref) do
      mkBinOp false f (← toExprCore lhs) (← toExprCore rhs)
  | .macroExpansion macroName stx stx' nested =>
    withRef stx <| withInfoContext' stx (mkInfo := mkTermInfo macroName stx) do
      withMacroExpansion stx stx' do
        toExprCore nested

/--
  Auxiliary function to decide whether we should coerce `f`'s argument to `maxType` or not.
  - `f` is a binary operator.
  - `lhs == true` (`lhs == false`) if are trying to coerce the left-argument (right-argument).
  This function assumes `f` is a heterogeneous operator (e.g., `HAdd.hAdd`, `HMul.hMul`, etc).
  It returns true IF
  - `f` is a constant of the form `Cls.op` where `Cls` is a class name, and
  - `maxType` is of the form `C ...` where `C` is a constant, and
  - There are more than one default instance. That is, it assumes the class `Cls` for the
    heterogeneous operator `f`, and always has the monomorphic instance. (e.g., for `HAdd`, we have
    `instance [Add α] : HAdd α α α`), and
  - If `lhs == true`, then there is a default instance of the form `Cls _ (C ..) _`, and
  - If `lhs == false`, then there is a default instance of the form `Cls (C ..) _ _`.

  The motivation is to support default instances such as
  ```
  @[default_instance high]
  instance [Mul α] : HMul α (Array α) (Array α) where
    hMul a as := as.map (a * ·)

  #eval 2 * #[3, 4, 5]
  ```
  If the type of an argument is unknown we should not coerce it to `maxType` because it would
  prevent the default instance above from being even tried.
-/
private def hasHeterogeneousDefaultInstances (f : Expr) (maxType : Expr) (lhs : Bool) :
    MetaM Bool := do
  let .const fName .. := f | return false
  let .const typeName .. := maxType.getAppFn | return false
  let className := fName.getPrefix
  let defInstances ← getDefaultInstances className
  if defInstances.length ≤ 1 then return false
  for (instName, _) in defInstances do
    if let .app (.app (.app _heteroClass lhsType) rhsType) _resultType :=
        (← getConstInfo instName).type.getForallBody then
      if  lhs && rhsType.isAppOf typeName then return true
      if !lhs && lhsType.isAppOf typeName then return true
  return false

/--
  Return `true` if polymorphic function `f` has a homogenous instance of `maxType`.
  The coercions to `maxType` only makes sense if such instance exists.

  For example, suppose `maxType` is `Int`, and `f` is `HPow.hPow`. Then,
  adding coercions to `maxType` only make sense if we have an instance `HPow Int Int Int`.
-/
private def hasHomogeneousInstance (f : Expr) (maxType : Expr) : MetaM Bool := do
  let .const fName .. := f | return false
  let className := fName.getPrefix
  try
    let inst ← mkAppM className #[maxType, maxType, maxType]
    return (← trySynthInstance inst) matches .some _
  catch _ =>
    return false

mutual
  /--
    Try to coerce elements in the `t` to `maxType` when needed.
    If the type of an element in `t` is unknown we only coerce it to `maxType` if `maxType` does not
    have heterogeneous default instances. This extra check is approximated by
    `hasHeterogeneousDefaultInstances`.

    Remark: If `maxType` does not implement heterogeneous default instances, we do want to assign
    unknown types `?m` to `maxType` because it produces better type information propagation. Our
    test suite has many tests that would break if we don't do this. For example, consider the term
    ```
    eq_of_isEqvAux a b hsz (i+1) (Nat.succ_le_of_lt h) heqv.2
    ```
    `Nat.succ_le_of_lt h` type depends on `i+1`, but `i+1` only reduces to `Nat.succ i` if we know
    that `1` is a `Nat`. There are several other examples like that in our test suite, and one can
    find them by just replacing the `← hasHeterogeneousDefaultInstances f maxType lhs` test with
    `true`


    Remark: if `hasHeterogeneousDefaultInstances` implementation is not good enough we should refine
    it in the future.
  -/
  private partial def applyCoe (t : Tree) (maxType : Expr) (isPred : Bool) : TermElabM Tree := do
    go t none false isPred
  where
    go (t : Tree) (f? : Option Expr) (lhs : Bool) (isPred : Bool) : TermElabM Tree := do
      match t with
      | .binop ref lazy f lhs rhs =>
        /-
          We only keep applying coercions to `maxType` if `f` is predicate or `f` has a homogenous
          instance with `maxType`. See `hasHomogeneousInstance` for additional details.

          Remark: We assume `binrel%` elaborator is only used with homogenous predicates.
        -/
        if (← pure isPred <||> hasHomogeneousInstance f maxType) then
          return .binop ref lazy f (← go lhs f true false) (← go rhs f false false)
        else
          let r ← withRef ref do
            mkBinOp lazy f (← toExpr lhs none) (← toExpr rhs none)
          let infoTrees ← getResetInfoTrees
          return .term ref infoTrees r
      | .unop ref f arg =>
        return .unop ref f (← go arg none false false)
      | .action ref right f lhs rhs =>
        if right then
          return .action ref right f (← go lhs none false false) rhs
        else
          return .action ref right f lhs (← go rhs none false false)
      | .term ref trees e =>
        let type ← instantiateMVars (← inferType e)
        trace[Elab.binop] "visiting {e} : {type} =?= {maxType}"
        if isUnknow type then
          if let some f := f? then
            if (← hasHeterogeneousDefaultInstances f maxType lhs) then
              -- See comment at `hasHeterogeneousDefaultInstances`
              return t
        if (← isDefEqGuarded maxType type) then
          return t
        else
          trace[Elab.binop] "added coercion: {e} : {type} => {maxType}"
          withRef ref <| return .term ref trees (← mkCoe maxType e)
      | .macroExpansion macroName stx stx' nested =>
        withRef stx <| withPushMacroExpansionStack stx stx' do
          return .macroExpansion macroName stx stx' (← go nested f? lhs isPred)

  private partial def toExpr (tree : Tree) (expectedType? : Option Expr) : TermElabM Expr := do
    let r ← analyze tree expectedType?
    trace[Elab.binop] "hasUncomparable: {r.hasUncomparable}, maxType: {r.max?}"
    if r.hasUncomparable || r.max?.isNone then
      let result ← toExprCore tree
      ensureHasType expectedType? result
    else
      let result ← toExprCore (← applyCoe tree r.max?.get! (isPred := false))
      trace[Elab.binop] "result: {result}"
      ensureHasType expectedType? result

end

def elabOp : TermElab := fun stx expectedType? => do
  toExpr (← toTree stx) expectedType?

@[term_elab binop]
def elabBinOp : TermElab := elabOp

@[term_elab binop_lazy]
def elabBinOpLazy : TermElab := elabOp

@[term_elab unop]
def elabUnOp : TermElab := elabOp

@[term_elab leftact]
def elabLeftAct : TermElab := elabOp

@[term_elab rightact]
def elabRightAct : TermElab := elabOp

/--
  Elaboration functionf for `binrel%` and `binrel_no_prop%` notations.
  We use the infrastructure for `binop%` to make sure we propagate information between the left and
  right hand sides of a binary relation.

  Recall that the `binrel_no_prop%` notation is used for relations such as `==` which do not support
  `Prop`, but we still want to be able to write `(5 > 2) == (2 > 1)`.
-/
def elabBinRelCore (noProp : Bool) (stx : Syntax) (expectedType? : Option Expr) :
    TermElabM Expr :=  do
  match (← resolveId? stx[1]) with
  | some f => withSynthesizeLight do
    /-
    We used to use `withSynthesize (mayPostpone := true)` here instead of `withSynthesizeLight`
    here. Recall that `withSynthesizeLight` is equivalent to
    `withSynthesize (mayPostpone := true) (synthesizeDefault := false)`. It seems too much to apply
    default instances at binary relations. For example, we cannot elaborate
    ```
    def as : List Int := [-1, 2, 0, -3, 4]
    #eval as.map fun a => ite (a ≥ 0) [a] []
    ```
    The problem is that when elaborating `a ≥ 0` we don't know yet that `a` is an `Int`.
    Then, by applying default instances, we apply the default instance to `0` that forces it to
    become an `Int`,
    and Lean infers that `a` has type `Nat`.
    Then, later we get a type error because `as` is `List Int` instead of `List Nat`.
    This behavior is quite counterintuitive since if we avoid this elaborator by writing
    ```
    def as : List Int := [-1, 2, 0, -3, 4]
    #eval as.map fun a => ite (GE.ge a 0) [a] []
    ```
    everything works.
    However, there is a drawback of using `withSynthesizeLight` instead of
    `withSynthesize (mayPostpone := true)`.
    The following cannot be elaborated
    ```
    have : (0 == 1) = false := rfl
    ```
    We get a type error at `rfl`. `0 == 1` only reduces to `false` after we have applied the default
    instances that force the numeral to be `Nat`. We claim this is defensible behavior because the
    same happens if we do not use this elaborator.
    ```
    have : (BEq.beq 0 1) = false := rfl
    ```
    We can improve this failure in the future by applying default instances before reporting a type
    mismatch.
    -/
    let lhs ← withRef stx[2] <| toTree stx[2]
    let rhs ← withRef stx[3] <| toTree stx[3]
    let tree := .binop (lazy := false) stx f lhs rhs
    let r ← analyze tree none
    trace[Elab.binrel] "hasUncomparable: {r.hasUncomparable}, maxType: {r.max?}"
    if r.hasUncomparable || r.max?.isNone then
      -- Use default elaboration strategy + `toBoolIfNecessary`
      let lhs ← toExprCore lhs
      let rhs ← toExprCore rhs
      let lhs ← toBoolIfNecessary lhs
      let rhs ← toBoolIfNecessary rhs
      let lhsType ← inferType lhs
      let rhs ← ensureHasType lhsType rhs
      elabAppArgs f #[] #[Arg.expr lhs, Arg.expr rhs] expectedType? (explicit := false)
        (ellipsis := false) (resultIsOutParamSupport := false)
    else
      let mut maxType := r.max?.get!
      /- If `noProp == true` and `maxType` is `Prop`, then set `maxType := Bool`. See
      `toBoolIfNecessary` -/
      if noProp then
        if (← withNewMCtxDepth <| isDefEq maxType (mkSort levelZero)) then
          maxType := Lean.mkConst ``Bool
      let result ← toExprCore (← applyCoe tree maxType (isPred := true))
      trace[Elab.binrel] "result: {result}"
      return result
  | none   => throwUnknownConstant stx[1].getId
where
  /-- If `noProp == true` and `e` has type `Prop`, then coerce it to `Bool`. -/
  toBoolIfNecessary (e : Expr) : TermElabM Expr := do
    if noProp then
      -- We use `withNewMCtxDepth` to make sure metavariables are not assigned
      if (← withNewMCtxDepth <| isDefEq (← inferType e) (mkSort levelZero)) then
        return (← ensureHasType (Lean.mkConst ``Bool) e)
    return e

@[term_elab binrel] def elabBinRel : TermElab := elabBinRelCore false

@[term_elab binrel_no_prop] def elabBinRelNoProp : TermElab := elabBinRelCore true

end OpV2

macro_rules | `($x ^ $y)   => `(rightact% HPow.hPow $x $y)

end Lean.Elab.Term
