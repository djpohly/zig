const std = @import("std");
const mem = std.mem;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const Value = @import("value.zig").Value;
const Type = @import("type.zig").Type;
const TypedValue = @import("TypedValue.zig");
const zir = @import("zir.zig");
const Module = @import("Module.zig");
const ast = std.zig.ast;
const trace = @import("tracy.zig").trace;
const Scope = Module.Scope;
const InnerError = Module.InnerError;
const BuiltinFn = @import("BuiltinFn.zig");

pub const ResultLoc = union(enum) {
    /// The expression is the right-hand side of assignment to `_`. Only the side-effects of the
    /// expression should be generated. The result instruction from the expression must
    /// be ignored.
    discard,
    /// The expression has an inferred type, and it will be evaluated as an rvalue.
    none,
    /// The expression must generate a pointer rather than a value. For example, the left hand side
    /// of an assignment uses this kind of result location.
    ref,
    /// The expression will be coerced into this type, but it will be evaluated as an rvalue.
    ty: zir.Inst.Ref,
    /// The expression must store its result into this typed pointer. The result instruction
    /// from the expression must be ignored.
    ptr: zir.Inst.Ref,
    /// The expression must store its result into this allocation, which has an inferred type.
    /// The result instruction from the expression must be ignored.
    /// Always an instruction with tag `alloc_inferred`.
    inferred_ptr: zir.Inst.Ref,
    /// The expression must store its result into this pointer, which is a typed pointer that
    /// has been bitcasted to whatever the expression's type is.
    /// The result instruction from the expression must be ignored.
    bitcasted_ptr: zir.Inst.Ref,
    /// There is a pointer for the expression to store its result into, however, its type
    /// is inferred based on peer type resolution for a `zir.Inst.Block`.
    /// The result instruction from the expression must be ignored.
    block_ptr: *Module.Scope.GenZir,

    pub const Strategy = struct {
        elide_store_to_block_ptr_instructions: bool,
        tag: Tag,

        pub const Tag = enum {
            /// Both branches will use break_void; result location is used to communicate the
            /// result instruction.
            break_void,
            /// Use break statements to pass the block result value, and call rvalue() at
            /// the end depending on rl. Also elide the store_to_block_ptr instructions
            /// depending on rl.
            break_operand,
        };
    };
};

pub fn typeExpr(mod: *Module, scope: *Scope, type_node: ast.Node.Index) InnerError!zir.Inst.Ref {
    return expr(mod, scope, .{ .ty = .type_type }, type_node);
}

fn lvalExpr(mod: *Module, scope: *Scope, node: ast.Node.Index) InnerError!zir.Inst.Ref {
    const tree = scope.tree();
    const node_tags = tree.nodes.items(.tag);
    const main_tokens = tree.nodes.items(.main_token);
    switch (node_tags[node]) {
        .root => unreachable,
        .@"usingnamespace" => unreachable,
        .test_decl => unreachable,
        .global_var_decl => unreachable,
        .local_var_decl => unreachable,
        .simple_var_decl => unreachable,
        .aligned_var_decl => unreachable,
        .switch_case => unreachable,
        .switch_case_one => unreachable,
        .container_field_init => unreachable,
        .container_field_align => unreachable,
        .container_field => unreachable,
        .asm_output => unreachable,
        .asm_input => unreachable,

        .assign,
        .assign_bit_and,
        .assign_bit_or,
        .assign_bit_shift_left,
        .assign_bit_shift_right,
        .assign_bit_xor,
        .assign_div,
        .assign_sub,
        .assign_sub_wrap,
        .assign_mod,
        .assign_add,
        .assign_add_wrap,
        .assign_mul,
        .assign_mul_wrap,
        .add,
        .add_wrap,
        .sub,
        .sub_wrap,
        .mul,
        .mul_wrap,
        .div,
        .mod,
        .bit_and,
        .bit_or,
        .bit_shift_left,
        .bit_shift_right,
        .bit_xor,
        .bang_equal,
        .equal_equal,
        .greater_than,
        .greater_or_equal,
        .less_than,
        .less_or_equal,
        .array_cat,
        .array_mult,
        .bool_and,
        .bool_or,
        .@"asm",
        .asm_simple,
        .string_literal,
        .integer_literal,
        .call,
        .call_comma,
        .async_call,
        .async_call_comma,
        .call_one,
        .call_one_comma,
        .async_call_one,
        .async_call_one_comma,
        .unreachable_literal,
        .@"return",
        .@"if",
        .if_simple,
        .@"while",
        .while_simple,
        .while_cont,
        .bool_not,
        .address_of,
        .float_literal,
        .undefined_literal,
        .true_literal,
        .false_literal,
        .null_literal,
        .optional_type,
        .block,
        .block_semicolon,
        .block_two,
        .block_two_semicolon,
        .@"break",
        .ptr_type_aligned,
        .ptr_type_sentinel,
        .ptr_type,
        .ptr_type_bit_range,
        .array_type,
        .array_type_sentinel,
        .enum_literal,
        .multiline_string_literal,
        .char_literal,
        .@"defer",
        .@"errdefer",
        .@"catch",
        .error_union,
        .merge_error_sets,
        .switch_range,
        .@"await",
        .bit_not,
        .negation,
        .negation_wrap,
        .@"resume",
        .@"try",
        .slice,
        .slice_open,
        .slice_sentinel,
        .array_init_one,
        .array_init_one_comma,
        .array_init_dot_two,
        .array_init_dot_two_comma,
        .array_init_dot,
        .array_init_dot_comma,
        .array_init,
        .array_init_comma,
        .struct_init_one,
        .struct_init_one_comma,
        .struct_init_dot_two,
        .struct_init_dot_two_comma,
        .struct_init_dot,
        .struct_init_dot_comma,
        .struct_init,
        .struct_init_comma,
        .@"switch",
        .switch_comma,
        .@"for",
        .for_simple,
        .@"suspend",
        .@"continue",
        .@"anytype",
        .fn_proto_simple,
        .fn_proto_multi,
        .fn_proto_one,
        .fn_proto,
        .fn_decl,
        .anyframe_type,
        .anyframe_literal,
        .error_set_decl,
        .container_decl,
        .container_decl_trailing,
        .container_decl_two,
        .container_decl_two_trailing,
        .container_decl_arg,
        .container_decl_arg_trailing,
        .tagged_union,
        .tagged_union_trailing,
        .tagged_union_two,
        .tagged_union_two_trailing,
        .tagged_union_enum_tag,
        .tagged_union_enum_tag_trailing,
        .@"comptime",
        .@"nosuspend",
        .error_value,
        => return mod.failNode(scope, node, "invalid left-hand side to assignment", .{}),

        .builtin_call,
        .builtin_call_comma,
        .builtin_call_two,
        .builtin_call_two_comma,
        => {
            const builtin_token = main_tokens[node];
            const builtin_name = tree.tokenSlice(builtin_token);
            // If the builtin is an invalid name, we don't cause an error here; instead
            // let it pass, and the error will be "invalid builtin function" later.
            if (BuiltinFn.list.get(builtin_name)) |info| {
                if (!info.allows_lvalue) {
                    return mod.failNode(scope, node, "invalid left-hand side to assignment", .{});
                }
            }
        },

        // These can be assigned to.
        .unwrap_optional,
        .deref,
        .field_access,
        .array_access,
        .identifier,
        .grouped_expression,
        .@"orelse",
        => {},
    }
    return expr(mod, scope, .ref, node);
}

/// Turn Zig AST into untyped ZIR istructions.
/// When `rl` is discard, ptr, inferred_ptr, bitcasted_ptr, or inferred_ptr, the
/// result instruction can be used to inspect whether it is isNoReturn() but that is it,
/// it must otherwise not be used.
pub fn expr(mod: *Module, scope: *Scope, rl: ResultLoc, node: ast.Node.Index) InnerError!zir.Inst.Ref {
    const tree = scope.tree();
    const main_tokens = tree.nodes.items(.main_token);
    const token_tags = tree.tokens.items(.tag);
    const node_datas = tree.nodes.items(.data);
    const node_tags = tree.nodes.items(.tag);

    const gz = scope.getGenZir();

    switch (node_tags[node]) {
        .root => unreachable, // Top-level declaration.
        .@"usingnamespace" => unreachable, // Top-level declaration.
        .test_decl => unreachable, // Top-level declaration.
        .container_field_init => unreachable, // Top-level declaration.
        .container_field_align => unreachable, // Top-level declaration.
        .container_field => unreachable, // Top-level declaration.
        .fn_decl => unreachable, // Top-level declaration.

        .global_var_decl => unreachable, // Handled in `blockExpr`.
        .local_var_decl => unreachable, // Handled in `blockExpr`.
        .simple_var_decl => unreachable, // Handled in `blockExpr`.
        .aligned_var_decl => unreachable, // Handled in `blockExpr`.

        .switch_case => unreachable, // Handled in `switchExpr`.
        .switch_case_one => unreachable, // Handled in `switchExpr`.
        .switch_range => unreachable, // Handled in `switchExpr`.

        .asm_output => unreachable, // Handled in `asmExpr`.
        .asm_input => unreachable, // Handled in `asmExpr`.

        .assign => {
            try assign(mod, scope, node);
            return rvalue(mod, scope, rl, .void_value, node);
        },
        .assign_bit_and => {
            try assignOp(mod, scope, node, .bit_and);
            return rvalue(mod, scope, rl, .void_value, node);
        },
        .assign_bit_or => {
            try assignOp(mod, scope, node, .bit_or);
            return rvalue(mod, scope, rl, .void_value, node);
        },
        .assign_bit_shift_left => {
            try assignOp(mod, scope, node, .shl);
            return rvalue(mod, scope, rl, .void_value, node);
        },
        .assign_bit_shift_right => {
            try assignOp(mod, scope, node, .shr);
            return rvalue(mod, scope, rl, .void_value, node);
        },
        .assign_bit_xor => {
            try assignOp(mod, scope, node, .xor);
            return rvalue(mod, scope, rl, .void_value, node);
        },
        .assign_div => {
            try assignOp(mod, scope, node, .div);
            return rvalue(mod, scope, rl, .void_value, node);
        },
        .assign_sub => {
            try assignOp(mod, scope, node, .sub);
            return rvalue(mod, scope, rl, .void_value, node);
        },
        .assign_sub_wrap => {
            try assignOp(mod, scope, node, .subwrap);
            return rvalue(mod, scope, rl, .void_value, node);
        },
        .assign_mod => {
            try assignOp(mod, scope, node, .mod_rem);
            return rvalue(mod, scope, rl, .void_value, node);
        },
        .assign_add => {
            try assignOp(mod, scope, node, .add);
            return rvalue(mod, scope, rl, .void_value, node);
        },
        .assign_add_wrap => {
            try assignOp(mod, scope, node, .addwrap);
            return rvalue(mod, scope, rl, .void_value, node);
        },
        .assign_mul => {
            try assignOp(mod, scope, node, .mul);
            return rvalue(mod, scope, rl, .void_value, node);
        },
        .assign_mul_wrap => {
            try assignOp(mod, scope, node, .mulwrap);
            return rvalue(mod, scope, rl, .void_value, node);
        },

        .add => return simpleBinOp(mod, scope, rl, node, .add),
        .add_wrap => return simpleBinOp(mod, scope, rl, node, .addwrap),
        .sub => return simpleBinOp(mod, scope, rl, node, .sub),
        .sub_wrap => return simpleBinOp(mod, scope, rl, node, .subwrap),
        .mul => return simpleBinOp(mod, scope, rl, node, .mul),
        .mul_wrap => return simpleBinOp(mod, scope, rl, node, .mulwrap),
        .div => return simpleBinOp(mod, scope, rl, node, .div),
        .mod => return simpleBinOp(mod, scope, rl, node, .mod_rem),
        .bit_and => return simpleBinOp(mod, scope, rl, node, .bit_and),
        .bit_or => return simpleBinOp(mod, scope, rl, node, .bit_or),
        .bit_shift_left => return simpleBinOp(mod, scope, rl, node, .shl),
        .bit_shift_right => return simpleBinOp(mod, scope, rl, node, .shr),
        .bit_xor => return simpleBinOp(mod, scope, rl, node, .xor),

        .bang_equal => return simpleBinOp(mod, scope, rl, node, .cmp_neq),
        .equal_equal => return simpleBinOp(mod, scope, rl, node, .cmp_eq),
        .greater_than => return simpleBinOp(mod, scope, rl, node, .cmp_gt),
        .greater_or_equal => return simpleBinOp(mod, scope, rl, node, .cmp_gte),
        .less_than => return simpleBinOp(mod, scope, rl, node, .cmp_lt),
        .less_or_equal => return simpleBinOp(mod, scope, rl, node, .cmp_lte),

        .array_cat => return simpleBinOp(mod, scope, rl, node, .array_cat),
        .array_mult => return simpleBinOp(mod, scope, rl, node, .array_mul),

        .bool_and => return boolBinOp(mod, scope, rl, node, .bool_br_and),
        .bool_or => return boolBinOp(mod, scope, rl, node, .bool_br_or),

        .bool_not => return boolNot(mod, scope, rl, node),
        .bit_not => return bitNot(mod, scope, rl, node),

        .negation => return negation(mod, scope, rl, node, .negate),
        .negation_wrap => return negation(mod, scope, rl, node, .negate_wrap),

        .identifier => return identifier(mod, scope, rl, node),

        .asm_simple => return asmExpr(mod, scope, rl, node, tree.asmSimple(node)),
        .@"asm" => return asmExpr(mod, scope, rl, node, tree.asmFull(node)),

        .string_literal => return stringLiteral(mod, scope, rl, node),
        .multiline_string_literal => return multilineStringLiteral(mod, scope, rl, node),

        .integer_literal => return integerLiteral(mod, scope, rl, node),

        .builtin_call_two, .builtin_call_two_comma => {
            if (node_datas[node].lhs == 0) {
                const params = [_]ast.Node.Index{};
                return builtinCall(mod, scope, rl, node, &params);
            } else if (node_datas[node].rhs == 0) {
                const params = [_]ast.Node.Index{node_datas[node].lhs};
                return builtinCall(mod, scope, rl, node, &params);
            } else {
                const params = [_]ast.Node.Index{ node_datas[node].lhs, node_datas[node].rhs };
                return builtinCall(mod, scope, rl, node, &params);
            }
        },
        .builtin_call, .builtin_call_comma => {
            const params = tree.extra_data[node_datas[node].lhs..node_datas[node].rhs];
            return builtinCall(mod, scope, rl, node, params);
        },

        .call_one, .call_one_comma, .async_call_one, .async_call_one_comma => {
            var params: [1]ast.Node.Index = undefined;
            return callExpr(mod, scope, rl, node, tree.callOne(&params, node));
        },
        .call, .call_comma, .async_call, .async_call_comma => {
            return callExpr(mod, scope, rl, node, tree.callFull(node));
        },

        .unreachable_literal => {
            _ = try gz.addAsIndex(.{
                .tag = .@"unreachable",
                .data = .{ .@"unreachable" = .{
                    .safety = true,
                    .src_node = gz.zir_code.decl.nodeIndexToRelative(node),
                } },
            });
            return zir.Inst.Ref.unreachable_value;
        },
        .@"return" => return ret(mod, scope, node),
        .field_access => return fieldAccess(mod, scope, rl, node),
        .float_literal => return floatLiteral(mod, scope, rl, node),

        .if_simple => return ifExpr(mod, scope, rl, node, tree.ifSimple(node)),
        .@"if" => return ifExpr(mod, scope, rl, node, tree.ifFull(node)),

        .while_simple => return whileExpr(mod, scope, rl, node, tree.whileSimple(node)),
        .while_cont => return whileExpr(mod, scope, rl, node, tree.whileCont(node)),
        .@"while" => return whileExpr(mod, scope, rl, node, tree.whileFull(node)),

        .for_simple => return forExpr(mod, scope, rl, node, tree.forSimple(node)),
        .@"for" => return forExpr(mod, scope, rl, node, tree.forFull(node)),

        .slice_open => {
            const lhs = try expr(mod, scope, .{ .ty = .usize_type }, node_datas[node].lhs);
            const start = try expr(mod, scope, .{ .ty = .usize_type }, node_datas[node].rhs);
            const result = try gz.addPlNode(.slice_start, node, zir.Inst.SliceStart{
                .lhs = lhs,
                .start = start,
            });
            return rvalue(mod, scope, rl, result, node);
        },
        .slice => {
            const lhs = try expr(mod, scope, .{ .ty = .usize_type }, node_datas[node].lhs);
            const extra = tree.extraData(node_datas[node].rhs, ast.Node.Slice);
            const start = try expr(mod, scope, .{ .ty = .usize_type }, extra.start);
            const end = try expr(mod, scope, .{ .ty = .usize_type }, extra.end);
            const result = try gz.addPlNode(.slice_end, node, zir.Inst.SliceEnd{
                .lhs = lhs,
                .start = start,
                .end = end,
            });
            return rvalue(mod, scope, rl, result, node);
        },
        .slice_sentinel => {
            const lhs = try expr(mod, scope, .{ .ty = .usize_type }, node_datas[node].lhs);
            const extra = tree.extraData(node_datas[node].rhs, ast.Node.SliceSentinel);
            const start = try expr(mod, scope, .{ .ty = .usize_type }, extra.start);
            const end = try expr(mod, scope, .{ .ty = .usize_type }, extra.end);
            const sentinel = try expr(mod, scope, .{ .ty = .usize_type }, extra.sentinel);
            const result = try gz.addPlNode(.slice_sentinel, node, zir.Inst.SliceSentinel{
                .lhs = lhs,
                .start = start,
                .end = end,
                .sentinel = sentinel,
            });
            return rvalue(mod, scope, rl, result, node);
        },

        .deref => {
            const lhs = try expr(mod, scope, .none, node_datas[node].lhs);
            const result = try gz.addUnNode(.load, lhs, node);
            return rvalue(mod, scope, rl, result, node);
        },
        .address_of => {
            const result = try expr(mod, scope, .ref, node_datas[node].lhs);
            return rvalue(mod, scope, rl, result, node);
        },
        .undefined_literal => return rvalue(mod, scope, rl, .undef, node),
        .true_literal => return rvalue(mod, scope, rl, .bool_true, node),
        .false_literal => return rvalue(mod, scope, rl, .bool_false, node),
        .null_literal => return rvalue(mod, scope, rl, .null_value, node),
        .optional_type => {
            const operand = try typeExpr(mod, scope, node_datas[node].lhs);
            const result = try gz.addUnNode(.optional_type, operand, node);
            return rvalue(mod, scope, rl, result, node);
        },
        .unwrap_optional => switch (rl) {
            .ref => return gz.addUnNode(
                .optional_payload_safe_ptr,
                try expr(mod, scope, .ref, node_datas[node].lhs),
                node,
            ),
            else => return rvalue(mod, scope, rl, try gz.addUnNode(
                .optional_payload_safe,
                try expr(mod, scope, .none, node_datas[node].lhs),
                node,
            ), node),
        },
        .block_two, .block_two_semicolon => {
            const statements = [2]ast.Node.Index{ node_datas[node].lhs, node_datas[node].rhs };
            if (node_datas[node].lhs == 0) {
                return blockExpr(mod, scope, rl, node, statements[0..0]);
            } else if (node_datas[node].rhs == 0) {
                return blockExpr(mod, scope, rl, node, statements[0..1]);
            } else {
                return blockExpr(mod, scope, rl, node, statements[0..2]);
            }
        },
        .block, .block_semicolon => {
            const statements = tree.extra_data[node_datas[node].lhs..node_datas[node].rhs];
            return blockExpr(mod, scope, rl, node, statements);
        },
        .enum_literal => {
            const ident_token = main_tokens[node];
            const string_bytes = &gz.zir_code.string_bytes;
            const str_index = @intCast(u32, string_bytes.items.len);
            try mod.appendIdentStr(scope, ident_token, string_bytes);
            try string_bytes.append(mod.gpa, 0);
            const result = try gz.addStrTok(.enum_literal, str_index, ident_token);
            return rvalue(mod, scope, rl, result, node);
        },
        .error_value => {
            if (true) @panic("TODO update for zir-memory-layout");
            const ident_token = node_datas[node].rhs;
            const name = try mod.identifierTokenString(scope, ident_token);
            const result = try addZirInstTag(mod, scope, src, .error_value, .{ .name = name });
            return rvalue(mod, scope, rl, result);
        },
        .error_union => {
            if (true) @panic("TODO update for zir-memory-layout");
            const error_set = try typeExpr(mod, scope, node_datas[node].lhs);
            const payload = try typeExpr(mod, scope, node_datas[node].rhs);
            const result = try addZIRBinOp(mod, scope, src, .error_union_type, error_set, payload);
            return rvalue(mod, scope, rl, result);
        },
        .merge_error_sets => {
            if (true) @panic("TODO update for zir-memory-layout");
            const lhs = try typeExpr(mod, scope, node_datas[node].lhs);
            const rhs = try typeExpr(mod, scope, node_datas[node].rhs);
            const result = try addZIRBinOp(mod, scope, src, .merge_error_sets, lhs, rhs);
            return rvalue(mod, scope, rl, result);
        },
        .anyframe_literal => return mod.failNode(scope, node, "async and related features are not yet supported", .{}),
        .anyframe_type => return mod.failNode(scope, node, "async and related features are not yet supported", .{}),
        .@"catch" => {
            if (true) @panic("TODO update for zir-memory-layout");
            const catch_token = main_tokens[node];
            const payload_token: ?ast.TokenIndex = if (token_tags[catch_token + 1] == .pipe)
                catch_token + 2
            else
                null;
            switch (rl) {
                .ref => return orelseCatchExpr(
                    mod,
                    scope,
                    rl,
                    node,
                    node_datas[node].lhs,
                    .is_err_ptr,
                    .err_union_payload_unsafe_ptr,
                    .err_union_code_ptr,
                    node_datas[node].rhs,
                    payload_token,
                ),
                else => return orelseCatchExpr(
                    mod,
                    scope,
                    rl,
                    node,
                    node_datas[node].lhs,
                    .is_err,
                    .err_union_payload_unsafe,
                    .err_union_code,
                    node_datas[node].rhs,
                    payload_token,
                ),
            }
        },
        .@"orelse" => switch (rl) {
            .ref => return orelseCatchExpr(
                mod,
                scope,
                rl,
                node,
                node_datas[node].lhs,
                .is_null_ptr,
                .optional_payload_unsafe_ptr,
                undefined,
                node_datas[node].rhs,
                null,
            ),
            else => return orelseCatchExpr(
                mod,
                scope,
                rl,
                node,
                node_datas[node].lhs,
                .is_null,
                .optional_payload_unsafe,
                undefined,
                node_datas[node].rhs,
                null,
            ),
        },

        .ptr_type_aligned => return ptrType(mod, scope, rl, node, tree.ptrTypeAligned(node)),
        .ptr_type_sentinel => return ptrType(mod, scope, rl, node, tree.ptrTypeSentinel(node)),
        .ptr_type => return ptrType(mod, scope, rl, node, tree.ptrType(node)),
        .ptr_type_bit_range => return ptrType(mod, scope, rl, node, tree.ptrTypeBitRange(node)),

        .container_decl,
        .container_decl_trailing,
        => return containerDecl(mod, scope, rl, tree.containerDecl(node)),
        .container_decl_two, .container_decl_two_trailing => {
            var buffer: [2]ast.Node.Index = undefined;
            return containerDecl(mod, scope, rl, tree.containerDeclTwo(&buffer, node));
        },
        .container_decl_arg,
        .container_decl_arg_trailing,
        => return containerDecl(mod, scope, rl, tree.containerDeclArg(node)),

        .tagged_union,
        .tagged_union_trailing,
        => return containerDecl(mod, scope, rl, tree.taggedUnion(node)),
        .tagged_union_two, .tagged_union_two_trailing => {
            var buffer: [2]ast.Node.Index = undefined;
            return containerDecl(mod, scope, rl, tree.taggedUnionTwo(&buffer, node));
        },
        .tagged_union_enum_tag,
        .tagged_union_enum_tag_trailing,
        => return containerDecl(mod, scope, rl, tree.taggedUnionEnumTag(node)),

        .@"break" => return breakExpr(mod, scope, node),
        .@"continue" => return continueExpr(mod, scope, node),
        .grouped_expression => return expr(mod, scope, rl, node_datas[node].lhs),
        .array_type => return arrayType(mod, scope, rl, node),
        .array_type_sentinel => return arrayTypeSentinel(mod, scope, rl, node),
        .char_literal => return charLiteral(mod, scope, rl, node),
        .error_set_decl => return errorSetDecl(mod, scope, rl, node),
        .array_access => return arrayAccess(mod, scope, rl, node),
        .@"comptime" => return comptimeExpr(mod, scope, rl, node_datas[node].lhs),
        .@"switch", .switch_comma => return switchExpr(mod, scope, rl, node),

        .@"nosuspend" => return mod.failNode(scope, node, "async and related features are not yet supported", .{}),
        .@"suspend" => return mod.failNode(scope, node, "async and related features are not yet supported", .{}),
        .@"await" => return mod.failNode(scope, node, "async and related features are not yet supported", .{}),
        .@"resume" => return mod.failNode(scope, node, "async and related features are not yet supported", .{}),

        .@"defer" => return mod.failNode(scope, node, "TODO implement astgen.expr for .defer", .{}),
        .@"errdefer" => return mod.failNode(scope, node, "TODO implement astgen.expr for .errdefer", .{}),
        .@"try" => return mod.failNode(scope, node, "TODO implement astgen.expr for .Try", .{}),

        .array_init_one,
        .array_init_one_comma,
        .array_init_dot_two,
        .array_init_dot_two_comma,
        .array_init_dot,
        .array_init_dot_comma,
        .array_init,
        .array_init_comma,
        => return mod.failNode(scope, node, "TODO implement astgen.expr for array literals", .{}),

        .struct_init_one,
        .struct_init_one_comma,
        .struct_init_dot_two,
        .struct_init_dot_two_comma,
        .struct_init_dot,
        .struct_init_dot_comma,
        .struct_init,
        .struct_init_comma,
        => return mod.failNode(scope, node, "TODO implement astgen.expr for struct literals", .{}),

        .@"anytype" => return mod.failNode(scope, node, "TODO implement astgen.expr for .anytype", .{}),
        .fn_proto_simple,
        .fn_proto_multi,
        .fn_proto_one,
        .fn_proto,
        => return mod.failNode(scope, node, "TODO implement astgen.expr for function prototypes", .{}),
    }
}

