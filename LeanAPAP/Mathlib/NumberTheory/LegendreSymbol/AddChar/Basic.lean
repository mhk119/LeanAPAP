import Mathlib.NumberTheory.LegendreSymbol.AddCharacter
import LeanAPAP.Mathlib.Algebra.DirectSum.Basic
import LeanAPAP.Mathlib.Analysis.Normed.Field.Basic
import LeanAPAP.Mathlib.Data.IsROrC.Basic
import LeanAPAP.Mathlib.LinearAlgebra.FiniteDimensional
import LeanAPAP.Prereqs.Convolution.Basic
import LeanAPAP.Prereqs.LpNorm

/-!
### TODO

Rename
* `map_add_mul` → `map_add_eq_mul`
* `map_zero_one` → `map_zero_eq_one`
* `map_nsmul_pow` → `map_nsmul_eq_pow`
* `coe_toFun_apply` → whatever is better, maybe change to `ψ.toMonoidNom a = ψ (of_mul a)`.

Kill the evil instance `AddChar.MonoidHomClass`. It creates a diamond for
`FunLike (AddChar G R) _ _`.
-/

--TODO: This instance is evil
attribute [-instance] AddChar.monoidHomClass

open Finset hiding card
open Fintype (card)
open Function
open scoped BigOperators ComplexConjugate DirectSum

variable {G H R : Type*}

namespace AddChar
section AddMonoid
variable [AddMonoid G] [AddMonoid H] [CommMonoid R] {ψ : AddChar G R}

instance : AddCommMonoid (AddChar G R) := Additive.addCommMonoid

instance instFunLike : FunLike (AddChar G R) G fun _ ↦ R where
  coe := (⇑)
  coe_injective' ψ χ h := by obtain ⟨⟨_, _⟩, _⟩ := ψ; congr

-- TODO: Replace `AddChar.toMonoidHom`
/-- Interpret an additive character as a monoid homomorphism. -/
def toMonoidHom' : AddChar G R ≃ (Multiplicative G →* R) := Equiv.refl _

