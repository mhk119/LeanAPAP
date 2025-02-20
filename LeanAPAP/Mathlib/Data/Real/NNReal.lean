import Mathlib.Data.Real.NNReal

open scoped NNReal

namespace NNReal
variable {x : ℝ≥0}

instance {M : Type*} [OrderedAddCommMonoid M] [Module ℝ M] [OrderedSMul ℝ M] :
    OrderedSMul ℝ≥0 M where
  smul_lt_smul_of_pos hab hc := (smul_lt_smul_of_pos hab (NNReal.coe_pos.2 hc) : _)
  lt_of_smul_lt_smul_of_pos {a b c} hab _ :=
    lt_of_smul_lt_smul_of_nonneg (by exact hab) (NNReal.coe_nonneg c)

@[simp]
lemma mk_le_mk {x y : ℝ} {hx : 0 ≤ x} {hy : 0 ≤ y} : (⟨x, hx⟩ : ℝ≥0) ≤ ⟨y, hy⟩ ↔ x ≤ y := Iff.rfl

@[simp, norm_cast]
lemma one_le_coe : 1 ≤ (x : ℝ) ↔ 1 ≤ x := by rw [←NNReal.coe_le_coe, NNReal.coe_one]

@[simp, norm_cast]
lemma one_lt_coe : 1 < (x : ℝ) ↔ 1 < x := by rw [←NNReal.coe_lt_coe, NNReal.coe_one]

lemma coe_ne_one : (x : ℝ) ≠ 1 ↔ x ≠ 1 := x.coe_eq_one.not

instance : StarRing ℝ≥0 := starRingOfComm
instance : TrivialStar ℝ≥0 := ⟨fun _ ↦ rfl⟩

end NNReal