pub fn comptimeExpr(
    mod: *Module,
    parent_scope: *Scope,
    rl: ResultLoc,
    node: ast.Node.Index,
) InnerError!zir.Inst.Ref {
    const gz = parent_scope.getGenZir();

    const prev_force_comptime = gz.force_comptime;
    gz.force_comptime = true;
    const result = try expr(mod, parent_scope, rl, node);
    gz.force_comptime = prev_force_comptime;
    return result;
}

fn breakExpr(mod: *Module, parent_scope: *Scope, node: ast.Node.Index) InnerError!zir.Inst.Ref {
    const parent_gz = parent_scope.getGenZir();
    const tree = parent_gz.tree();
    const node_datas = tree.nodes.items(.data);
    const break_label = node_datas[node].lhs;
    const rhs = node_datas[node].rhs;

    // Look for the label in the scope.
    var scope = parent_scope;
    while (true) {
        switch (scope.tag) {
            .gen_zir => {
                const block_gz = scope.cast(Scope.GenZir).?;

                const block_inst = blk: {
                    if (break_label != 0) {
                        if (block_gz.label) |*label| {
                            if (try tokenIdentEql(mod, parent_scope, label.token, break_label)) {
                                label.used = true;
                                break :blk label.block_inst;
                            }
                        }
                    } else if (block_gz.break_block != 0) {
                        break :blk block_gz.break_block;
                    }
                    scope = block_gz.parent;
                    continue;
                };

                if (rhs == 0) {
                    _ = try parent_gz.addBreak(.@"break", block_inst, .void_value);
                    return zir.Inst.Ref.unreachable_value;
                }
                block_gz.break_count += 1;
                const prev_rvalue_rl_count = block_gz.rvalue_rl_count;
                const operand = try expr(mod, parent_scope, block_gz.break_result_loc, rhs);
                const have_store_to_block = block_gz.rvalue_rl_count != prev_rvalue_rl_count;

                const br = try parent_gz.addBreak(.@"break", block_inst, operand);

                if (block_gz.break_result_loc == .block_ptr) {
                    try block_gz.labeled_breaks.append(mod.gpa, br);

                    if (have_store_to_block) {
                        const zir_tags = parent_gz.zir_code.instructions.items(.tag);
                        const zir_datas = parent_gz.zir_code.instructions.items(.data);
                        const store_inst = @intCast(u32, zir_tags.len - 2);
                        assert(zir_tags[store_inst] == .store_to_block_ptr);
                        assert(zir_datas[store_inst].bin.lhs == block_gz.rl_ptr);
                        try block_gz.labeled_store_to_block_ptr_list.append(mod.gpa, store_inst);
                    }
                }
                return zir.Inst.Ref.unreachable_value;
            },
            .local_val => scope = scope.cast(Scope.LocalVal).?.parent,
            .local_ptr => scope = scope.cast(Scope.LocalPtr).?.parent,
            else => if (break_label != 0) {
                const label_name = try mod.identifierTokenString(parent_scope, break_label);
                return mod.failTok(parent_scope, break_label, "label not found: '{s}'", .{label_name});
            } else {
                return mod.failNode(parent_scope, node, "break expression outside loop", .{});
            },
        }
    }
}

fn continueExpr(mod: *Module, parent_scope: *Scope, node: ast.Node.Index) InnerError!zir.Inst.Ref {
    if (true) @panic("TODO update for zir-memory-layout");
    const tree = parent_scope.tree();
    const node_datas = tree.nodes.items(.data);
    const main_tokens = tree.nodes.items(.main_token);

    const break_label = node_datas[node].lhs;

    // Look for the label in the scope.
    var scope = parent_scope;
    while (true) {
        switch (scope.tag) {
            .gen_zir => {
                const gen_zir = scope.cast(Scope.GenZir).?;
                const continue_block = gen_zir.continue_block orelse {
                    scope = gen_zir.parent;
                    continue;
                };
                if (break_label != 0) blk: {
                    if (gen_zir.label) |*label| {
                        if (try tokenIdentEql(mod, parent_scope, label.token, break_label)) {
                            label.used = true;
                            break :blk;
                        }
                    }
                    // found continue but either it has a different label, or no label
                    scope = gen_zir.parent;
                    continue;
                }

                _ = try addZirInstTag(mod, parent_scope, src, .break_void, .{
                    .block = continue_block,
                });
                return zir.Inst.Ref.unreachable_value;
            },
            .local_val => scope = scope.cast(Scope.LocalVal).?.parent,
            .local_ptr => scope = scope.cast(Scope.LocalPtr).?.parent,
            else => if (break_label != 0) {
                const label_name = try mod.identifierTokenString(parent_scope, break_label);
                return mod.failTok(parent_scope, break_label, "label not found: '{s}'", .{label_name});
            } else {
                return mod.failTok(parent_scope, src, "continue expression outside loop", .{});
            },
        }
    }
}

pub fn blockExpr(
    mod: *Module,
    scope: *Scope,
    rl: ResultLoc,
    block_node: ast.Node.Index,
    statements: []const ast.Node.Index,
) InnerError!zir.Inst.Ref {
    const tracy = trace(@src());
    defer tracy.end();

    const tree = scope.tree();
    const main_tokens = tree.nodes.items(.main_token);
    const token_tags = tree.tokens.items(.tag);

    const lbrace = main_tokens[block_node];
    if (token_tags[lbrace - 1] == .colon and
        token_tags[lbrace - 2] == .identifier)
    {
        return labeledBlockExpr(mod, scope, rl, block_node, statements, .block);
    }

    try blockExprStmts(mod, scope, block_node, statements);
    return rvalue(mod, scope, rl, .void_value, block_node);
}

fn checkLabelRedefinition(mod: *Module, parent_scope: *Scope, label: ast.TokenIndex) !void {
    // Look for the label in the scope.
    var scope = parent_scope;
    while (true) {
        switch (scope.tag) {
            .gen_zir => {
                const gen_zir = scope.cast(Scope.GenZir).?;
                if (gen_zir.label) |prev_label| {
                    if (try tokenIdentEql(mod, parent_scope, label, prev_label.token)) {
                        const tree = parent_scope.tree();
                        const main_tokens = tree.nodes.items(.main_token);

                        const label_name = try mod.identifierTokenString(parent_scope, label);
                        const msg = msg: {
                            const msg = try mod.errMsg(
                                parent_scope,
                                gen_zir.tokSrcLoc(label),
                                "redefinition of label '{s}'",
                                .{label_name},
                            );
                            errdefer msg.destroy(mod.gpa);
                            try mod.errNote(
                                parent_scope,
                                gen_zir.tokSrcLoc(prev_label.token),
                                msg,
                                "previous definition is here",
                                .{},
                            );
                            break :msg msg;
                        };
                        return mod.failWithOwnedErrorMsg(parent_scope, msg);
                    }
                }
                scope = gen_zir.parent;
            },
            .local_val => scope = scope.cast(Scope.LocalVal).?.parent,
            .local_ptr => scope = scope.cast(Scope.LocalPtr).?.parent,
            else => return,
        }
    }
}

fn labeledBlockExpr(
    mod: *Module,
    parent_scope: *Scope,
    rl: ResultLoc,
    block_node: ast.Node.Index,
    statements: []const ast.Node.Index,
    zir_tag: zir.Inst.Tag,
) InnerError!zir.Inst.Ref {
    const tracy = trace(@src());
    defer tracy.end();

    assert(zir_tag == .block);

    const tree = parent_scope.tree();
    const main_tokens = tree.nodes.items(.main_token);
    const token_tags = tree.tokens.items(.tag);

    const lbrace = main_tokens[block_node];
    const label_token = lbrace - 2;
    assert(token_tags[label_token] == .identifier);

    try checkLabelRedefinition(mod, parent_scope, label_token);

    // Reserve the Block ZIR instruction index so that we can put it into the GenZir struct
    // so that break statements can reference it.
    const gz = parent_scope.getGenZir();
    const block_inst = try gz.addBlock(zir_tag, block_node);
    try gz.instructions.append(mod.gpa, block_inst);

    var block_scope: Scope.GenZir = .{
        .parent = parent_scope,
        .zir_code = gz.zir_code,
        .force_comptime = gz.force_comptime,
        .instructions = .{},
        // TODO @as here is working around a stage1 miscompilation bug :(
        .label = @as(?Scope.GenZir.Label, Scope.GenZir.Label{
            .token = label_token,
            .block_inst = block_inst,
        }),
    };
    setBlockResultLoc(&block_scope, rl);
    defer block_scope.instructions.deinit(mod.gpa);
    defer block_scope.labeled_breaks.deinit(mod.gpa);
    defer block_scope.labeled_store_to_block_ptr_list.deinit(mod.gpa);

    try blockExprStmts(mod, &block_scope.base, block_node, statements);

    if (!block_scope.label.?.used) {
        return mod.failTok(parent_scope, label_token, "unused block label", .{});
    }

    const zir_tags = gz.zir_code.instructions.items(.tag);
    const zir_datas = gz.zir_code.instructions.items(.data);

    const strat = rlStrategy(rl, &block_scope);
    switch (strat.tag) {
        .break_void => {
            // The code took advantage of the result location as a pointer.
            // Turn the break instruction operands into void.
            for (block_scope.labeled_breaks.items) |br| {
                zir_datas[br].@"break".operand = .void_value;
            }
            try block_scope.setBlockBody(block_inst);

            return gz.zir_code.indexToRef(block_inst);
        },
        .break_operand => {
            // All break operands are values that did not use the result location pointer.
            if (strat.elide_store_to_block_ptr_instructions) {
                for (block_scope.labeled_store_to_block_ptr_list.items) |inst| {
                    zir_tags[inst] = .elided;
                    zir_datas[inst] = undefined;
                }
                // TODO technically not needed since we changed the tag to elided but
                // would be better still to elide the ones that are in this list.
            }
            try block_scope.setBlockBody(block_inst);
            const block_ref = gz.zir_code.indexToRef(block_inst);
            switch (rl) {
                .ref => return block_ref,
                else => return rvalue(mod, parent_scope, rl, block_ref, block_node),
            }
        },
    }
}