@[simp, norm_cast]
lemma coe_toMonoid_hom (ψ : AddChar G R) : ⇑(toMonoidHom' ψ) = ψ ∘ Multiplicative.toAdd := rfl

@[simp, norm_cast] lemma coe_toMonoid_hom_symm (ψ : Multiplicative G →* R) :
    ⇑(toMonoidHom'.symm ψ) = ψ ∘ Multiplicative.ofAdd := rfl

@[simp] lemma toMonoid_hom_apply (ψ : AddChar G R) (a : Multiplicative G) :
    toMonoidHom' ψ a = ψ (Multiplicative.toAdd a) := rfl

@[simp] lemma toMonoid_hom_symm_apply (ψ : Multiplicative G →* R) (a : G) :
    toMonoidHom'.symm ψ a = ψ (Multiplicative.ofAdd a) := rfl

/-- Interpret an additive character as a monoid homomorphism. -/
def toAddMonoidHom : AddChar G R ≃ (G →+ Additive R) := MonoidHom.toAdditive

@[simp, norm_cast]
lemma coe_toAddMonoidHom (ψ : AddChar G R) : ⇑(toAddMonoidHom ψ) = Additive.ofMul ∘ ψ := rfl

@[simp, norm_cast] lemma coe_toAddMonoidHom_symm (ψ : G →+ Additive R) :
    ⇑(toAddMonoidHom.symm ψ) = Additive.toMul ∘ ψ := rfl

@[simp] lemma toAddMonoidHom_apply (ψ : AddChar G R) (a : G) :
    toAddMonoidHom ψ a = Additive.ofMul (ψ a) := rfl

@[simp] lemma toAddMonoidHom_symm_apply (ψ : G →+ Additive R) (a : G) :
    toAddMonoidHom.symm ψ a = Additive.toMul (ψ a) := rfl

lemma eq_one_iff : ψ = 0 ↔ ∀ x, ψ x = 1 := FunLike.ext_iff

lemma ne_one_iff : ψ ≠ 0 ↔ ∃ x, ψ x ≠ 1 := FunLike.ne_iff

@[simp, norm_cast] lemma coe_one : ⇑(1 : AddChar G R) = 1 := rfl
@[simp, norm_cast] lemma coe_mul (ψ χ : AddChar G R) : ⇑(ψ * χ) = ψ * χ := rfl

@[simp, norm_cast]
lemma coe_pow (n : ℕ) (ψ : AddChar G R) : ⇑(ψ ^ n) = ψ ^ n := rfl

lemma pow_apply (n : ℕ) (ψ : AddChar G R) (a : G) : (ψ ^ n) a = ψ a ^ n := rfl

lemma eq_zero_iff : ψ = 0 ↔ ∀ x, ψ x = 1 := FunLike.ext_iff
lemma ne_zero_iff : ψ ≠ 0 ↔ ∃ x, ψ x ≠ 1 := FunLike.ne_iff

@[simp, norm_cast] lemma coe_zero : ⇑(0 : AddChar G R) = 1 := rfl

lemma zero_apply (a : G) : (0 : AddChar G R) a = 1 := rfl

@[simp, norm_cast] lemma coe_eq_zero : ⇑ψ = 1 ↔ ψ = 0 := by rw [←coe_zero]; exact FunLike.coe_fn_eq
@[simp, norm_cast] lemma coe_add (ψ χ : AddChar G R) : ⇑(ψ + χ) = ψ * χ := rfl

lemma add_apply (ψ χ : AddChar G R) (a : G) : (ψ + χ) a = ψ a * χ a := rfl

@[simp, norm_cast] lemma coe_nsmul (n : ℕ) (ψ : AddChar G R) : ⇑(n • ψ) = ψ ^ n := rfl

lemma nsmul_apply (n : ℕ) (ψ : AddChar G R) (a : G) : (ψ ^ n) a = ψ a ^ n := rfl

variable {ι : Type*}

@[simp, norm_cast]
lemma coe_sum (s : Finset ι) (ψ : ι → AddChar G R) : ⇑(∑ i in s, ψ i) = ∏ i in s, ⇑ψ i := by
  induction s using Finset.cons_induction <;> simp [*]

lemma sum_apply (s : Finset ι) (ψ : ι → AddChar G R) (a : G) :
    (∑ i in s, ψ i) a = ∏ i in s, ψ i a := by rw [coe_sum, Finset.prod_apply]

noncomputable instance : DecidableEq (AddChar G R) := Classical.decEq _

/-- Precompose a `R`-valued character of `H` with a homomorphism `G → H` to get a `R`-valued
character of `G`. -/
def compAddMonoidHom (ψ : AddChar H R) (f : G →+ H) : AddChar G R :=
  toMonoidHom'.symm $ ψ.toMonoidHom'.comp $ AddMonoidHom.toMultiplicative f

@[simp] lemma compAddMonoidHom_apply (ψ : AddChar H R) (f : G →+ H) (a : G) :
    ψ.compAddMonoidHom f a = ψ (f a) := rfl

@[simp, norm_cast]
lemma coe_compAddMonoidHom (ψ : AddChar H R) (f : G →+ H) : ⇑(ψ.compAddMonoidHom f) = ψ ∘ f := rfl

lemma compAddMonoidHom_injective_left (f : G →+ H) (hf : Surjective f) :
    Injective fun ψ : AddChar H R ↦ ψ.compAddMonoidHom f := by
  rintro ψ χ h
  rw [FunLike.ext'_iff] at h ⊢
  exact hf.injective_comp_right h

lemma compAddMonoidHom_injective_right (ψ : AddChar H R) (hψ : Injective ψ) :
    Injective fun f : G →+ H ↦ ψ.compAddMonoidHom f := by
  rintro f g h
  rw [FunLike.ext'_iff] at h ⊢
  exact hψ.comp_left h

/-- The double dual embedding. -/
def doubleDualEmb : G →+ AddChar (AddChar G R) R := MonoidHom.toAdditive'' MonoidHom.eval

@[simp] lemma doubleDualEmb_apply (a : G) (ψ : AddChar G R) : doubleDualEmb a ψ = ψ a := rfl

end AddMonoid

section AddGroup
variable [AddGroup G]

section DivisionCommMonoid
variable [DivisionCommMonoid R]

lemma map_sub_eq_div (ψ : AddChar G R) (x y : G) : ψ (x - y) = ψ x / ψ y := by
  rw [coe_to_fun_apply, coe_to_fun_apply _ x, coe_to_fun_apply _ y, ofAdd_sub, map_div]

lemma injective_iff {ψ : AddChar G R} : Injective ψ ↔ ∀ ⦃x⦄, ψ x = 1 → x = 0 :=
  ψ.ker_eq_bot_iff.symm.trans eq_bot_iff

end DivisionCommMonoid

section NormedField
variable [Finite G] [NormedField R]

@[simp] lemma norm_apply (ψ : AddChar G R) (x : G) : ‖ψ x‖ = 1 :=
  (ψ.isOfFinOrder $ exists_pow_eq_one _).norm_eq_one

@[simp] lemma coe_ne_zero (ψ : AddChar G R) : (ψ : G → R) ≠ 0 :=
  Function.ne_iff.2 ⟨0, fun h ↦ by simpa only [h, Pi.zero_apply, zero_ne_one] using map_zero_one ψ⟩

end NormedField

section IsROrC
variable [IsROrC R]

lemma inv_apply_eq_conj [Finite G] (ψ : AddChar G R) (x : G) : (ψ x)⁻¹ = conj (ψ x) :=
  IsROrC.inv_eq_conj $ norm_apply _ _

protected lemma l2inner_self [Fintype G] (ψ : AddChar G R) :
    ⟪(ψ : G → R), ψ⟫_[R] = Fintype.card G := l2inner_self_of_norm_eq_one ψ.norm_apply

end IsROrC

variable [Fintype G] [CommSemiring R] [IsDomain R] [CharZero R] {ψ : AddChar G R}

lemma sum_eq_ite (ψ : AddChar G R) : ∑ a, ψ a = if ψ = 0 then ↑(card G) else 0 := by
  split_ifs with h
  · simp [h, card_univ]
  obtain ⟨x, hx⟩ := ne_one_iff.1 h
  refine' eq_zero_of_mul_eq_self_left hx _
  rw [Finset.mul_sum]
  exact Fintype.sum_equiv (Equiv.addLeft x) _ _ fun y ↦ (map_add_mul _ _ _).symm

lemma sum_eq_zero_iff_ne_zero : ∑ x, ψ x = 0 ↔ ψ ≠ 0 := by
  rw [sum_eq_ite, Ne.ite_eq_right_iff]
  exact Nat.cast_ne_zero.2 Fintype.card_ne_zero

lemma sum_ne_zero_iff_eq_zero : ∑ x, ψ x ≠ 0 ↔ ψ = 0 :=
  sum_eq_zero_iff_ne_zero.not_left

end AddGroup

section AddCommGroup
variable [AddCommGroup G]

section CommMonoid
variable [CommMonoid R]

/-- The additive characters on a commutative additive group form a commutative group. -/
instance : AddCommGroup (AddChar G R) :=
  @Additive.addCommGroup (AddChar G R) _

@[simp]
lemma neg_apply (ψ : AddChar G R) (a : G) : (-ψ) a = ψ (-a) := rfl

@[simp]
lemma sub_apply (ψ χ : AddChar G R) (a : G) : (ψ - χ) a = ψ a * χ (-a) := rfl

end CommMonoid

section DivisionCommMonoid
variable [DivisionCommMonoid R]

-- TODO: Replace `map_zsmul_zpow`
@[simp]
lemma map_zsmul_eq_zpow (ψ : AddChar G R) (n : ℤ) (a : G) : ψ (n • a) = ψ a ^ n :=
  map_zpow ψ.toMonoidHom _ _

lemma map_neg_eq_inv (ψ : AddChar G R) (x : G) : ψ (-x) = (ψ x)⁻¹ :=
  eq_inv_of_mul_eq_one_left $ by simp [←map_add_mul]

lemma inv_apply' (ψ : AddChar G R) (x : G) : ψ⁻¹ x = (ψ x)⁻¹ :=
  map_neg_eq_inv _ _

lemma neg_apply' (ψ : AddChar G R) (x : G) : (-ψ) x = (ψ x)⁻¹ :=
  map_neg_eq_inv _ _

lemma sub_apply' (ψ χ : AddChar G R) (a : G) : (ψ - χ) a = ψ a / χ a := by
  rw [sub_apply, map_neg_eq_inv, div_eq_mul_inv]

end DivisionCommMonoid

section IsROrC
variable [IsROrC R] {ψ₁ ψ₂ : AddChar G R}

lemma l2inner_eq [Fintype G] (ψ₁ ψ₂ : AddChar G R) :
    ⟪(ψ₁ : G → R), ψ₂⟫_[R] = if ψ₁ = ψ₂ then ↑(card G) else 0 := by
  split_ifs with h
  · rw [h, AddChar.l2inner_self]
  have : ψ₁⁻¹ * ψ₂ ≠ 1 := by rwa [Ne.def, inv_mul_eq_one]
  simp_rw [l2inner_eq_sum, ←inv_apply_eq_conj]
  simpa [inv_apply'] using sum_eq_zero_iff_ne_zero.2 this

lemma l2inner_eq_zero_iff_ne [Fintype G] : ⟪(ψ₁ : G → R), ψ₂⟫_[R] = 0 ↔ ψ₁ ≠ ψ₂ := by
  rw [l2inner_eq, Ne.ite_eq_right_iff (Nat.cast_ne_zero.2 Fintype.card_ne_zero)]

lemma l2inner_eq_card_iff_eq [Fintype G] : ⟪(ψ₁ : G → R), ψ₂⟫_[R] = card G ↔ ψ₁ = ψ₂ := by
  rw [l2inner_eq, Ne.ite_eq_left_iff (Nat.cast_ne_zero.2 Fintype.card_ne_zero)]

variable (G R)

protected lemma linearIndependent [Finite G] : LinearIndependent R ((⇑) : AddChar G R → G → R) := by
  cases nonempty_fintype G
  exact linearIndependent_of_ne_zero_of_l2inner_eq_zero AddChar.coe_ne_zero fun ψ₁ ψ₂ ↦
    l2inner_eq_zero_iff_ne.2

noncomputable instance instFintype [Finite G] : Fintype (AddChar G R) :=
  @Fintype.ofFinite _ (AddChar.linearIndependent G R).finite'

@[simp] lemma card_addChar_le [Fintype G] : card (AddChar G R) ≤ card G := by
  simpa only [FiniteDimensional.finrank_fintype_fun_eq_card] using
    FiniteDimensional.fintype_card_le_finrank_of_linearIndependent (AddChar.linearIndependent G R)

end IsROrC

end AddCommGroup

section DirectSum
variable {ι : Type*} {π : ι → Type*} [DecidableEq ι] [∀ i, AddCommGroup (π i)] [CommMonoid R]

/-- Direct sum of additive characters. -/
protected def directSum (ψ : ∀ i, AddChar (π i) R) : AddChar (⨁ i, π i) R :=
  AddChar.toAddMonoidHom.symm
    (DirectSum.toAddMonoid fun i ↦ toAddMonoidHom (ψ i) : (⨁ i, π i) →+ Additive R)

lemma directSum_injective :
    Injective (AddChar.directSum : (∀ i, AddChar (π i) R) → AddChar (⨁ i, π i) R) := by
  refine' AddChar.toAddMonoidHom.symm.injective.comp $ DirectSum.toAddMonoid_injective.comp _
  rintro ψ χ h
  simpa [Function.funext_iff] using h

end DirectSum
end AddChar
