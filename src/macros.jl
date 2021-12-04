import Base.Meta: isexpr

"""
    @default_checked

Redirect default integer math to overflow-checked operators. Only works at top-level.
"""
macro default_checked()
return quote
    Base.eval(:((Base.:-)(x::T) where T <: Base.BitInteger = Main.checked_neg(x)))
    Base.eval(:((Base.:+)(x::T, y::T) where T <: Base.BitInteger = Main.checked_add(x, y)))
    Base.eval(:((Base.:-)(x::T, y::T) where T <: Base.BitInteger = Main.checked_sub(x, y)))
    Base.eval(:((Base.:*)(x::T, y::T) where T <: Base.BitInteger = Main.checked_mul(x, y)))
end
end

"""
    @default_unchecked

Restore default integer math to overflow-permissive operations. Only works at top-level.
"""
macro default_unchecked()
return quote
    Base.eval(:((Base.:-)(x::T) where T <: Base.BitInteger = Main.unchecked_neg(x)))
    Base.eval(:((Base.:+)(x::T, y::T) where T <: Base.BitInteger = Main.unchecked_add(x, y)))
    Base.eval(:((Base.:-)(x::T, y::T) where T <: Base.BitInteger = Main.unchecked_sub(x, y)))
    Base.eval(:((Base.:*)(x::T, y::T) where T <: Base.BitInteger = Main.unchecked_mul(x, y)))
end
end

"""
    @unchecked expr

Perform all integer operations in `expr` using overflow-permissive arithmetic.
"""
macro unchecked(expr::Expr)
    isa(expr, Expr) || return expr
    expr = copy(expr)
    return esc(replace_op!(expr, op_unchecked))
end

"""
    @checked expr

Perform all integer operations in `expr` using overflow-permissive arithmetic.
"""
macro checked(expr::Expr)
    isa(expr, Expr) || return expr
    expr = copy(expr)
    return esc(replace_op!(expr, op_checked))
end

const op_checked = Dict(
    Symbol("unary-") => :(checked_neg),
    Symbol("ambig-") => :(checked_negsub),
    :+ => :(checked_add),
    :- => :(checked_sub),
    :* => :(checked_mul),
    :+= => :(checked_add),
    :-= => :(checked_sub),
    :*= => :(checked_mul),
    # :abs => :(unchecked_abs)
)

const op_unchecked = Dict(
    Symbol("unary-") => :(unchecked_neg),
    Symbol("ambig-") => :(unchecked_negsub),
    :+ => :(unchecked_add),
    :- => :(unchecked_sub),
    :* => :(unchecked_mul),
    :+= => :(unchecked_add),
    :-= => :(unchecked_sub),
    :*= => :(unchecked_mul),
    # :abs => :(unchecked_abs)
)

# resolve ambiguity when `-` used as symbol
unchecked_negsub(x) = unchecked_neg(x)
unchecked_negsub(x, y) = unchecked_sub(x, y)
checked_negsub(x) = checked_neg(x)
checked_negsub(x, y) = checked_sub(x, y)

# copied from CheckedArithmetic.jl and modified it
function replace_op!(expr::Expr, op_map::Dict)
    if isexpr(expr, :call)
        f, len = expr.args[1], length(expr.args)
        op = isexpr(f, :.) ? f.args[2].value : f # handle module-scoped functions
        if op === :+ && len == 2                 # unary +
            # no action required
        elseif op === :- && len == 2             # unary -
            op = get(op_map, Symbol("unary-"), op)
            if isexpr(f, :.)
                f.args[2] = QuoteNode(op)
                expr.args[1] = f
            else
                expr.args[1] = op
            end
        else                                     # arbitrary call
            op = get(op_map, op, op)
            if isexpr(f, :.)
                f.args[2] = QuoteNode(op)
                expr.args[1] = f
            else
                expr.args[1] = op
            end
        end
        for i in 2:length(expr.args)
            a = expr.args[i]
            if isa(a, Expr)
                replace_op!(a, op_map)
            elseif isa(a, Symbol)                 # operator as symbol function argument, e.g. `fold(+, ...)`
                op = if a == :-
                    get(op_map, Symbol("ambig-"), a)
                else
                    get(op_map, a, a)
                end
                expr.args[i] = op
            end
        end
    elseif isexpr(expr, (:+=, :-=, :*=))          # in-place operator
        target = expr.args[1]
        arg = expr.args[2]
        op = expr.head
        op = get(op_map, op, op)
        expr.head = :(=)
        expr.args[2] = Expr(:call, op, target, arg)
    elseif !isexpr(expr, :macrocall) || expr.args[1] ∉ (Symbol("@checked"), Symbol("@unchecked"))
        for a in expr.args
            if isa(a, Expr)
                replace_op!(a, op_map)
            end
        end
    end
    return expr
end