fn blockExprStmts(
    mod: *Module,
    parent_scope: *Scope,
    node: ast.Node.Index,
    statements: []const ast.Node.Index,
) !void {
    const tree = parent_scope.tree();
    const main_tokens = tree.nodes.items(.main_token);
    const node_tags = tree.nodes.items(.tag);

    var block_arena = std.heap.ArenaAllocator.init(mod.gpa);
    defer block_arena.deinit();

    const gz = parent_scope.getGenZir();

    var scope = parent_scope;
    for (statements) |statement| {
        if (!gz.force_comptime) {
            _ = try gz.addNode(.dbg_stmt_node, statement);
        }
        switch (node_tags[statement]) {
            .global_var_decl => scope = try varDecl(mod, scope, statement, &block_arena.allocator, tree.globalVarDecl(statement)),
            .local_var_decl => scope = try varDecl(mod, scope, statement, &block_arena.allocator, tree.localVarDecl(statement)),
            .simple_var_decl => scope = try varDecl(mod, scope, statement, &block_arena.allocator, tree.simpleVarDecl(statement)),
            .aligned_var_decl => scope = try varDecl(mod, scope, statement, &block_arena.allocator, tree.alignedVarDecl(statement)),

            .assign => try assign(mod, scope, statement),
            .assign_bit_and => try assignOp(mod, scope, statement, .bit_and),
            .assign_bit_or => try assignOp(mod, scope, statement, .bit_or),
            .assign_bit_shift_left => try assignOp(mod, scope, statement, .shl),
            .assign_bit_shift_right => try assignOp(mod, scope, statement, .shr),
            .assign_bit_xor => try assignOp(mod, scope, statement, .xor),
            .assign_div => try assignOp(mod, scope, statement, .div),
            .assign_sub => try assignOp(mod, scope, statement, .sub),
            .assign_sub_wrap => try assignOp(mod, scope, statement, .subwrap),
            .assign_mod => try assignOp(mod, scope, statement, .mod_rem),
            .assign_add => try assignOp(mod, scope, statement, .add),
            .assign_add_wrap => try assignOp(mod, scope, statement, .addwrap),
            .assign_mul => try assignOp(mod, scope, statement, .mul),
            .assign_mul_wrap => try assignOp(mod, scope, statement, .mulwrap),

            else => {
                // We need to emit an error if the result is not `noreturn` or `void`, but
                // we want to avoid adding the ZIR instruction if possible for performance.
                const maybe_unused_result = try expr(mod, scope, .none, statement);
                const elide_check = if (gz.zir_code.refToIndex(maybe_unused_result)) |inst| b: {
                    // Note that this array becomes invalid after appending more items to it
                    // in the above while loop.
                    const zir_tags = gz.zir_code.instructions.items(.tag);
                    switch (zir_tags[inst]) {
                        .@"const" => {
                            const tv = gz.zir_code.instructions.items(.data)[inst].@"const";
                            break :b switch (tv.ty.zigTypeTag()) {
                                .NoReturn, .Void => true,
                                else => false,
                            };
                        },
                        // For some instructions, swap in a slightly different ZIR tag
                        // so we can avoid a separate ensure_result_used instruction.
                        .call_none_chkused => unreachable,
                        .call_none => {
                            zir_tags[inst] = .call_none_chkused;
                            break :b true;
                        },
                        .call_chkused => unreachable,
                        .call => {
                            zir_tags[inst] = .call_chkused;
                            break :b true;
                        },

                        // ZIR instructions that might be a type other than `noreturn` or `void`.
                        .add,
                        .addwrap,
                        .alloc,
                        .alloc_mut,
                        .alloc_inferred,
                        .alloc_inferred_mut,
                        .array_cat,
                        .array_mul,
                        .array_type,
                        .array_type_sentinel,
                        .indexable_ptr_len,
                        .as,
                        .as_node,
                        .@"asm",
                        .asm_volatile,
                        .bit_and,
                        .bitcast,
                        .bitcast_ref,
                        .bitcast_result_ptr,
                        .bit_or,
                        .block,
                        .block_inline,
                        .loop,
                        .bool_br_and,
                        .bool_br_or,
                        .bool_not,
                        .bool_and,
                        .bool_or,
                        .call_compile_time,
                        .cmp_lt,
                        .cmp_lte,
                        .cmp_eq,
                        .cmp_gte,
                        .cmp_gt,
                        .cmp_neq,
                        .coerce_result_ptr,
                        .decl_ref,
                        .decl_val,
                        .load,
                        .div,
                        .elem_ptr,
                        .elem_val,
                        .elem_ptr_node,
                        .elem_val_node,
                        .floatcast,
                        .field_ptr,
                        .field_val,
                        .field_ptr_named,
                        .field_val_named,
                        .fn_type,
                        .fn_type_var_args,
                        .fn_type_cc,
                        .fn_type_cc_var_args,
                        .int,
                        .intcast,
                        .int_type,
                        .is_non_null,
                        .is_null,
                        .is_non_null_ptr,
                        .is_null_ptr,
                        .is_err,
                        .is_err_ptr,
                        .mod_rem,
                        .mul,
                        .mulwrap,
                        .param_type,
                        .ptrtoint,
                        .ref,
                        .ret_ptr,
                        .ret_type,
                        .shl,
                        .shr,
                        .str,
                        .sub,
                        .subwrap,
                        .negate,
                        .negate_wrap,
                        .typeof,
                        .xor,
                        .optional_type,
                        .optional_type_from_ptr_elem,
                        .optional_payload_safe,
                        .optional_payload_unsafe,
                        .optional_payload_safe_ptr,
                        .optional_payload_unsafe_ptr,
                        .err_union_payload_safe,
                        .err_union_payload_unsafe,
                        .err_union_payload_safe_ptr,
                        .err_union_payload_unsafe_ptr,
                        .err_union_code,
                        .err_union_code_ptr,
                        .ptr_type,
                        .ptr_type_simple,
                        .enum_literal,
                        .enum_literal_small,
                        .merge_error_sets,
                        .error_union_type,
                        .bit_not,
                        .error_set,
                        .error_value,
                        .slice_start,
                        .slice_end,
                        .slice_sentinel,
                        .import,
                        .typeof_peer,
                        => break :b false,

                        // ZIR instructions that are always either `noreturn` or `void`.
                        .breakpoint,
                        .dbg_stmt_node,
                        .ensure_result_used,
                        .ensure_result_non_error,
                        .set_eval_branch_quota,
                        .compile_log,
                        .ensure_err_payload_void,
                        .@"break",
                        .break_inline,
                        .condbr,
                        .condbr_inline,
                        .compile_error,
                        .ret_node,
                        .ret_tok,
                        .ret_coerce,
                        .@"unreachable",
                        .elided,
                        .store,
                        .store_node,
                        .store_to_block_ptr,
                        .store_to_inferred_ptr,
                        .resolve_inferred_alloc,
                        .repeat,
                        .repeat_inline,
                        => break :b true,
                    }
                } else switch (maybe_unused_result) {
                    .none => unreachable,

                    .void_value,
                    .unreachable_value,
                    => true,

                    else => false,
                };
                if (!elide_check) {
                    _ = try gz.addUnNode(.ensure_result_used, maybe_unused_result, statement);
                }
            },
        }
    }
}

fn varDecl(
    mod: *Module,
    scope: *Scope,
    node: ast.Node.Index,
    block_arena: *Allocator,
    var_decl: ast.full.VarDecl,
) InnerError!*Scope {
    if (var_decl.comptime_token) |comptime_token| {
        return mod.failTok(scope, comptime_token, "TODO implement comptime locals", .{});
    }
    if (var_decl.ast.align_node != 0) {
        return mod.failNode(scope, var_decl.ast.align_node, "TODO implement alignment on locals", .{});
    }
    const gz = scope.getGenZir();
    const wzc = gz.zir_code;
    const tree = scope.tree();
    const token_tags = tree.tokens.items(.tag);

    const name_token = var_decl.ast.mut_token + 1;
    const name_src = gz.tokSrcLoc(name_token);
    const ident_name = try mod.identifierTokenString(scope, name_token);

    // Local variables shadowing detection, including function parameters.
    {
        var s = scope;
        while (true) switch (s.tag) {
            .local_val => {
                const local_val = s.cast(Scope.LocalVal).?;
                if (mem.eql(u8, local_val.name, ident_name)) {
                    const msg = msg: {
                        const msg = try mod.errMsg(scope, name_src, "redefinition of '{s}'", .{
                            ident_name,
                        });
                        errdefer msg.destroy(mod.gpa);
                        try mod.errNote(scope, local_val.src, msg, "previous definition is here", .{});
                        break :msg msg;
                    };
                    return mod.failWithOwnedErrorMsg(scope, msg);
                }
                s = local_val.parent;
            },
            .local_ptr => {
                const local_ptr = s.cast(Scope.LocalPtr).?;
                if (mem.eql(u8, local_ptr.name, ident_name)) {
                    const msg = msg: {
                        const msg = try mod.errMsg(scope, name_src, "redefinition of '{s}'", .{
                            ident_name,
                        });
                        errdefer msg.destroy(mod.gpa);
                        try mod.errNote(scope, local_ptr.src, msg, "previous definition is here", .{});
                        break :msg msg;
                    };
                    return mod.failWithOwnedErrorMsg(scope, msg);
                }
                s = local_ptr.parent;
            },
            .gen_zir => s = s.cast(Scope.GenZir).?.parent,
            else => break,
        };
    }

    // Namespace vars shadowing detection
    if (mod.lookupDeclName(scope, ident_name)) |_| {
        // TODO add note for other definition
        return mod.fail(scope, name_src, "redefinition of '{s}'", .{ident_name});
    }
    if (var_decl.ast.init_node == 0) {
        return mod.fail(scope, name_src, "variables must be initialized", .{});
    }

    switch (token_tags[var_decl.ast.mut_token]) {
        .keyword_const => {
            // Depending on the type of AST the initialization expression is, we may need an lvalue
            // or an rvalue as a result location. If it is an rvalue, we can use the instruction as
            // the variable, no memory location needed.
            if (!nodeMayNeedMemoryLocation(scope, var_decl.ast.init_node)) {
                const result_loc: ResultLoc = if (var_decl.ast.type_node != 0) .{
                    .ty = try typeExpr(mod, scope, var_decl.ast.type_node),
                } else .none;
                const init_inst = try expr(mod, scope, result_loc, var_decl.ast.init_node);
                const sub_scope = try block_arena.create(Scope.LocalVal);
                sub_scope.* = .{
                    .parent = scope,
                    .gen_zir = gz,
                    .name = ident_name,
                    .inst = init_inst,
                    .src = name_src,
                };
                return &sub_scope.base;
            }

            // Detect whether the initialization expression actually uses the
            // result location pointer.
            var init_scope: Scope.GenZir = .{
                .parent = scope,
                .force_comptime = gz.force_comptime,
                .zir_code = wzc,
            };
            defer init_scope.instructions.deinit(mod.gpa);

            var resolve_inferred_alloc: zir.Inst.Ref = .none;
            var opt_type_inst: zir.Inst.Ref = .none;
            if (var_decl.ast.type_node != 0) {
                const type_inst = try typeExpr(mod, &init_scope.base, var_decl.ast.type_node);
                opt_type_inst = type_inst;
                init_scope.rl_ptr = try init_scope.addUnNode(.alloc, type_inst, node);
            } else {
                const alloc = try init_scope.addUnNode(.alloc_inferred, undefined, node);
                resolve_inferred_alloc = alloc;
                init_scope.rl_ptr = alloc;
            }
            const init_result_loc: ResultLoc = .{ .block_ptr = &init_scope };
            const init_inst = try expr(mod, &init_scope.base, init_result_loc, var_decl.ast.init_node);
            const zir_tags = wzc.instructions.items(.tag);
            const zir_datas = wzc.instructions.items(.data);

            const parent_zir = &gz.instructions;
            if (init_scope.rvalue_rl_count == 1) {
                // Result location pointer not used. We don't need an alloc for this
                // const local, and type inference becomes trivial.
                // Move the init_scope instructions into the parent scope, eliding
                // the alloc instruction and the store_to_block_ptr instruction.
                const expected_len = parent_zir.items.len + init_scope.instructions.items.len - 2;
                try parent_zir.ensureCapacity(mod.gpa, expected_len);
                for (init_scope.instructions.items) |src_inst| {
                    if (wzc.indexToRef(src_inst) == init_scope.rl_ptr) continue;
                    if (zir_tags[src_inst] == .store_to_block_ptr) {
                        if (zir_datas[src_inst].bin.lhs == init_scope.rl_ptr) continue;
                    }
                    parent_zir.appendAssumeCapacity(src_inst);
                }
                assert(parent_zir.items.len == expected_len);
                const casted_init = if (opt_type_inst != .none)
                    try gz.addPlNode(.as_node, var_decl.ast.type_node, zir.Inst.As{
                        .dest_type = opt_type_inst,
                        .operand = init_inst,
                    })
                else
                    init_inst;

                const sub_scope = try block_arena.create(Scope.LocalVal);
                sub_scope.* = .{
                    .parent = scope,
                    .gen_zir = gz,
                    .name = ident_name,
                    .inst = casted_init,
                    .src = name_src,
                };
                return &sub_scope.base;
            }
            // The initialization expression took advantage of the result location
            // of the const local. In this case we will create an alloc and a LocalPtr for it.
            // Move the init_scope instructions into the parent scope, swapping
            // store_to_block_ptr for store_to_inferred_ptr.
            const expected_len = parent_zir.items.len + init_scope.instructions.items.len;
            try parent_zir.ensureCapacity(mod.gpa, expected_len);
            for (init_scope.instructions.items) |src_inst| {
                if (zir_tags[src_inst] == .store_to_block_ptr) {
                    if (zir_datas[src_inst].bin.lhs == init_scope.rl_ptr) {
                        zir_tags[src_inst] = .store_to_inferred_ptr;
                    }
                }
                parent_zir.appendAssumeCapacity(src_inst);
            }
            assert(parent_zir.items.len == expected_len);
            if (resolve_inferred_alloc != .none) {
                _ = try gz.addUnNode(.resolve_inferred_alloc, resolve_inferred_alloc, node);
            }
            const sub_scope = try block_arena.create(Scope.LocalPtr);
            sub_scope.* = .{
                .parent = scope,
                .gen_zir = gz,
                .name = ident_name,
                .ptr = init_scope.rl_ptr,
                .src = name_src,
            };
            return &sub_scope.base;
        },
        .keyword_var => {
            var resolve_inferred_alloc: zir.Inst.Ref = .none;
            const var_data: struct {
                result_loc: ResultLoc,
                alloc: zir.Inst.Ref,
            } = if (var_decl.ast.type_node != 0) a: {
                const type_inst = try typeExpr(mod, scope, var_decl.ast.type_node);

                const alloc = try gz.addUnNode(.alloc_mut, type_inst, node);
                break :a .{ .alloc = alloc, .result_loc = .{ .ptr = alloc } };
            } else a: {
                const alloc = try gz.addUnNode(.alloc_inferred_mut, undefined, node);
                resolve_inferred_alloc = alloc;
                break :a .{ .alloc = alloc, .result_loc = .{ .inferred_ptr = alloc } };
            };
            const init_inst = try expr(mod, scope, var_data.result_loc, var_decl.ast.init_node);
            if (resolve_inferred_alloc != .none) {
                _ = try gz.addUnNode(.resolve_inferred_alloc, resolve_inferred_alloc, node);
            }
            const sub_scope = try block_arena.create(Scope.LocalPtr);
            sub_scope.* = .{
                .parent = scope,
                .gen_zir = gz,
                .name = ident_name,
                .ptr = var_data.alloc,
                .src = name_src,
            };
            return &sub_scope.base;
        },
        else => unreachable,
    }
}

fn assign(mod: *Module, scope: *Scope, infix_node: ast.Node.Index) InnerError!void {
    const tree = scope.tree();
    const node_datas = tree.nodes.items(.data);
    const main_tokens = tree.nodes.items(.main_token);
    const node_tags = tree.nodes.items(.tag);

    const lhs = node_datas[infix_node].lhs;
    const rhs = node_datas[infix_node].rhs;
    if (node_tags[lhs] == .identifier) {
        // This intentionally does not support `@"_"` syntax.
        const ident_name = tree.tokenSlice(main_tokens[lhs]);
        if (mem.eql(u8, ident_name, "_")) {
            _ = try expr(mod, scope, .discard, rhs);
            return;
        }
    }
    const lvalue = try lvalExpr(mod, scope, lhs);
    _ = try expr(mod, scope, .{ .ptr = lvalue }, rhs);
}

fn assignOp(
    mod: *Module,
    scope: *Scope,
    infix_node: ast.Node.Index,
    op_inst_tag: zir.Inst.Tag,
) InnerError!void {
    const tree = scope.tree();
    const node_datas = tree.nodes.items(.data);
    const gz = scope.getGenZir();

    const lhs_ptr = try lvalExpr(mod, scope, node_datas[infix_node].lhs);
    const lhs = try gz.addUnNode(.load, lhs_ptr, infix_node);
    const lhs_type = try gz.addUnTok(.typeof, lhs, infix_node);
    const rhs = try expr(mod, scope, .{ .ty = lhs_type }, node_datas[infix_node].rhs);

    const result = try gz.addPlNode(op_inst_tag, infix_node, zir.Inst.Bin{
        .lhs = lhs,
        .rhs = rhs,
    });
    _ = try gz.addBin(.store, lhs_ptr, result);
}

