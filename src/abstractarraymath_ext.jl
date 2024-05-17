checked_neg(A::AbstractArray) = broadcast_preserving_zero_d(checked_neg, A)

for f in (:checked_add, :checked_sub)
    @eval function ($f)(A::AbstractArray, B::AbstractArray)
        promote_shape(A, B) # check size compatibility
        Base.broadcast_preserving_zero_d($f, A, B)
    end
end

checked_mul(A::AbstractArray, B::Number) = Base.broadcast_preserving_zero_d(checked_mul, A, B)