fn boolNot(mod: *Module, scope: *Scope, rl: ResultLoc, node: ast.Node.Index) InnerError!zir.Inst.Ref {
    const tree = scope.tree();
    const node_datas = tree.nodes.items(.data);

    const operand = try expr(mod, scope, .{ .ty = .bool_type }, node_datas[node].lhs);
    const gz = scope.getGenZir();
    const result = try gz.addUnNode(.bool_not, operand, node);
    return rvalue(mod, scope, rl, result, node);
}

fn bitNot(mod: *Module, scope: *Scope, rl: ResultLoc, node: ast.Node.Index) InnerError!zir.Inst.Ref {
    const tree = scope.tree();
    const node_datas = tree.nodes.items(.data);

    const gz = scope.getGenZir();
    const operand = try expr(mod, scope, .none, node_datas[node].lhs);
    const result = try gz.addUnNode(.bit_not, operand, node);
    return rvalue(mod, scope, rl, result, node);
}

fn negation(
    mod: *Module,
    scope: *Scope,
    rl: ResultLoc,
    node: ast.Node.Index,
    tag: zir.Inst.Tag,
) InnerError!zir.Inst.Ref {
    const tree = scope.tree();
    const node_datas = tree.nodes.items(.data);

    const gz = scope.getGenZir();
    const operand = try expr(mod, scope, .none, node_datas[node].lhs);
    const result = try gz.addUnNode(tag, operand, node);
    return rvalue(mod, scope, rl, result, node);
}

fn ptrType(
    mod: *Module,
    scope: *Scope,
    rl: ResultLoc,
    node: ast.Node.Index,
    ptr_info: ast.full.PtrType,
) InnerError!zir.Inst.Ref {
    const tree = scope.tree();
    const gz = scope.getGenZir();

    const elem_type = try typeExpr(mod, scope, ptr_info.ast.child_type);

    const simple = ptr_info.ast.align_node == 0 and
        ptr_info.ast.sentinel == 0 and
        ptr_info.ast.bit_range_start == 0;

    if (simple) {
        const result = try gz.add(.{ .tag = .ptr_type_simple, .data = .{
            .ptr_type_simple = .{
                .is_allowzero = ptr_info.allowzero_token != null,
                .is_mutable = ptr_info.const_token == null,
                .is_volatile = ptr_info.volatile_token != null,
                .size = ptr_info.size,
                .elem_type = elem_type,
            },
        } });
        return rvalue(mod, scope, rl, result, node);
    }

    var sentinel_ref: zir.Inst.Ref = .none;
    var align_ref: zir.Inst.Ref = .none;
    var bit_start_ref: zir.Inst.Ref = .none;
    var bit_end_ref: zir.Inst.Ref = .none;
    var trailing_count: u32 = 0;

    if (ptr_info.ast.sentinel != 0) {
        sentinel_ref = try expr(mod, scope, .{ .ty = elem_type }, ptr_info.ast.sentinel);
        trailing_count += 1;
    }
    if (ptr_info.ast.align_node != 0) {
        align_ref = try expr(mod, scope, .none, ptr_info.ast.align_node);
        trailing_count += 1;
    }
    if (ptr_info.ast.bit_range_start != 0) {
        assert(ptr_info.ast.bit_range_end != 0);
        bit_start_ref = try expr(mod, scope, .none, ptr_info.ast.bit_range_start);
        bit_end_ref = try expr(mod, scope, .none, ptr_info.ast.bit_range_end);
        trailing_count += 2;
    }

    const gpa = gz.zir_code.gpa;
    try gz.instructions.ensureCapacity(gpa, gz.instructions.items.len + 1);
    try gz.zir_code.instructions.ensureCapacity(gpa, gz.zir_code.instructions.len + 1);
    try gz.zir_code.extra.ensureCapacity(gpa, gz.zir_code.extra.items.len +
        @typeInfo(zir.Inst.PtrType).Struct.fields.len + trailing_count);

    const payload_index = gz.zir_code.addExtraAssumeCapacity(zir.Inst.PtrType{ .elem_type = elem_type });
    if (sentinel_ref != .none) {
        gz.zir_code.extra.appendAssumeCapacity(@enumToInt(sentinel_ref));
    }
    if (align_ref != .none) {
        gz.zir_code.extra.appendAssumeCapacity(@enumToInt(align_ref));
    }
    if (bit_start_ref != .none) {
        gz.zir_code.extra.appendAssumeCapacity(@enumToInt(bit_start_ref));
        gz.zir_code.extra.appendAssumeCapacity(@enumToInt(bit_end_ref));
    }

    const new_index = @intCast(zir.Inst.Index, gz.zir_code.instructions.len);
    const result = gz.zir_code.indexToRef(new_index);
    gz.zir_code.instructions.appendAssumeCapacity(.{ .tag = .ptr_type, .data = .{
        .ptr_type = .{
            .flags = .{
                .is_allowzero = ptr_info.allowzero_token != null,
                .is_mutable = ptr_info.const_token == null,
                .is_volatile = ptr_info.volatile_token != null,
                .has_sentinel = sentinel_ref != .none,
                .has_align = align_ref != .none,
                .has_bit_range = bit_start_ref != .none,
            },
            .size = ptr_info.size,
            .payload_index = payload_index,
        },
    } });
    gz.instructions.appendAssumeCapacity(new_index);

    return rvalue(mod, scope, rl, result, node);
}

fn arrayType(mod: *Module, scope: *Scope, rl: ResultLoc, node: ast.Node.Index) !zir.Inst.Ref {
    const tree = scope.tree();
    const node_datas = tree.nodes.items(.data);
    const gz = scope.getGenZir();

    // TODO check for [_]T
    const len = try expr(mod, scope, .{ .ty = .usize_type }, node_datas[node].lhs);
    const elem_type = try typeExpr(mod, scope, node_datas[node].rhs);

    const result = try gz.addBin(.array_type, len, elem_type);
    return rvalue(mod, scope, rl, result, node);
}

fn arrayTypeSentinel(mod: *Module, scope: *Scope, rl: ResultLoc, node: ast.Node.Index) !zir.Inst.Ref {
    const tree = scope.tree();
    const node_datas = tree.nodes.items(.data);
    const extra = tree.extraData(node_datas[node].rhs, ast.Node.ArrayTypeSentinel);
    const gz = scope.getGenZir();

    // TODO check for [_]T
    const len = try expr(mod, scope, .{ .ty = .usize_type }, node_datas[node].lhs);
    const elem_type = try typeExpr(mod, scope, extra.elem_type);
    const sentinel = try expr(mod, scope, .{ .ty = elem_type }, extra.sentinel);

    const result = try gz.addArrayTypeSentinel(len, elem_type, sentinel);
    return rvalue(mod, scope, rl, result, node);
}

fn containerDecl(
    mod: *Module,
    scope: *Scope,
    rl: ResultLoc,
    container_decl: ast.full.ContainerDecl,
) InnerError!zir.Inst.Ref {
    if (true) @panic("TODO update for zir-memory-layout");
    return mod.failTok(scope, container_decl.ast.main_token, "TODO implement container decls", .{});
}

fn errorSetDecl(
    mod: *Module,
    scope: *Scope,
    rl: ResultLoc,
    node: ast.Node.Index,
) InnerError!zir.Inst.Ref {
    if (true) @panic("TODO update for zir-memory-layout");
    const tree = scope.tree();
    const main_tokens = tree.nodes.items(.main_token);
    const token_tags = tree.tokens.items(.tag);

    // Count how many fields there are.
    const error_token = main_tokens[node];
    const count: usize = count: {
        var tok_i = error_token + 2;
        var count: usize = 0;
        while (true) : (tok_i += 1) {
            switch (token_tags[tok_i]) {
                .doc_comment, .comma => {},
                .identifier => count += 1,
                .r_brace => break :count count,
                else => unreachable,
            }
        } else unreachable; // TODO should not need else unreachable here
    };

    const fields = try scope.arena().alloc([]const u8, count);
    {
        var tok_i = error_token + 2;
        var field_i: usize = 0;
        while (true) : (tok_i += 1) {
            switch (token_tags[tok_i]) {
                .doc_comment, .comma => {},
                .identifier => {
                    fields[field_i] = try mod.identifierTokenString(scope, tok_i);
                    field_i += 1;
                },
                .r_brace => break,
                else => unreachable,
            }
        }
    }
    const result = try addZIRInst(mod, scope, src, zir.Inst.ErrorSet, .{ .fields = fields }, .{});
    return rvalue(mod, scope, rl, result);
}

fn orelseCatchExpr(
    mod: *Module,
    scope: *Scope,
    rl: ResultLoc,
    node: ast.Node.Index,
    lhs: ast.Node.Index,
    cond_op: zir.Inst.Tag,
    unwrap_op: zir.Inst.Tag,
    unwrap_code_op: zir.Inst.Tag,
    rhs: ast.Node.Index,
    payload_token: ?ast.TokenIndex,
) InnerError!zir.Inst.Ref {
    const parent_gz = scope.getGenZir();
    const tree = parent_gz.tree();

    var block_scope: Scope.GenZir = .{
        .parent = scope,
        .zir_code = parent_gz.zir_code,
        .force_comptime = parent_gz.force_comptime,
        .instructions = .{},
    };
    setBlockResultLoc(&block_scope, rl);
    defer block_scope.instructions.deinit(mod.gpa);

    // This could be a pointer or value depending on the `operand_rl` parameter.
    // We cannot use `block_scope.break_result_loc` because that has the bare
    // type, whereas this expression has the optional type. Later we make
    // up for this fact by calling rvalue on the else branch.
    block_scope.break_count += 1;

    // TODO handle catch
    const operand_rl: ResultLoc = switch (block_scope.break_result_loc) {
        .ref => .ref,
        .discard, .none, .block_ptr, .inferred_ptr, .bitcasted_ptr => .none,
        .ty => |elem_ty| blk: {
            const wrapped_ty = try block_scope.addUnNode(.optional_type, elem_ty, node);
            break :blk .{ .ty = wrapped_ty };
        },
        .ptr => |ptr_ty| blk: {
            const wrapped_ty = try block_scope.addUnNode(.optional_type_from_ptr_elem, ptr_ty, node);
            break :blk .{ .ty = wrapped_ty };
        },
    };
    const operand = try expr(mod, &block_scope.base, operand_rl, lhs);
    const cond = try block_scope.addUnNode(cond_op, operand, node);
    const condbr = try block_scope.addCondBr(.condbr, node);

    const block = try parent_gz.addBlock(.block, node);
    try parent_gz.instructions.append(mod.gpa, block);
    try block_scope.setBlockBody(block);

    var then_scope: Scope.GenZir = .{
        .parent = scope,
        .zir_code = parent_gz.zir_code,
        .force_comptime = block_scope.force_comptime,
        .instructions = .{},
    };
    defer then_scope.instructions.deinit(mod.gpa);

    var err_val_scope: Scope.LocalVal = undefined;
    const then_sub_scope = blk: {
        const payload = payload_token orelse break :blk &then_scope.base;
        if (mem.eql(u8, tree.tokenSlice(payload), "_")) {
            return mod.failTok(&then_scope.base, payload, "discard of error capture; omit it instead", .{});
        }
        const err_name = try mod.identifierTokenString(scope, payload);
        err_val_scope = .{
            .parent = &then_scope.base,
            .gen_zir = &then_scope,
            .name = err_name,
            .inst = try then_scope.addUnNode(unwrap_code_op, operand, node),
            .src = parent_gz.tokSrcLoc(payload),
        };
        break :blk &err_val_scope.base;
    };

    block_scope.break_count += 1;
    const then_result = try expr(mod, then_sub_scope, block_scope.break_result_loc, rhs);
    // We hold off on the break instructions as well as copying the then/else
    // instructions into place until we know whether to keep store_to_block_ptr
    // instructions or not.

    var else_scope: Scope.GenZir = .{
        .parent = scope,
        .zir_code = parent_gz.zir_code,
        .force_comptime = block_scope.force_comptime,
        .instructions = .{},
    };
    defer else_scope.instructions.deinit(mod.gpa);

    // This could be a pointer or value depending on `unwrap_op`.
    const unwrapped_payload = try else_scope.addUnNode(unwrap_op, operand, node);
    const else_result = switch (rl) {
        .ref => unwrapped_payload,
        else => try rvalue(mod, &else_scope.base, block_scope.break_result_loc, unwrapped_payload, node),
    };

    return finishThenElseBlock(
        mod,
        scope,
        rl,
        node,
        &block_scope,
        &then_scope,
        &else_scope,
        condbr,
        cond,
        node,
        node,
        then_result,
        else_result,
        block,
        block,
        .@"break",
    );
}

fn finishThenElseBlock(
    mod: *Module,
    parent_scope: *Scope,
    rl: ResultLoc,
    node: ast.Node.Index,
    block_scope: *Scope.GenZir,
    then_scope: *Scope.GenZir,
    else_scope: *Scope.GenZir,
    condbr: zir.Inst.Index,
    cond: zir.Inst.Ref,
    then_src: ast.Node.Index,
    else_src: ast.Node.Index,
    then_result: zir.Inst.Ref,
    else_result: zir.Inst.Ref,
    main_block: zir.Inst.Index,
    then_break_block: zir.Inst.Index,
    break_tag: zir.Inst.Tag,
) InnerError!zir.Inst.Ref {
    // We now have enough information to decide whether the result instruction should
    // be communicated via result location pointer or break instructions.
    const strat = rlStrategy(rl, block_scope);
    const wzc = block_scope.zir_code;
    switch (strat.tag) {
        .break_void => {
            if (!wzc.refIsNoReturn(then_result)) {
                _ = try then_scope.addBreak(break_tag, then_break_block, .void_value);
            }
            const elide_else = if (else_result != .none) wzc.refIsNoReturn(else_result) else false;
            if (!elide_else) {
                _ = try else_scope.addBreak(break_tag, main_block, .void_value);
            }
            assert(!strat.elide_store_to_block_ptr_instructions);
            try setCondBrPayload(condbr, cond, then_scope, else_scope);
            return wzc.indexToRef(main_block);
        },
        .break_operand => {
            if (!wzc.refIsNoReturn(then_result)) {
                _ = try then_scope.addBreak(break_tag, then_break_block, then_result);
            }
            if (else_result != .none) {
                if (!wzc.refIsNoReturn(else_result)) {
                    _ = try else_scope.addBreak(break_tag, main_block, else_result);
                }
            } else {
                _ = try else_scope.addBreak(break_tag, main_block, .void_value);
            }
            if (strat.elide_store_to_block_ptr_instructions) {
                try setCondBrPayloadElideBlockStorePtr(condbr, cond, then_scope, else_scope);
            } else {
                try setCondBrPayload(condbr, cond, then_scope, else_scope);
            }
            const block_ref = wzc.indexToRef(main_block);
            switch (rl) {
                .ref => return block_ref,
                else => return rvalue(mod, parent_scope, rl, block_ref, node),
            }
        },
    }
}

/// Return whether the identifier names of two tokens are equal. Resolves @""
/// tokens without allocating.
/// OK in theory it could do it without allocating. This implementation
/// allocates when the @"" form is used.
fn tokenIdentEql(mod: *Module, scope: *Scope, token1: ast.TokenIndex, token2: ast.TokenIndex) !bool {
    const ident_name_1 = try mod.identifierTokenString(scope, token1);
    const ident_name_2 = try mod.identifierTokenString(scope, token2);
    return mem.eql(u8, ident_name_1, ident_name_2);
}

pub fn fieldAccess(
    mod: *Module,
    scope: *Scope,
    rl: ResultLoc,
    node: ast.Node.Index,
) InnerError!zir.Inst.Ref {
    const gz = scope.getGenZir();
    const tree = gz.tree();
    const main_tokens = tree.nodes.items(.main_token);
    const node_datas = tree.nodes.items(.data);
    const object_node = node_datas[node].lhs;
    const dot_token = main_tokens[node];
    const field_ident = dot_token + 1;
    const string_bytes = &gz.zir_code.string_bytes;
    const str_index = @intCast(u32, string_bytes.items.len);
    try mod.appendIdentStr(scope, field_ident, string_bytes);
    try string_bytes.append(mod.gpa, 0);
    switch (rl) {
        .ref => return gz.addPlNode(.field_ptr, node, zir.Inst.Field{
            .lhs = try expr(mod, scope, .ref, object_node),
            .field_name_start = str_index,
        }),
        else => return rvalue(mod, scope, rl, try gz.addPlNode(.field_val, node, zir.Inst.Field{
            .lhs = try expr(mod, scope, .none, object_node),
            .field_name_start = str_index,
        }), node),
    }
}

fn arrayAccess(
    mod: *Module,
    scope: *Scope,
    rl: ResultLoc,
    node: ast.Node.Index,
) InnerError!zir.Inst.Ref {
    const gz = scope.getGenZir();
    const tree = gz.tree();
    const main_tokens = tree.nodes.items(.main_token);
    const node_datas = tree.nodes.items(.data);
    switch (rl) {
        .ref => return gz.addBin(
            .elem_ptr,
            try expr(mod, scope, .ref, node_datas[node].lhs),
            try expr(mod, scope, .{ .ty = .usize_type }, node_datas[node].rhs),
        ),
        else => return rvalue(mod, scope, rl, try gz.addBin(
            .elem_val,
            try expr(mod, scope, .none, node_datas[node].lhs),
            try expr(mod, scope, .{ .ty = .usize_type }, node_datas[node].rhs),
        ), node),
    }
}

fn simpleBinOp(
    mod: *Module,
    scope: *Scope,
    rl: ResultLoc,
    node: ast.Node.Index,
    op_inst_tag: zir.Inst.Tag,
) InnerError!zir.Inst.Ref {
    const gz = scope.getGenZir();
    const tree = gz.tree();
    const node_datas = tree.nodes.items(.data);

    const result = try gz.addPlNode(op_inst_tag, node, zir.Inst.Bin{
        .lhs = try expr(mod, scope, .none, node_datas[node].lhs),
        .rhs = try expr(mod, scope, .none, node_datas[node].rhs),
    });
    return rvalue(mod, scope, rl, result, node);
}

fn boolBinOp(
    mod: *Module,
    scope: *Scope,
    rl: ResultLoc,
    node: ast.Node.Index,
    zir_tag: zir.Inst.Tag,
) InnerError!zir.Inst.Ref {
    const gz = scope.getGenZir();
    const node_datas = gz.tree().nodes.items(.data);

    const lhs = try expr(mod, scope, .{ .ty = .bool_type }, node_datas[node].lhs);
    const bool_br = try gz.addBoolBr(zir_tag, lhs);

    var rhs_scope: Scope.GenZir = .{
        .parent = scope,
        .zir_code = gz.zir_code,
        .force_comptime = gz.force_comptime,
    };
    defer rhs_scope.instructions.deinit(mod.gpa);
    const rhs = try expr(mod, &rhs_scope.base, .{ .ty = .bool_type }, node_datas[node].rhs);
    _ = try rhs_scope.addBreak(.break_inline, bool_br, rhs);
    try rhs_scope.setBoolBrBody(bool_br);

    const block_ref = gz.zir_code.indexToRef(bool_br);
    return rvalue(mod, scope, rl, block_ref, node);
}

fn ifExpr(
    mod: *Module,
    scope: *Scope,
    rl: ResultLoc,
    node: ast.Node.Index,
    if_full: ast.full.If,
) InnerError!zir.Inst.Ref {
    const parent_gz = scope.getGenZir();
    var block_scope: Scope.GenZir = .{
        .parent = scope,
        .zir_code = parent_gz.zir_code,
        .force_comptime = parent_gz.force_comptime,
        .instructions = .{},
    };
    setBlockResultLoc(&block_scope, rl);
    defer block_scope.instructions.deinit(mod.gpa);

    const cond = c: {
        // TODO https://github.com/ziglang/zig/issues/7929
        if (if_full.error_token) |error_token| {
            return mod.failTok(scope, error_token, "TODO implement if error union", .{});
        } else if (if_full.payload_token) |payload_token| {
            return mod.failTok(scope, payload_token, "TODO implement if optional", .{});
        } else {
            break :c try expr(mod, &block_scope.base, .{ .ty = .bool_type }, if_full.ast.cond_expr);
        }
    };

    const condbr = try block_scope.addCondBr(.condbr, node);

    const block = try parent_gz.addBlock(.block, node);
    try parent_gz.instructions.append(mod.gpa, block);
    try block_scope.setBlockBody(block);

    var then_scope: Scope.GenZir = .{
        .parent = scope,
        .zir_code = parent_gz.zir_code,
        .force_comptime = block_scope.force_comptime,
        .instructions = .{},
    };
    defer then_scope.instructions.deinit(mod.gpa);

    // declare payload to the then_scope
    const then_sub_scope = &then_scope.base;

    block_scope.break_count += 1;
    const then_result = try expr(mod, then_sub_scope, block_scope.break_result_loc, if_full.ast.then_expr);
    // We hold off on the break instructions as well as copying the then/else
    // instructions into place until we know whether to keep store_to_block_ptr
    // instructions or not.

    var else_scope: Scope.GenZir = .{
        .parent = scope,
        .zir_code = parent_gz.zir_code,
        .force_comptime = block_scope.force_comptime,
        .instructions = .{},
    };
    defer else_scope.instructions.deinit(mod.gpa);

    const else_node = if_full.ast.else_expr;
    const else_info: struct {
        src: ast.Node.Index,
        result: zir.Inst.Ref,
    } = if (else_node != 0) blk: {
        block_scope.break_count += 1;
        const sub_scope = &else_scope.base;
        break :blk .{
            .src = else_node,
            .result = try expr(mod, sub_scope, block_scope.break_result_loc, else_node),
        };
    } else .{
        .src = if_full.ast.then_expr,
        .result = .none,
    };

    return finishThenElseBlock(
        mod,
        scope,
        rl,
        node,
        &block_scope,
        &then_scope,
        &else_scope,
        condbr,
        cond,
        if_full.ast.then_expr,
        else_info.src,
        then_result,
        else_info.result,
        block,
        block,
        .@"break",
    );
}

fn setCondBrPayload(
    condbr: zir.Inst.Index,
    cond: zir.Inst.Ref,
    then_scope: *Scope.GenZir,
    else_scope: *Scope.GenZir,
) !void {
    const wzc = then_scope.zir_code;

    try wzc.extra.ensureCapacity(wzc.gpa, wzc.extra.items.len +
        @typeInfo(zir.Inst.CondBr).Struct.fields.len +
        then_scope.instructions.items.len + else_scope.instructions.items.len);

    const zir_datas = wzc.instructions.items(.data);
    zir_datas[condbr].pl_node.payload_index = wzc.addExtraAssumeCapacity(zir.Inst.CondBr{
        .condition = cond,
        .then_body_len = @intCast(u32, then_scope.instructions.items.len),
        .else_body_len = @intCast(u32, else_scope.instructions.items.len),
    });
    wzc.extra.appendSliceAssumeCapacity(then_scope.instructions.items);
    wzc.extra.appendSliceAssumeCapacity(else_scope.instructions.items);
}

/// If `elide_block_store_ptr` is set, expects to find exactly 1 .store_to_block_ptr instruction.
fn setCondBrPayloadElideBlockStorePtr(
    condbr: zir.Inst.Index,
    cond: zir.Inst.Ref,
    then_scope: *Scope.GenZir,
    else_scope: *Scope.GenZir,
) !void {
    const wzc = then_scope.zir_code;

    try wzc.extra.ensureCapacity(wzc.gpa, wzc.extra.items.len +
        @typeInfo(zir.Inst.CondBr).Struct.fields.len +
        then_scope.instructions.items.len + else_scope.instructions.items.len - 2);

    const zir_datas = wzc.instructions.items(.data);
    zir_datas[condbr].pl_node.payload_index = wzc.addExtraAssumeCapacity(zir.Inst.CondBr{
        .condition = cond,
        .then_body_len = @intCast(u32, then_scope.instructions.items.len - 1),
        .else_body_len = @intCast(u32, else_scope.instructions.items.len - 1),
    });

    const zir_tags = wzc.instructions.items(.tag);
    for ([_]*Scope.GenZir{ then_scope, else_scope }) |scope| {
        for (scope.instructions.items) |src_inst| {
            if (zir_tags[src_inst] != .store_to_block_ptr) {
                wzc.extra.appendAssumeCapacity(src_inst);
            }
        }
    }
}

fn whileExpr(
    mod: *Module,
    scope: *Scope,
    rl: ResultLoc,
    node: ast.Node.Index,
    while_full: ast.full.While,
) InnerError!zir.Inst.Ref {
    if (while_full.label_token) |label_token| {
        try checkLabelRedefinition(mod, scope, label_token);
    }
    const parent_gz = scope.getGenZir();
    const is_inline = parent_gz.force_comptime or while_full.inline_token != null;
    const loop_tag: zir.Inst.Tag = if (is_inline) .block_inline else .loop;
    const loop_block = try parent_gz.addBlock(loop_tag, node);
    try parent_gz.instructions.append(mod.gpa, loop_block);

    var loop_scope: Scope.GenZir = .{
        .parent = scope,
        .zir_code = parent_gz.zir_code,
        .force_comptime = parent_gz.force_comptime,
        .instructions = .{},
    };
    setBlockResultLoc(&loop_scope, rl);
    defer loop_scope.instructions.deinit(mod.gpa);

    var continue_scope: Scope.GenZir = .{
        .parent = &loop_scope.base,
        .zir_code = parent_gz.zir_code,
        .force_comptime = loop_scope.force_comptime,
        .instructions = .{},
    };
    defer continue_scope.instructions.deinit(mod.gpa);

    const cond = c: {
        // TODO https://github.com/ziglang/zig/issues/7929
        if (while_full.error_token) |error_token| {
            return mod.failTok(scope, error_token, "TODO implement while error union", .{});
        } else if (while_full.payload_token) |payload_token| {
            return mod.failTok(scope, payload_token, "TODO implement while optional", .{});
        } else {
            const bool_type_rl: ResultLoc = .{ .ty = .bool_type };
            break :c try expr(mod, &continue_scope.base, bool_type_rl, while_full.ast.cond_expr);
        }
    };

    const condbr_tag: zir.Inst.Tag = if (is_inline) .condbr_inline else .condbr;
    const condbr = try continue_scope.addCondBr(condbr_tag, node);
    const block_tag: zir.Inst.Tag = if (is_inline) .block_inline else .block;
    const cond_block = try loop_scope.addBlock(block_tag, node);
    try loop_scope.instructions.append(mod.gpa, cond_block);
    try continue_scope.setBlockBody(cond_block);

    // TODO avoid emitting the continue expr when there
    // are no jumps to it. This happens when the last statement of a while body is noreturn
    // and there are no `continue` statements.
    if (while_full.ast.cont_expr != 0) {
        _ = try expr(mod, &loop_scope.base, .{ .ty = .void_type }, while_full.ast.cont_expr);
    }
    const repeat_tag: zir.Inst.Tag = if (is_inline) .repeat_inline else .repeat;
    _ = try loop_scope.addNode(repeat_tag, node);

    try loop_scope.setBlockBody(loop_block);
    loop_scope.break_block = loop_block;
    loop_scope.continue_block = cond_block;
    if (while_full.label_token) |label_token| {
        loop_scope.label = @as(?Scope.GenZir.Label, Scope.GenZir.Label{
            .token = label_token,
            .block_inst = loop_block,
        });
    }

    var then_scope: Scope.GenZir = .{
        .parent = &continue_scope.base,
        .zir_code = parent_gz.zir_code,
        .force_comptime = continue_scope.force_comptime,
        .instructions = .{},
    };
    defer then_scope.instructions.deinit(mod.gpa);

    const then_sub_scope = &then_scope.base;

    loop_scope.break_count += 1;
    const then_result = try expr(mod, then_sub_scope, loop_scope.break_result_loc, while_full.ast.then_expr);

    var else_scope: Scope.GenZir = .{
        .parent = &continue_scope.base,
        .zir_code = parent_gz.zir_code,
        .force_comptime = continue_scope.force_comptime,
        .instructions = .{},
    };
    defer else_scope.instructions.deinit(mod.gpa);

    const else_node = while_full.ast.else_expr;
    const else_info: struct {
        src: ast.Node.Index,
        result: zir.Inst.Ref,
    } = if (else_node != 0) blk: {
        loop_scope.break_count += 1;
        const sub_scope = &else_scope.base;
        break :blk .{
            .src = else_node,
            .result = try expr(mod, sub_scope, loop_scope.break_result_loc, else_node),
        };
    } else .{
        .src = while_full.ast.then_expr,
        .result = .none,
    };

    if (loop_scope.label) |some| {
        if (!some.used) {
            return mod.failTok(scope, some.token, "unused while loop label", .{});
        }
    }
    const break_tag: zir.Inst.Tag = if (is_inline) .break_inline else .@"break";
    return finishThenElseBlock(
        mod,
        scope,
        rl,
        node,
        &loop_scope,
        &then_scope,
        &else_scope,
        condbr,
        cond,
        while_full.ast.then_expr,
        else_info.src,
        then_result,
        else_info.result,
        loop_block,
        cond_block,
        break_tag,
    );
}

fn forExpr(
    mod: *Module,
    scope: *Scope,
    rl: ResultLoc,
    node: ast.Node.Index,
    for_full: ast.full.While,
) InnerError!zir.Inst.Ref {
    if (for_full.label_token) |label_token| {
        try checkLabelRedefinition(mod, scope, label_token);
    }
    // Set up variables and constants.
    const parent_gz = scope.getGenZir();
    const is_inline = parent_gz.force_comptime or for_full.inline_token != null;
    const tree = parent_gz.tree();
    const token_tags = tree.tokens.items(.tag);

    const array_ptr = try expr(mod, scope, .ref, for_full.ast.cond_expr);
    const len = try parent_gz.addUnNode(.indexable_ptr_len, array_ptr, for_full.ast.cond_expr);

    const index_ptr = blk: {
        const index_ptr = try parent_gz.addUnNode(.alloc, .usize_type, node);
        // initialize to zero
        _ = try parent_gz.addBin(.store, index_ptr, .zero_usize);
        break :blk index_ptr;
    };

    const loop_tag: zir.Inst.Tag = if (is_inline) .block_inline else .loop;
    const loop_block = try parent_gz.addBlock(loop_tag, node);
    try parent_gz.instructions.append(mod.gpa, loop_block);

    var loop_scope: Scope.GenZir = .{
        .parent = scope,
        .zir_code = parent_gz.zir_code,
        .force_comptime = parent_gz.force_comptime,
        .instructions = .{},
    };
    setBlockResultLoc(&loop_scope, rl);
    defer loop_scope.instructions.deinit(mod.gpa);

    var cond_scope: Scope.GenZir = .{
        .parent = &loop_scope.base,
        .zir_code = parent_gz.zir_code,
        .force_comptime = loop_scope.force_comptime,
        .instructions = .{},
    };
    defer cond_scope.instructions.deinit(mod.gpa);

    // check condition i < array_expr.len
    const index = try cond_scope.addUnNode(.load, index_ptr, for_full.ast.cond_expr);
    const cond = try cond_scope.addPlNode(.cmp_lt, for_full.ast.cond_expr, zir.Inst.Bin{
        .lhs = index,
        .rhs = len,
    });

    const condbr_tag: zir.Inst.Tag = if (is_inline) .condbr_inline else .condbr;
    const condbr = try cond_scope.addCondBr(condbr_tag, node);
    const block_tag: zir.Inst.Tag = if (is_inline) .block_inline else .block;
    const cond_block = try loop_scope.addBlock(block_tag, node);
    try loop_scope.instructions.append(mod.gpa, cond_block);
    try cond_scope.setBlockBody(cond_block);

    // Increment the index variable.
    const index_2 = try loop_scope.addUnNode(.load, index_ptr, for_full.ast.cond_expr);
    const index_plus_one = try loop_scope.addPlNode(.add, node, zir.Inst.Bin{
        .lhs = index_2,
        .rhs = .one_usize,
    });
    _ = try loop_scope.addBin(.store, index_ptr, index_plus_one);
    const repeat_tag: zir.Inst.Tag = if (is_inline) .repeat_inline else .repeat;
    _ = try loop_scope.addNode(repeat_tag, node);

    try loop_scope.setBlockBody(loop_block);
    loop_scope.break_block = loop_block;
    loop_scope.continue_block = cond_block;
    if (for_full.label_token) |label_token| {
        loop_scope.label = @as(?Scope.GenZir.Label, Scope.GenZir.Label{
            .token = label_token,
            .block_inst = loop_block,
        });
    }

    var then_scope: Scope.GenZir = .{
        .parent = &cond_scope.base,
        .zir_code = parent_gz.zir_code,
        .force_comptime = cond_scope.force_comptime,
        .instructions = .{},
    };
    defer then_scope.instructions.deinit(mod.gpa);

    var index_scope: Scope.LocalPtr = undefined;
    const then_sub_scope = blk: {
        const payload_token = for_full.payload_token.?;
        const ident = if (token_tags[payload_token] == .asterisk)
            payload_token + 1
        else
            payload_token;
        const is_ptr = ident != payload_token;
        const value_name = tree.tokenSlice(ident);
        if (!mem.eql(u8, value_name, "_")) {
            return mod.failNode(&then_scope.base, ident, "TODO implement for loop value payload", .{});
        } else if (is_ptr) {
            return mod.failTok(&then_scope.base, payload_token, "pointer modifier invalid on discard", .{});
        }

        const index_token = if (token_tags[ident + 1] == .comma)
            ident + 2
        else
            break :blk &then_scope.base;
        if (mem.eql(u8, tree.tokenSlice(index_token), "_")) {
            return mod.failTok(&then_scope.base, index_token, "discard of index capture; omit it instead", .{});
        }
        const index_name = try mod.identifierTokenString(&then_scope.base, index_token);
        index_scope = .{
            .parent = &then_scope.base,
            .gen_zir = &then_scope,
            .name = index_name,
            .ptr = index_ptr,
            .src = parent_gz.tokSrcLoc(index_token),
        };
        break :blk &index_scope.base;
    };

    loop_scope.break_count += 1;
    const then_result = try expr(mod, then_sub_scope, loop_scope.break_result_loc, for_full.ast.then_expr);

    var else_scope: Scope.GenZir = .{
        .parent = &cond_scope.base,
        .zir_code = parent_gz.zir_code,
        .force_comptime = cond_scope.force_comptime,
        .instructions = .{},
    };
    defer else_scope.instructions.deinit(mod.gpa);

    const else_node = for_full.ast.else_expr;
    const else_info: struct {
        src: ast.Node.Index,
        result: zir.Inst.Ref,
    } = if (else_node != 0) blk: {
        loop_scope.break_count += 1;
        const sub_scope = &else_scope.base;
        break :blk .{
            .src = else_node,
            .result = try expr(mod, sub_scope, loop_scope.break_result_loc, else_node),
        };
    } else .{
        .src = for_full.ast.then_expr,
        .result = .none,
    };

    if (loop_scope.label) |some| {
        if (!some.used) {
            return mod.failTok(scope, some.token, "unused for loop label", .{});
        }
    }
    const break_tag: zir.Inst.Tag = if (is_inline) .break_inline else .@"break";
    return finishThenElseBlock(
        mod,
        scope,
        rl,
        node,
        &loop_scope,
        &then_scope,
        &else_scope,
        condbr,
        cond,
        for_full.ast.then_expr,
        else_info.src,
        then_result,
        else_info.result,
        loop_block,
        cond_block,
        break_tag,
    );
}

fn getRangeNode(
    node_tags: []const ast.Node.Tag,
    node_datas: []const ast.Node.Data,
    start_node: ast.Node.Index,
) ?ast.Node.Index {
    var node = start_node;
    while (true) {
        switch (node_tags[node]) {
            .switch_range => return node,
            .grouped_expression => node = node_datas[node].lhs,
            else => return null,
        }
    }
}

fn switchExpr(
    mod: *Module,
    scope: *Scope,
    rl: ResultLoc,
    switch_node: ast.Node.Index,
) InnerError!zir.Inst.Ref {
    if (true) @panic("TODO update for zir-memory-layout");
    const parent_gz = scope.getGenZir();
    const tree = parent_gz.tree();
    const node_datas = tree.nodes.items(.data);
    const main_tokens = tree.nodes.items(.main_token);
    const token_tags = tree.tokens.items(.tag);
    const node_tags = tree.nodes.items(.tag);

    const switch_token = main_tokens[switch_node];
    const target_node = node_datas[switch_node].lhs;
    const extra = tree.extraData(node_datas[switch_node].rhs, ast.Node.SubRange);
    const case_nodes = tree.extra_data[extra.start..extra.end];

    const switch_src = token_starts[switch_token];

    var block_scope: Scope.GenZir = .{
        .parent = scope,
        .decl = scope.ownerDecl().?,
        .arena = scope.arena(),
        .force_comptime = parent_gz.force_comptime,
        .instructions = .{},
    };
    setBlockResultLoc(&block_scope, rl);
    defer block_scope.instructions.deinit(mod.gpa);

    var items = std.ArrayList(zir.Inst.Ref).init(mod.gpa);
    defer items.deinit();

    // First we gather all the switch items and check else/'_' prongs.
    var else_src: ?usize = null;
    var underscore_src: ?usize = null;
    var first_range: ?*zir.Inst = null;
    var simple_case_count: usize = 0;
    var any_payload_is_ref = false;
    for (case_nodes) |case_node| {
        const case = switch (node_tags[case_node]) {
            .switch_case_one => tree.switchCaseOne(case_node),
            .switch_case => tree.switchCase(case_node),
            else => unreachable,
        };
        if (case.payload_token) |payload_token| {
            if (token_tags[payload_token] == .asterisk) {
                any_payload_is_ref = true;
            }
        }
        // Check for else/_ prong, those are handled last.
        if (case.ast.values.len == 0) {
            const case_src = token_starts[case.ast.arrow_token - 1];
            if (else_src) |src| {
                const msg = msg: {
                    const msg = try mod.errMsg(
                        scope,
                        case_src,
                        "multiple else prongs in switch expression",
                        .{},
                    );
                    errdefer msg.destroy(mod.gpa);
                    try mod.errNote(scope, src, msg, "previous else prong is here", .{});
                    break :msg msg;
                };
                return mod.failWithOwnedErrorMsg(scope, msg);
            }
            else_src = case_src;
            continue;
        } else if (case.ast.values.len == 1 and
            node_tags[case.ast.values[0]] == .identifier and
            mem.eql(u8, tree.tokenSlice(main_tokens[case.ast.values[0]]), "_"))
        {
            const case_src = token_starts[case.ast.arrow_token - 1];
            if (underscore_src) |src| {
                const msg = msg: {
                    const msg = try mod.errMsg(
                        scope,
                        case_src,
                        "multiple '_' prongs in switch expression",
                        .{},
                    );
                    errdefer msg.destroy(mod.gpa);
                    try mod.errNote(scope, src, msg, "previous '_' prong is here", .{});
                    break :msg msg;
                };
                return mod.failWithOwnedErrorMsg(scope, msg);
            }
            underscore_src = case_src;
            continue;
        }

        if (else_src) |some_else| {
            if (underscore_src) |some_underscore| {
                const msg = msg: {
                    const msg = try mod.errMsg(
                        scope,
                        switch_src,
                        "else and '_' prong in switch expression",
                        .{},
                    );
                    errdefer msg.destroy(mod.gpa);
                    try mod.errNote(scope, some_else, msg, "else prong is here", .{});
                    try mod.errNote(scope, some_underscore, msg, "'_' prong is here", .{});
                    break :msg msg;
                };
                return mod.failWithOwnedErrorMsg(scope, msg);
            }
        }

        if (case.ast.values.len == 1 and
            getRangeNode(node_tags, node_datas, case.ast.values[0]) == null)
        {
            simple_case_count += 1;
        }

        // Generate all the switch items as comptime expressions.
        for (case.ast.values) |item| {
            if (getRangeNode(node_tags, node_datas, item)) |range| {
                const start = try comptimeExpr(mod, &block_scope.base, .none, node_datas[range].lhs);
                const end = try comptimeExpr(mod, &block_scope.base, .none, node_datas[range].rhs);
                const range_src = token_starts[main_tokens[range]];
                const range_inst = try addZIRBinOp(mod, &block_scope.base, range_src, .switch_range, start, end);
                try items.append(range_inst);
            } else {
                const item_inst = try comptimeExpr(mod, &block_scope.base, .none, item);
                try items.append(item_inst);
            }
        }
    }

    var special_prong: zir.Inst.SwitchBr.SpecialProng = .none;
    if (else_src != null) special_prong = .@"else";
    if (underscore_src != null) special_prong = .underscore;
    var cases = try block_scope.arena.alloc(zir.Inst.SwitchBr.Case, simple_case_count);

    const rl_and_tag: struct { rl: ResultLoc, tag: zir.Inst.Tag } = if (any_payload_is_ref) .{
        .rl = .ref,
        .tag = .switchbr_ref,
    } else .{
        .rl = .none,
        .tag = .switchbr,
    };
    const target = try expr(mod, &block_scope.base, rl_and_tag.rl, target_node);
    const switch_inst = try addZirInstT(mod, &block_scope.base, switch_src, zir.Inst.SwitchBr, rl_and_tag.tag, .{
        .target = target,
        .cases = cases,
        .items = try block_scope.arena.dupe(zir.Inst.Ref, items.items),
        .else_body = undefined, // populated below
        .range = first_range,
        .special_prong = special_prong,
    });
    const block = try addZIRInstBlock(mod, scope, switch_src, .block, .{
        .instructions = try block_scope.arena.dupe(zir.Inst.Ref, block_scope.instructions.items),
    });

    var case_scope: Scope.GenZir = .{
        .parent = scope,
        .decl = block_scope.decl,
        .arena = block_scope.arena,
        .force_comptime = block_scope.force_comptime,
        .instructions = .{},
    };
    defer case_scope.instructions.deinit(mod.gpa);

    var else_scope: Scope.GenZir = .{
        .parent = scope,
        .decl = case_scope.decl,
        .arena = case_scope.arena,
        .force_comptime = case_scope.force_comptime,
        .instructions = .{},
    };
    defer else_scope.instructions.deinit(mod.gpa);

    // Now generate all but the special cases.
    var special_case: ?ast.full.SwitchCase = null;
    var items_index: usize = 0;
    var case_index: usize = 0;
    for (case_nodes) |case_node| {
        const case = switch (node_tags[case_node]) {
            .switch_case_one => tree.switchCaseOne(case_node),
            .switch_case => tree.switchCase(case_node),
            else => unreachable,
        };
        const case_src = token_starts[main_tokens[case_node]];
        case_scope.instructions.shrinkRetainingCapacity(0);

        // Check for else/_ prong, those are handled last.
        if (case.ast.values.len == 0) {
            special_case = case;
            continue;
        } else if (case.ast.values.len == 1 and
            node_tags[case.ast.values[0]] == .identifier and
            mem.eql(u8, tree.tokenSlice(main_tokens[case.ast.values[0]]), "_"))
        {
            special_case = case;
            continue;
        }

        // If this is a simple one item prong then it is handled by the switchbr.
        if (case.ast.values.len == 1 and
            getRangeNode(node_tags, node_datas, case.ast.values[0]) == null)
        {
            const item = items.items[items_index];
            items_index += 1;
            try switchCaseExpr(mod, &case_scope.base, block_scope.break_result_loc, block, case, target);

            cases[case_index] = .{
                .item = item,
                .body = .{ .instructions = try scope.arena().dupe(zir.Inst.Ref, case_scope.instructions.items) },
            };
            case_index += 1;
            continue;
        }

        // Check if the target matches any of the items.
        // 1, 2, 3..6 will result in
        // target == 1 or target == 2 or (target >= 3 and target <= 6)
        // TODO handle multiple items as switch prongs rather than along with ranges.
        var any_ok: ?*zir.Inst = null;
        for (case.ast.values) |item| {
            if (getRangeNode(node_tags, node_datas, item)) |range| {
                const range_src = token_starts[main_tokens[range]];
                const range_inst = items.items[items_index].castTag(.switch_range).?;
                items_index += 1;

                // target >= start and target <= end
                const range_start_ok = try addZIRBinOp(mod, &else_scope.base, range_src, .cmp_gte, target, range_inst.positionals.lhs);
                const range_end_ok = try addZIRBinOp(mod, &else_scope.base, range_src, .cmp_lte, target, range_inst.positionals.rhs);
                const range_ok = try addZIRBinOp(mod, &else_scope.base, range_src, .bool_and, range_start_ok, range_end_ok);

                if (any_ok) |some| {
                    any_ok = try addZIRBinOp(mod, &else_scope.base, range_src, .bool_or, some, range_ok);
                } else {
                    any_ok = range_ok;
                }
                continue;
            }

            const item_inst = items.items[items_index];
            items_index += 1;
            const cpm_ok = try addZIRBinOp(mod, &else_scope.base, item_inst.src, .cmp_eq, target, item_inst);

            if (any_ok) |some| {
                any_ok = try addZIRBinOp(mod, &else_scope.base, item_inst.src, .bool_or, some, cpm_ok);
            } else {
                any_ok = cpm_ok;
            }
        }

        const condbr = try addZIRInstSpecial(mod, &case_scope.base, case_src, zir.Inst.CondBr, .{
            .condition = any_ok.?,
            .then_body = undefined, // populated below
            .else_body = undefined, // populated below
        }, .{});
        const cond_block = try addZIRInstBlock(mod, &else_scope.base, case_src, .block, .{
            .instructions = try scope.arena().dupe(zir.Inst.Ref, case_scope.instructions.items),
        });

        // reset cond_scope for then_body
        case_scope.instructions.items.len = 0;
        try switchCaseExpr(mod, &case_scope.base, block_scope.break_result_loc, block, case, target);
        condbr.positionals.then_body = .{
            .instructions = try scope.arena().dupe(zir.Inst.Ref, case_scope.instructions.items),
        };

        // reset cond_scope for else_body
        case_scope.instructions.items.len = 0;
        _ = try addZIRInst(mod, &case_scope.base, case_src, zir.Inst.BreakVoid, .{
            .block = cond_block,
        }, .{});
        condbr.positionals.else_body = .{
            .instructions = try scope.arena().dupe(zir.Inst.Ref, case_scope.instructions.items),
        };
    }

    // Finally generate else block or a break.
    if (special_case) |case| {
        try switchCaseExpr(mod, &else_scope.base, block_scope.break_result_loc, block, case, target);
    } else {
        // Not handling all possible cases is a compile error.
        _ = try addZIRNoOp(mod, &else_scope.base, switch_src, .unreachable_unsafe);
    }
    switch_inst.positionals.else_body = .{
        .instructions = try block_scope.arena.dupe(zir.Inst.Ref, else_scope.instructions.items),
    };

    return &block.base;
}

fn switchCaseExpr(
    mod: *Module,
    scope: *Scope,
    rl: ResultLoc,
    block: *zir.Inst.Block,
    case: ast.full.SwitchCase,
    target: zir.Inst.Ref,
) !void {
    const tree = scope.tree();
    const node_datas = tree.nodes.items(.data);
    const main_tokens = tree.nodes.items(.main_token);
    const token_tags = tree.tokens.items(.tag);

    const case_src = token_starts[case.ast.arrow_token];
    const sub_scope = blk: {
        const payload_token = case.payload_token orelse break :blk scope;
        const ident = if (token_tags[payload_token] == .asterisk)
            payload_token + 1
        else
            payload_token;
        const is_ptr = ident != payload_token;
        const value_name = tree.tokenSlice(ident);
        if (mem.eql(u8, value_name, "_")) {
            if (is_ptr) {
                return mod.failTok(scope, payload_token, "pointer modifier invalid on discard", .{});
            }
            break :blk scope;
        }
        return mod.failTok(scope, ident, "TODO implement switch value payload", .{});
    };

    const case_body = try expr(mod, sub_scope, rl, case.ast.target_expr);
    if (!case_body.tag.isNoReturn()) {
        _ = try addZIRInst(mod, sub_scope, case_src, zir.Inst.Break, .{
            .block = block,
            .operand = case_body,
        }, .{});
    }
}

fn ret(mod: *Module, scope: *Scope, node: ast.Node.Index) InnerError!zir.Inst.Ref {
    const tree = scope.tree();
    const node_datas = tree.nodes.items(.data);
    const main_tokens = tree.nodes.items(.main_token);

    const operand_node = node_datas[node].lhs;
    const gz = scope.getGenZir();
    const operand: zir.Inst.Ref = if (operand_node != 0) operand: {
        const rl: ResultLoc = if (nodeMayNeedMemoryLocation(scope, operand_node)) .{
            .ptr = try gz.addNode(.ret_ptr, node),
        } else .{
            .ty = try gz.addNode(.ret_type, node),
        };
        break :operand try expr(mod, scope, rl, operand_node);
    } else .void_value;
    _ = try gz.addUnNode(.ret_node, operand, node);
    return zir.Inst.Ref.unreachable_value;
}

fn identifier(
    mod: *Module,
    scope: *Scope,
    rl: ResultLoc,
    ident: ast.Node.Index,
) InnerError!zir.Inst.Ref {
    const tracy = trace(@src());
    defer tracy.end();

    const tree = scope.tree();
    const main_tokens = tree.nodes.items(.main_token);

    const gz = scope.getGenZir();

    const ident_token = main_tokens[ident];
    const ident_name = try mod.identifierTokenString(scope, ident_token);
    if (mem.eql(u8, ident_name, "_")) {
        return mod.failNode(scope, ident, "TODO implement '_' identifier", .{});
    }

    if (simple_types.get(ident_name)) |zir_const_ref| {
        return rvalue(mod, scope, rl, zir_const_ref, ident);
    }

    if (ident_name.len >= 2) integer: {
        const first_c = ident_name[0];
        if (first_c == 'i' or first_c == 'u') {
            const signedness: std.builtin.Signedness = switch (first_c == 'i') {
                true => .signed,
                false => .unsigned,
            };
            const bit_count = std.fmt.parseInt(u16, ident_name[1..], 10) catch |err| switch (err) {
                error.Overflow => return mod.failNode(
                    scope,
                    ident,
                    "primitive integer type '{s}' exceeds maximum bit width of 65535",
                    .{ident_name},
                ),
                error.InvalidCharacter => break :integer,
            };
            const result = try gz.add(.{
                .tag = .int_type,
                .data = .{ .int_type = .{
                    .src_node = gz.zir_code.decl.nodeIndexToRelative(ident),
                    .signedness = signedness,
                    .bit_count = bit_count,
                } },
            });
            return rvalue(mod, scope, rl, result, ident);
        }
    }

    // Local variables, including function parameters.
    {
        var s = scope;
        while (true) switch (s.tag) {
            .local_val => {
                const local_val = s.cast(Scope.LocalVal).?;
                if (mem.eql(u8, local_val.name, ident_name)) {
                    return rvalue(mod, scope, rl, local_val.inst, ident);
                }
                s = local_val.parent;
            },
            .local_ptr => {
                const local_ptr = s.cast(Scope.LocalPtr).?;
                if (mem.eql(u8, local_ptr.name, ident_name)) {
                    if (rl == .ref) return local_ptr.ptr;
                    const loaded = try gz.addUnNode(.load, local_ptr.ptr, ident);
                    return rvalue(mod, scope, rl, loaded, ident);
                }
                s = local_ptr.parent;
            },
            .gen_zir => s = s.cast(Scope.GenZir).?.parent,
            else => break,
        };
    }

    const gop = try gz.zir_code.decl_map.getOrPut(mod.gpa, ident_name);
    if (!gop.found_existing) {
        const decl = mod.lookupDeclName(scope, ident_name) orelse
            return mod.failNode(scope, ident, "use of undeclared identifier '{s}'", .{ident_name});
        try gz.zir_code.decls.append(mod.gpa, decl);
    }
    const decl_index = @intCast(u32, gop.index);
    switch (rl) {
        .ref => return gz.addDecl(.decl_ref, decl_index, ident),
        else => return rvalue(mod, scope, rl, try gz.addDecl(.decl_val, decl_index, ident), ident),
    }
}

fn stringLiteral(
    mod: *Module,
    scope: *Scope,
    rl: ResultLoc,
    node: ast.Node.Index,
) InnerError!zir.Inst.Ref {
    const tree = scope.tree();
    const main_tokens = tree.nodes.items(.main_token);
    const gz = scope.getGenZir();
    const string_bytes = &gz.zir_code.string_bytes;
    const str_index = string_bytes.items.len;
    const str_lit_token = main_tokens[node];
    const token_bytes = tree.tokenSlice(str_lit_token);
    try mod.parseStrLit(scope, str_lit_token, string_bytes, token_bytes, 0);
    const str_len = string_bytes.items.len - str_index;
    const result = try gz.add(.{
        .tag = .str,
        .data = .{ .str = .{
            .start = @intCast(u32, str_index),
            .len = @intCast(u32, str_len),
        } },
    });
    return rvalue(mod, scope, rl, result, node);
}

fn multilineStringLiteral(
    mod: *Module,
    scope: *Scope,
    rl: ResultLoc,
    node: ast.Node.Index,
) InnerError!zir.Inst.Ref {
    const gz = scope.getGenZir();
    const tree = gz.tree();
    const node_datas = tree.nodes.items(.data);
    const main_tokens = tree.nodes.items(.main_token);

    const start = node_datas[node].lhs;
    const end = node_datas[node].rhs;
    const string_bytes = &gz.zir_code.string_bytes;
    const str_index = string_bytes.items.len;

    // First line: do not append a newline.
    var tok_i = start;
    {
        const slice = tree.tokenSlice(tok_i);
        const line_bytes = slice[2 .. slice.len - 1];
        try string_bytes.appendSlice(mod.gpa, line_bytes);
        tok_i += 1;
    }
    // Following lines: each line prepends a newline.
    while (tok_i <= end) : (tok_i += 1) {
        const slice = tree.tokenSlice(tok_i);
        const line_bytes = slice[2 .. slice.len - 1];
        try string_bytes.ensureCapacity(mod.gpa, string_bytes.items.len + line_bytes.len + 1);
        string_bytes.appendAssumeCapacity('\n');
        string_bytes.appendSliceAssumeCapacity(line_bytes);
    }
    const result = try gz.add(.{
        .tag = .str,
        .data = .{ .str = .{
            .start = @intCast(u32, str_index),
            .len = @intCast(u32, string_bytes.items.len - str_index),
        } },
    });
    return rvalue(mod, scope, rl, result, node);
}

fn charLiteral(mod: *Module, scope: *Scope, rl: ResultLoc, node: ast.Node.Index) !zir.Inst.Ref {
    const gz = scope.getGenZir();
    const tree = gz.tree();
    const main_tokens = tree.nodes.items(.main_token);
    const main_token = main_tokens[node];
    const slice = tree.tokenSlice(main_token);

    var bad_index: usize = undefined;
    const value = std.zig.parseCharLiteral(slice, &bad_index) catch |err| switch (err) {
        error.InvalidCharacter => {
            const bad_byte = slice[bad_index];
            const token_starts = tree.tokens.items(.start);
            const src_off = @intCast(u32, token_starts[main_token] + bad_index);
            return mod.failOff(scope, src_off, "invalid character: '{c}'\n", .{bad_byte});
        },
    };
    const result = try gz.addInt(value);
    return rvalue(mod, scope, rl, result, node);
}

fn integerLiteral(
    mod: *Module,
    scope: *Scope,
    rl: ResultLoc,
    node: ast.Node.Index,
) InnerError!zir.Inst.Ref {
    const tree = scope.tree();
    const main_tokens = tree.nodes.items(.main_token);
    const int_token = main_tokens[node];
    const prefixed_bytes = tree.tokenSlice(int_token);
    const gz = scope.getGenZir();
    if (std.fmt.parseInt(u64, prefixed_bytes, 0)) |small_int| {
        const result: zir.Inst.Ref = switch (small_int) {
            0 => .zero,
            1 => .one,
            else => try gz.addInt(small_int),
        };
        return rvalue(mod, scope, rl, result, node);
    } else |err| {
        return mod.failNode(scope, node, "TODO implement int literals that don't fit in a u64", .{});
    }
}

fn floatLiteral(
    mod: *Module,
    scope: *Scope,
    rl: ResultLoc,
    float_lit: ast.Node.Index,
) InnerError!zir.Inst.Ref {
    if (true) @panic("TODO update for zir-memory-layout");
    const arena = scope.arena();
    const tree = scope.tree();
    const main_tokens = tree.nodes.items(.main_token);

    const main_token = main_tokens[float_lit];
    const bytes = tree.tokenSlice(main_token);
    if (bytes.len > 2 and bytes[1] == 'x') {
        return mod.failTok(scope, main_token, "TODO implement hex floats", .{});
    }
    const float_number = std.fmt.parseFloat(f128, bytes) catch |e| switch (e) {
        error.InvalidCharacter => unreachable, // validated by tokenizer
    };
    const result = try addZIRInstConst(mod, scope, src, .{
        .ty = Type.initTag(.comptime_float),
        .val = try Value.Tag.float_128.create(arena, float_number),
    });
    return rvalue(mod, scope, rl, result);
}

fn asmExpr(
    mod: *Module,
    scope: *Scope,
    rl: ResultLoc,
    node: ast.Node.Index,
    full: ast.full.Asm,
) InnerError!zir.Inst.Ref {
    const arena = scope.arena();
    const tree = scope.tree();
    const main_tokens = tree.nodes.items(.main_token);
    const node_datas = tree.nodes.items(.data);
    const gz = scope.getGenZir();

    const asm_source = try expr(mod, scope, .{ .ty = .const_slice_u8_type }, full.ast.template);

    if (full.outputs.len != 0) {
        return mod.failTok(scope, full.ast.asm_token, "TODO implement asm with an output", .{});
    }

    const constraints = try arena.alloc(u32, full.inputs.len);
    const args = try arena.alloc(zir.Inst.Ref, full.inputs.len);

    for (full.inputs) |input, i| {
        const constraint_token = main_tokens[input] + 2;
        const string_bytes = &gz.zir_code.string_bytes;
        constraints[i] = @intCast(u32, string_bytes.items.len);
        const token_bytes = tree.tokenSlice(constraint_token);
        try mod.parseStrLit(scope, constraint_token, string_bytes, token_bytes, 0);
        try string_bytes.append(mod.gpa, 0);

        args[i] = try expr(mod, scope, .{ .ty = .usize_type }, node_datas[input].lhs);
    }

    const tag: zir.Inst.Tag = if (full.volatile_token != null) .asm_volatile else .@"asm";
    const result = try gz.addPlNode(tag, node, zir.Inst.Asm{
        .asm_source = asm_source,
        .return_type = .void_type,
        .output = .none,
        .args_len = @intCast(u32, full.inputs.len),
        .clobbers_len = 0, // TODO implement asm clobbers
    });

    try gz.zir_code.extra.ensureCapacity(mod.gpa, gz.zir_code.extra.items.len +
        args.len + constraints.len);
    gz.zir_code.appendRefsAssumeCapacity(args);
    gz.zir_code.extra.appendSliceAssumeCapacity(constraints);

    return rvalue(mod, scope, rl, result, node);
}

fn as(
    mod: *Module,
    scope: *Scope,
    rl: ResultLoc,
    builtin_token: ast.TokenIndex,
    node: ast.Node.Index,
    lhs: ast.Node.Index,
    rhs: ast.Node.Index,
) InnerError!zir.Inst.Ref {
    const dest_type = try typeExpr(mod, scope, lhs);
    switch (rl) {
        .none, .discard, .ref, .ty => {
            const result = try expr(mod, scope, .{ .ty = dest_type }, rhs);
            return rvalue(mod, scope, rl, result, node);
        },

        .ptr => |result_ptr| {
            return asRlPtr(mod, scope, rl, result_ptr, rhs, dest_type);
        },
        .block_ptr => |block_scope| {
            return asRlPtr(mod, scope, rl, block_scope.rl_ptr, rhs, dest_type);
        },

        .bitcasted_ptr => |bitcasted_ptr| {
            // TODO here we should be able to resolve the inference; we now have a type for the result.
            return mod.failTok(scope, builtin_token, "TODO implement @as with result location @bitCast", .{});
        },
        .inferred_ptr => |result_alloc| {
            // TODO here we should be able to resolve the inference; we now have a type for the result.
            return mod.failTok(scope, builtin_token, "TODO implement @as with inferred-type result location pointer", .{});
        },
    }
}

fn asRlPtr(
    mod: *Module,
    scope: *Scope,
    rl: ResultLoc,
    result_ptr: zir.Inst.Ref,
    operand_node: ast.Node.Index,
    dest_type: zir.Inst.Ref,
) InnerError!zir.Inst.Ref {
    // Detect whether this expr() call goes into rvalue() to store the result into the
    // result location. If it does, elide the coerce_result_ptr instruction
    // as well as the store instruction, instead passing the result as an rvalue.
    const parent_gz = scope.getGenZir();
    const wzc = parent_gz.zir_code;

    var as_scope: Scope.GenZir = .{
        .parent = scope,
        .zir_code = wzc,
        .force_comptime = parent_gz.force_comptime,
        .instructions = .{},
    };
    defer as_scope.instructions.deinit(mod.gpa);

    as_scope.rl_ptr = try as_scope.addBin(.coerce_result_ptr, dest_type, result_ptr);
    const result = try expr(mod, &as_scope.base, .{ .block_ptr = &as_scope }, operand_node);
    const parent_zir = &parent_gz.instructions;
    if (as_scope.rvalue_rl_count == 1) {
        // Busted! This expression didn't actually need a pointer.
        const zir_tags = wzc.instructions.items(.tag);
        const zir_datas = wzc.instructions.items(.data);
        const expected_len = parent_zir.items.len + as_scope.instructions.items.len - 2;
        try parent_zir.ensureCapacity(mod.gpa, expected_len);
        for (as_scope.instructions.items) |src_inst| {
            if (wzc.indexToRef(src_inst) == as_scope.rl_ptr) continue;
            if (zir_tags[src_inst] == .store_to_block_ptr) {
                if (zir_datas[src_inst].bin.lhs == as_scope.rl_ptr) continue;
            }
            parent_zir.appendAssumeCapacity(src_inst);
        }
        assert(parent_zir.items.len == expected_len);
        const casted_result = try parent_gz.addBin(.as, dest_type, result);
        return rvalue(mod, scope, rl, casted_result, operand_node);
    } else {
        try parent_zir.appendSlice(mod.gpa, as_scope.instructions.items);
        return result;
    }
}

fn bitCast(
    mod: *Module,
    scope: *Scope,
    rl: ResultLoc,
    builtin_token: ast.TokenIndex,
    node: ast.Node.Index,
    lhs: ast.Node.Index,
    rhs: ast.Node.Index,
) InnerError!zir.Inst.Ref {
    if (true) @panic("TODO update for zir-memory-layout");
    const dest_type = try typeExpr(mod, scope, lhs);
    switch (rl) {
        .none => {
            const operand = try expr(mod, scope, .none, rhs);
            return addZIRBinOp(mod, scope, src, .bitcast, dest_type, operand);
        },
        .discard => {
            const operand = try expr(mod, scope, .none, rhs);
            const result = try addZIRBinOp(mod, scope, src, .bitcast, dest_type, operand);
            _ = try addZIRUnOp(mod, scope, result.src, .ensure_result_non_error, result);
            return result;
        },
        .ref => {
            const operand = try expr(mod, scope, .ref, rhs);
            const result = try addZIRBinOp(mod, scope, src, .bitcast_ref, dest_type, operand);
            return result;
        },
        .ty => |result_ty| {
            const result = try expr(mod, scope, .none, rhs);
            const bitcasted = try addZIRBinOp(mod, scope, src, .bitcast, dest_type, result);
            return addZIRBinOp(mod, scope, src, .as, result_ty, bitcasted);
        },
        .ptr => |result_ptr| {
            const casted_result_ptr = try addZIRUnOp(mod, scope, src, .bitcast_result_ptr, result_ptr);
            return expr(mod, scope, .{ .bitcasted_ptr = casted_result_ptr.castTag(.bitcast_result_ptr).? }, rhs);
        },
        .bitcasted_ptr => |bitcasted_ptr| {
            return mod.failTok(scope, builtin_token, "TODO implement @bitCast with result location another @bitCast", .{});
        },
        .block_ptr => |block_ptr| {
            return mod.failTok(scope, builtin_token, "TODO implement @bitCast with result location inferred peer types", .{});
        },
        .inferred_ptr => |result_alloc| {
            // TODO here we should be able to resolve the inference; we now have a type for the result.
            return mod.failTok(scope, builtin_token, "TODO implement @bitCast with inferred-type result location pointer", .{});
        },
    }
}

fn typeOf(
    mod: *Module,
    scope: *Scope,
    rl: ResultLoc,
    builtin_token: ast.TokenIndex,
    node: ast.Node.Index,
    params: []const ast.Node.Index,
) InnerError!zir.Inst.Ref {
    if (params.len < 1) {
        return mod.failTok(scope, builtin_token, "expected at least 1 argument, found 0", .{});
    }
    const gz = scope.getGenZir();
    if (params.len == 1) {
        return rvalue(
            mod,
            scope,
            rl,
            try gz.addUnTok(.typeof, try expr(mod, scope, .none, params[0]), node),
            node,
        );
    }
    const arena = scope.arena();
    var items = try arena.alloc(zir.Inst.Ref, params.len);
    for (params) |param, param_i| {
        items[param_i] = try expr(mod, scope, .none, param);
    }

    const result = try gz.addPlNode(.typeof_peer, node, zir.Inst.MultiOp{
        .operands_len = @intCast(u32, params.len),
    });
    try gz.zir_code.appendRefs(items);

    return rvalue(mod, scope, rl, result, node);
}

fn builtinCall(
    mod: *Module,
    scope: *Scope,
    rl: ResultLoc,
    node: ast.Node.Index,
    params: []const ast.Node.Index,
) InnerError!zir.Inst.Ref {
    const tree = scope.tree();
    const main_tokens = tree.nodes.items(.main_token);

    const builtin_token = main_tokens[node];
    const builtin_name = tree.tokenSlice(builtin_token);

    // We handle the different builtins manually because they have different semantics depending
    // on the function. For example, `@as` and others participate in result location semantics,
    // and `@cImport` creates a special scope that collects a .c source code text buffer.
    // Also, some builtins have a variable number of parameters.

    const info = BuiltinFn.list.get(builtin_name) orelse {
        return mod.failTok(scope, builtin_token, "invalid builtin function: '{s}'", .{
            builtin_name,
        });
    };
    if (info.param_count) |expected| {
        if (expected != params.len) {
            const s = if (expected == 1) "" else "s";
            return mod.failTok(scope, builtin_token, "expected {d} parameter{s}, found {d}", .{
                expected, s, params.len,
            });
        }
    }

    const gz = scope.getGenZir();

    switch (info.tag) {
        .ptr_to_int => {
            const operand = try expr(mod, scope, .none, params[0]);
            const result = try gz.addUnNode(.ptrtoint, operand, node);
            return rvalue(mod, scope, rl, result, node);
        },
        .float_cast => {
            const dest_type = try typeExpr(mod, scope, params[0]);
            const rhs = try expr(mod, scope, .none, params[1]);
            const result = try gz.addPlNode(.floatcast, node, zir.Inst.Bin{
                .lhs = dest_type,
                .rhs = rhs,
            });
            return rvalue(mod, scope, rl, result, node);
        },
        .int_cast => {
            const dest_type = try typeExpr(mod, scope, params[0]);
            const rhs = try expr(mod, scope, .none, params[1]);
            const result = try gz.addPlNode(.intcast, node, zir.Inst.Bin{
                .lhs = dest_type,
                .rhs = rhs,
            });
            return rvalue(mod, scope, rl, result, node);
        },
        .breakpoint => {
            const result = try gz.add(.{
                .tag = .breakpoint,
                .data = .{ .node = gz.zir_code.decl.nodeIndexToRelative(node) },
            });
            return rvalue(mod, scope, rl, result, node);
        },
        .import => {
            const target = try expr(mod, scope, .none, params[0]);
            const result = try gz.addUnNode(.import, target, node);
            return rvalue(mod, scope, rl, result, node);
        },
        .compile_error => {
            const target = try expr(mod, scope, .none, params[0]);
            const result = try gz.addUnNode(.compile_error, target, node);
            return rvalue(mod, scope, rl, result, node);
        },
        .set_eval_branch_quota => {
            const quota = try expr(mod, scope, .{ .ty = .u32_type }, params[0]);
            const result = try gz.addUnNode(.set_eval_branch_quota, quota, node);
            return rvalue(mod, scope, rl, result, node);
        },
        .compile_log => {
            const arg_refs = try mod.gpa.alloc(zir.Inst.Ref, params.len);
            defer mod.gpa.free(arg_refs);

            for (params) |param, i| arg_refs[i] = try expr(mod, scope, .none, param);

            const result = try gz.addPlNode(.compile_log, node, zir.Inst.MultiOp{
                .operands_len = @intCast(u32, params.len),
            });
            try gz.zir_code.appendRefs(arg_refs);
            return rvalue(mod, scope, rl, result, node);
        },
        .field => {
            const field_name = try comptimeExpr(mod, scope, .{ .ty = .const_slice_u8_type }, params[1]);
            if (rl == .ref) {
                return try gz.addPlNode(.field_ptr_named, node, zir.Inst.FieldNamed{
                    .lhs = try expr(mod, scope, .ref, params[0]),
                    .field_name = field_name,
                });
            }
            const result = try gz.addPlNode(.field_val_named, node, zir.Inst.FieldNamed{
                .lhs = try expr(mod, scope, .none, params[0]),
                .field_name = field_name,
            });
            return rvalue(mod, scope, rl, result, node);
        },
        .as => return as(mod, scope, rl, builtin_token, node, params[0], params[1]),
        .bit_cast => return bitCast(mod, scope, rl, builtin_token, node, params[0], params[1]),
        .TypeOf => return typeOf(mod, scope, rl, builtin_token, node, params),

        .add_with_overflow,
        .align_cast,
        .align_of,
        .atomic_load,
        .atomic_rmw,
        .atomic_store,
        .bit_offset_of,
        .bool_to_int,
        .bit_size_of,
        .mul_add,
        .byte_swap,
        .bit_reverse,
        .byte_offset_of,
        .call,
        .c_define,
        .c_import,
        .c_include,
        .clz,
        .cmpxchg_strong,
        .cmpxchg_weak,
        .ctz,
        .c_undef,
        .div_exact,
        .div_floor,
        .div_trunc,
        .embed_file,
        .enum_to_int,
        .error_name,
        .error_return_trace,
        .error_to_int,
        .err_set_cast,
        .@"export",
        .fence,
        .field_parent_ptr,
        .float_to_int,
        .has_decl,
        .has_field,
        .int_to_enum,
        .int_to_error,
        .int_to_float,
        .int_to_ptr,
        .memcpy,
        .memset,
        .wasm_memory_size,
        .wasm_memory_grow,
        .mod,
        .mul_with_overflow,
        .panic,
        .pop_count,
        .ptr_cast,
        .rem,
        .return_address,
        .set_align_stack,
        .set_cold,
        .set_float_mode,
        .set_runtime_safety,
        .shl_exact,
        .shl_with_overflow,
        .shr_exact,
        .shuffle,
        .size_of,
        .splat,
        .reduce,
        .src,
        .sqrt,
        .sin,
        .cos,
        .exp,
        .exp2,
        .log,
        .log2,
        .log10,
        .fabs,
        .floor,
        .ceil,
        .trunc,
        .round,
        .sub_with_overflow,
        .tag_name,
        .This,
        .truncate,
        .Type,
        .type_info,
        .type_name,
        .union_init,
        => return mod.failTok(scope, builtin_token, "TODO: implement builtin function {s}", .{
            builtin_name,
        }),

        .async_call,
        .frame,
        .Frame,
        .frame_address,
        .frame_size,
        => return mod.failTok(scope, builtin_token, "async and related features are not yet supported", .{}),
    }
}

fn callExpr(
    mod: *Module,
    scope: *Scope,
    rl: ResultLoc,
    node: ast.Node.Index,
    call: ast.full.Call,
) InnerError!zir.Inst.Ref {
    if (call.async_token) |async_token| {
        return mod.failTok(scope, async_token, "async and related features are not yet supported", .{});
    }
    const lhs = try expr(mod, scope, .none, call.ast.fn_expr);

    const args = try mod.gpa.alloc(zir.Inst.Ref, call.ast.params.len);
    defer mod.gpa.free(args);

    const gz = scope.getGenZir();
    for (call.ast.params) |param_node, i| {
        const param_type = try gz.add(.{
            .tag = .param_type,
            .data = .{ .param_type = .{
                .callee = lhs,
                .param_index = @intCast(u32, i),
            } },
        });
        args[i] = try expr(mod, scope, .{ .ty = param_type }, param_node);
    }

    const modifier: std.builtin.CallOptions.Modifier = switch (call.async_token != null) {
        true => .async_kw,
        false => .auto,
    };
    const result: zir.Inst.Ref = res: {
        const tag: zir.Inst.Tag = switch (modifier) {
            .auto => switch (args.len == 0) {
                true => break :res try gz.addUnNode(.call_none, lhs, node),
                false => .call,
            },
            .async_kw => return mod.failNode(scope, node, "async and related features are not yet supported", .{}),
            .never_tail => unreachable,
            .never_inline => unreachable,
            .no_async => return mod.failNode(scope, node, "async and related features are not yet supported", .{}),
            .always_tail => unreachable,
            .always_inline => unreachable,
            .compile_time => .call_compile_time,
        };
        break :res try gz.addCall(tag, lhs, args, node);
    };
    return rvalue(mod, scope, rl, result, node); // TODO function call with result location
}

pub const simple_types = std.ComptimeStringMap(zir.Inst.Ref, .{
    .{ "u8", .u8_type },
    .{ "i8", .i8_type },
    .{ "u16", .u16_type },
    .{ "i16", .i16_type },
    .{ "u32", .u32_type },
    .{ "i32", .i32_type },
    .{ "u64", .u64_type },
    .{ "i64", .i64_type },
    .{ "usize", .usize_type },
    .{ "isize", .isize_type },
    .{ "c_short", .c_short_type },
    .{ "c_ushort", .c_ushort_type },
    .{ "c_int", .c_int_type },
    .{ "c_uint", .c_uint_type },
    .{ "c_long", .c_long_type },
    .{ "c_ulong", .c_ulong_type },
    .{ "c_longlong", .c_longlong_type },
    .{ "c_ulonglong", .c_ulonglong_type },
    .{ "c_longdouble", .c_longdouble_type },
    .{ "f16", .f16_type },
    .{ "f32", .f32_type },
    .{ "f64", .f64_type },
    .{ "f128", .f128_type },
    .{ "c_void", .c_void_type },
    .{ "bool", .bool_type },
    .{ "void", .void_type },
    .{ "type", .type_type },
    .{ "anyerror", .anyerror_type },
    .{ "comptime_int", .comptime_int_type },
    .{ "comptime_float", .comptime_float_type },
    .{ "noreturn", .noreturn_type },
    .{ "null", .null_type },
    .{ "undefined", .undefined_type },
    .{ "undefined", .undef },
    .{ "null", .null_value },
    .{ "true", .bool_true },
    .{ "false", .bool_false },
});

fn nodeMayNeedMemoryLocation(scope: *Scope, start_node: ast.Node.Index) bool {
    const tree = scope.tree();
    const node_tags = tree.nodes.items(.tag);
    const node_datas = tree.nodes.items(.data);
    const main_tokens = tree.nodes.items(.main_token);
    const token_tags = tree.tokens.items(.tag);

    var node = start_node;
    while (true) {
        switch (node_tags[node]) {
            .root,
            .@"usingnamespace",
            .test_decl,
            .switch_case,
            .switch_case_one,
            .container_field_init,
            .container_field_align,
            .container_field,
            .asm_output,
            .asm_input,
            => unreachable,

            .@"return",
            .@"break",
            .@"continue",
            .bit_not,
            .bool_not,
            .global_var_decl,
            .local_var_decl,
            .simple_var_decl,
            .aligned_var_decl,
            .@"defer",
            .@"errdefer",
            .address_of,
            .optional_type,
            .negation,
            .negation_wrap,
            .@"resume",
            .array_type,
            .array_type_sentinel,
            .ptr_type_aligned,
            .ptr_type_sentinel,
            .ptr_type,
            .ptr_type_bit_range,
            .@"suspend",
            .@"anytype",
            .fn_proto_simple,
            .fn_proto_multi,
            .fn_proto_one,
            .fn_proto,
            .fn_decl,
            .anyframe_type,
            .anyframe_literal,
            .integer_literal,
            .float_literal,
            .enum_literal,
            .string_literal,
            .multiline_string_literal,
            .char_literal,
            .true_literal,
            .false_literal,
            .null_literal,
            .undefined_literal,
            .unreachable_literal,
            .identifier,
            .error_set_decl,
            .container_decl,
            .container_decl_trailing,
            .container_decl_two,
            .container_decl_two_trailing,
            .container_decl_arg,
            .container_decl_arg_trailing,
            .tagged_union,
            .tagged_union_trailing,
            .tagged_union_two,
            .tagged_union_two_trailing,
            .tagged_union_enum_tag,
            .tagged_union_enum_tag_trailing,
            .@"asm",
            .asm_simple,
            .add,
            .add_wrap,
            .array_cat,
            .array_mult,
            .assign,
            .assign_bit_and,
            .assign_bit_or,
            .assign_bit_shift_left,
            .assign_bit_shift_right,
            .assign_bit_xor,
            .assign_div,
            .assign_sub,
            .assign_sub_wrap,
            .assign_mod,
            .assign_add,
            .assign_add_wrap,
            .assign_mul,
            .assign_mul_wrap,
            .bang_equal,
            .bit_and,
            .bit_or,
            .bit_shift_left,
            .bit_shift_right,
            .bit_xor,
            .bool_and,
            .bool_or,
            .div,
            .equal_equal,
            .error_union,
            .greater_or_equal,
            .greater_than,
            .less_or_equal,
            .less_than,
            .merge_error_sets,
            .mod,
            .mul,
            .mul_wrap,
            .switch_range,
            .field_access,
            .sub,
            .sub_wrap,
            .slice,
            .slice_open,
            .slice_sentinel,
            .deref,
            .array_access,
            .error_value,
            .while_simple, // This variant cannot have an else expression.
            .while_cont, // This variant cannot have an else expression.
            .for_simple, // This variant cannot have an else expression.
            .if_simple, // This variant cannot have an else expression.
            => return false,

            // Forward the question to the LHS sub-expression.
            .grouped_expression,
            .@"try",
            .@"await",
            .@"comptime",
            .@"nosuspend",
            .unwrap_optional,
            => node = node_datas[node].lhs,

            // Forward the question to the RHS sub-expression.
            .@"catch",
            .@"orelse",
            => node = node_datas[node].rhs,

            // True because these are exactly the expressions we need memory locations for.
            .array_init_one,
            .array_init_one_comma,
            .array_init_dot_two,
            .array_init_dot_two_comma,
            .array_init_dot,
            .array_init_dot_comma,
            .array_init,
            .array_init_comma,
            .struct_init_one,
            .struct_init_one_comma,
            .struct_init_dot_two,
            .struct_init_dot_two_comma,
            .struct_init_dot,
            .struct_init_dot_comma,
            .struct_init,
            .struct_init_comma,
            => return true,

            // True because depending on comptime conditions, sub-expressions
            // may be the kind that need memory locations.
            .@"while", // This variant always has an else expression.
            .@"if", // This variant always has an else expression.
            .@"for", // This variant always has an else expression.
            .@"switch",
            .switch_comma,
            .call_one,
            .call_one_comma,
            .async_call_one,
            .async_call_one_comma,
            .call,
            .call_comma,
            .async_call,
            .async_call_comma,
            => return true,

            .block_two,
            .block_two_semicolon,
            .block,
            .block_semicolon,
            => {
                const lbrace = main_tokens[node];
                if (token_tags[lbrace - 1] == .colon) {
                    // Labeled blocks may need a memory location to forward
                    // to their break statements.
                    return true;
                } else {
                    return false;
                }
            },

            .builtin_call,
            .builtin_call_comma,
            .builtin_call_two,
            .builtin_call_two_comma,
            => {
                const builtin_token = main_tokens[node];
                const builtin_name = tree.tokenSlice(builtin_token);
                // If the builtin is an invalid name, we don't cause an error here; instead
                // let it pass, and the error will be "invalid builtin function" later.
                const builtin_info = BuiltinFn.list.get(builtin_name) orelse return false;
                return builtin_info.needs_mem_loc;
            },
        }
    }
}

/// Applies `rl` semantics to `inst`. Expressions which do not do their own handling of
/// result locations must call this function on their result.
/// As an example, if the `ResultLoc` is `ptr`, it will write the result to the pointer.
/// If the `ResultLoc` is `ty`, it will coerce the result to the type.
fn rvalue(
    mod: *Module,
    scope: *Scope,
    rl: ResultLoc,
    result: zir.Inst.Ref,
    src_node: ast.Node.Index,
) InnerError!zir.Inst.Ref {
    const gz = scope.getGenZir();
    switch (rl) {
        .none => return result,
        .discard => {
            // Emit a compile error for discarding error values.
            _ = try gz.addUnNode(.ensure_result_non_error, result, src_node);
            return result;
        },
        .ref => {
            // We need a pointer but we have a value.
            const tree = scope.tree();
            const src_token = tree.firstToken(src_node);
            return gz.addUnTok(.ref, result, src_token);
        },
        .ty => |ty_inst| {
            // Quickly eliminate some common, unnecessary type coercion.
            const as_ty = @as(u64, @enumToInt(zir.Inst.Ref.type_type)) << 32;
            const as_comptime_int = @as(u64, @enumToInt(zir.Inst.Ref.comptime_int_type)) << 32;
            const as_bool = @as(u64, @enumToInt(zir.Inst.Ref.bool_type)) << 32;
            const as_usize = @as(u64, @enumToInt(zir.Inst.Ref.usize_type)) << 32;
            const as_void = @as(u64, @enumToInt(zir.Inst.Ref.void_type)) << 32;
            switch ((@as(u64, @enumToInt(ty_inst)) << 32) | @as(u64, @enumToInt(result))) {
                as_ty | @enumToInt(zir.Inst.Ref.u8_type),
                as_ty | @enumToInt(zir.Inst.Ref.i8_type),
                as_ty | @enumToInt(zir.Inst.Ref.u16_type),
                as_ty | @enumToInt(zir.Inst.Ref.i16_type),
                as_ty | @enumToInt(zir.Inst.Ref.u32_type),
                as_ty | @enumToInt(zir.Inst.Ref.i32_type),
                as_ty | @enumToInt(zir.Inst.Ref.u64_type),
                as_ty | @enumToInt(zir.Inst.Ref.i64_type),
                as_ty | @enumToInt(zir.Inst.Ref.usize_type),
                as_ty | @enumToInt(zir.Inst.Ref.isize_type),
                as_ty | @enumToInt(zir.Inst.Ref.c_short_type),
                as_ty | @enumToInt(zir.Inst.Ref.c_ushort_type),
                as_ty | @enumToInt(zir.Inst.Ref.c_int_type),
                as_ty | @enumToInt(zir.Inst.Ref.c_uint_type),
                as_ty | @enumToInt(zir.Inst.Ref.c_long_type),
                as_ty | @enumToInt(zir.Inst.Ref.c_ulong_type),
                as_ty | @enumToInt(zir.Inst.Ref.c_longlong_type),
                as_ty | @enumToInt(zir.Inst.Ref.c_ulonglong_type),
                as_ty | @enumToInt(zir.Inst.Ref.c_longdouble_type),
                as_ty | @enumToInt(zir.Inst.Ref.f16_type),
                as_ty | @enumToInt(zir.Inst.Ref.f32_type),
                as_ty | @enumToInt(zir.Inst.Ref.f64_type),
                as_ty | @enumToInt(zir.Inst.Ref.f128_type),
                as_ty | @enumToInt(zir.Inst.Ref.c_void_type),
                as_ty | @enumToInt(zir.Inst.Ref.bool_type),
                as_ty | @enumToInt(zir.Inst.Ref.void_type),
                as_ty | @enumToInt(zir.Inst.Ref.type_type),
                as_ty | @enumToInt(zir.Inst.Ref.anyerror_type),
                as_ty | @enumToInt(zir.Inst.Ref.comptime_int_type),
                as_ty | @enumToInt(zir.Inst.Ref.comptime_float_type),
                as_ty | @enumToInt(zir.Inst.Ref.noreturn_type),
                as_ty | @enumToInt(zir.Inst.Ref.null_type),
                as_ty | @enumToInt(zir.Inst.Ref.undefined_type),
                as_ty | @enumToInt(zir.Inst.Ref.fn_noreturn_no_args_type),
                as_ty | @enumToInt(zir.Inst.Ref.fn_void_no_args_type),
                as_ty | @enumToInt(zir.Inst.Ref.fn_naked_noreturn_no_args_type),
                as_ty | @enumToInt(zir.Inst.Ref.fn_ccc_void_no_args_type),
                as_ty | @enumToInt(zir.Inst.Ref.single_const_pointer_to_comptime_int_type),
                as_ty | @enumToInt(zir.Inst.Ref.const_slice_u8_type),
                as_ty | @enumToInt(zir.Inst.Ref.enum_literal_type),
                as_comptime_int | @enumToInt(zir.Inst.Ref.zero),
                as_comptime_int | @enumToInt(zir.Inst.Ref.one),
                as_bool | @enumToInt(zir.Inst.Ref.bool_true),
                as_bool | @enumToInt(zir.Inst.Ref.bool_false),
                as_usize | @enumToInt(zir.Inst.Ref.zero_usize),
                as_usize | @enumToInt(zir.Inst.Ref.one_usize),
                as_void | @enumToInt(zir.Inst.Ref.void_value),
                => return result, // type of result is already correct

                // Need an explicit type coercion instruction.
                else => return gz.addPlNode(.as_node, src_node, zir.Inst.As{
                    .dest_type = ty_inst,
                    .operand = result,
                }),
            }
        },
        .ptr => |ptr_inst| {
            _ = try gz.addPlNode(.store_node, src_node, zir.Inst.Bin{
                .lhs = ptr_inst,
                .rhs = result,
            });
            return result;
        },
        .bitcasted_ptr => |bitcasted_ptr| {
            return mod.failNode(scope, src_node, "TODO implement rvalue .bitcasted_ptr", .{});
        },
        .inferred_ptr => |alloc| {
            _ = try gz.addBin(.store_to_inferred_ptr, alloc, result);
            return result;
        },
        .block_ptr => |block_scope| {
            block_scope.rvalue_rl_count += 1;
            _ = try gz.addBin(.store_to_block_ptr, block_scope.rl_ptr, result);
            return result;
        },
    }
}

fn rlStrategy(rl: ResultLoc, block_scope: *Scope.GenZir) ResultLoc.Strategy {
    var elide_store_to_block_ptr_instructions = false;
    switch (rl) {
        // In this branch there will not be any store_to_block_ptr instructions.
        .discard, .none, .ty, .ref => return .{
            .tag = .break_operand,
            .elide_store_to_block_ptr_instructions = false,
        },
        // The pointer got passed through to the sub-expressions, so we will use
        // break_void here.
        // In this branch there will not be any store_to_block_ptr instructions.
        .ptr => return .{
            .tag = .break_void,
            .elide_store_to_block_ptr_instructions = false,
        },
        .inferred_ptr, .bitcasted_ptr, .block_ptr => {
            if (block_scope.rvalue_rl_count == block_scope.break_count) {
                // Neither prong of the if consumed the result location, so we can
                // use break instructions to create an rvalue.
                return .{
                    .tag = .break_operand,
                    .elide_store_to_block_ptr_instructions = true,
                };
            } else {
                // Allow the store_to_block_ptr instructions to remain so that
                // semantic analysis can turn them into bitcasts.
                return .{
                    .tag = .break_void,
                    .elide_store_to_block_ptr_instructions = false,
                };
            }
        },
    }
}

fn setBlockResultLoc(block_scope: *Scope.GenZir, parent_rl: ResultLoc) void {
    // Depending on whether the result location is a pointer or value, different
    // ZIR needs to be generated. In the former case we rely on storing to the
    // pointer to communicate the result, and use breakvoid; in the latter case
    // the block break instructions will have the result values.
    // One more complication: when the result location is a pointer, we detect
    // the scenario where the result location is not consumed. In this case
    // we emit ZIR for the block break instructions to have the result values,
    // and then rvalue() on that to pass the value to the result location.
    switch (parent_rl) {
        .discard, .none, .ty, .ptr, .ref => {
            block_scope.break_result_loc = parent_rl;
        },

        .inferred_ptr => |ptr| {
            block_scope.rl_ptr = ptr;
            block_scope.break_result_loc = .{ .block_ptr = block_scope };
        },

        .bitcasted_ptr => |ptr| {
            block_scope.rl_ptr = ptr;
            block_scope.break_result_loc = .{ .block_ptr = block_scope };
        },

        .block_ptr => |parent_block_scope| {
            block_scope.rl_ptr = parent_block_scope.rl_ptr;
            block_scope.break_result_loc = .{ .block_ptr = block_scope };
        },
    }
}
