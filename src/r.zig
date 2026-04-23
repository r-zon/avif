const std = @import("std");
const c = @import("c");
const assert = std.debug.assert;

pub const Sexp = extern struct {
    ptr: c.SEXP,

    const Type = enum(u8) {
        null = c.NILSXP,
        symbol = c.SYMSXP,
        list = c.LISTSXP,
        closure = c.CLOSXP,
        environment = c.ENVSXP,
        promise = c.PROMSXP,
        language = c.LANGSXP,
        special = c.SPECIALSXP,
        builtin = c.BUILTINSXP,
        char = c.CHARSXP,
        logical = c.LGLSXP,
        integer = c.INTSXP,
        real = c.REALSXP,
        complex = c.CPLXSXP,
        string = c.STRSXP,
        dot = c.DOTSXP,
        any = c.ANYSXP,
        vector = c.VECSXP,
        expression = c.EXPRSXP,
        bytecode = c.BCODESXP,
        external_pointer = c.EXTPTRSXP,
        weak_reference = c.WEAKREFSXP,
        raw = c.RAWSXP,
        object = c.OBJSXP,

        new = c.NEWSXP,
        free = c.FREESXP,

        function = c.FUNSXP,

        _,

        fn ctype(self: Type) type {
            return switch (self) {
                .raw, .char => u8,
                .integer, .logical => c_int,
                .real => f64,
                .string => c.SEXP, // CHARSXP
                .complex => c.Rcomplex,
                else => @panic("Unsupported type"),
            };
        }
    };

    const Status = enum {
        protected,
        unprotected,
    };

    pub fn @"type"(self: Sexp) Type {
        return @enumFromInt(c.TYPEOF(self.ptr));
    }

    pub fn len(self: Sexp) c.R_xlen_t {
        return c.Rf_xlength(self.ptr);
    }

    pub fn isLogical(self: Sexp) bool {
        return c.Rf_isLogical(self.ptr) != 0;
    }

    pub fn isNull(self: Sexp) bool {
        return c.Rf_isNull(self.ptr) != 0;
    }

    pub fn isString(self: Sexp) bool {
        return c.Rf_isString(self.ptr) != 0;
    }

    pub fn raw(self: Sexp) [*c]u8 {
        assert(self.type() == .raw);
        return c.RAW(self.ptr);
    }

    pub fn logical(self: Sexp) [*c]c_int {
        assert(self.type() == .logical);
        return c.LOGICAL(self.ptr);
    }

    pub fn integer(self: Sexp) [*c]c_int {
        assert(self.type() == .integer);
        return c.INTEGER(self.ptr);
    }

    pub fn stringElement(self: Sexp, i: c.R_xlen_t) Sexp {
        assert(self.type() == .string);
        return .{ .ptr = c.STRING_ELT(self.ptr, i) };
    }

    pub fn toUtf8(self: Sexp) [*c]const u8 {
        assert(self.type() == .char);
        return c.Rf_translateCharUTF8(self.ptr);
    }
};

pub fn na(comptime T: Sexp.Type) T.ctype() {
    return switch (T) {
        .integer, .logical => c.R_NaInt,
        .real => c.R_NaReal,
        .string => c.R_NaString,
        else => @panic("Unsupported type"),
    };
}

pub fn allocVector(T: Sexp.Type, n: usize, status: Sexp.Status) c.SEXP {
    const vector = c.Rf_allocVector(@intFromEnum(T), @intCast(n));
    if (status == .protected)
        return protect(vector);
    return vector;
}

pub fn allocScalar(comptime T: Sexp.Type, value: T.ctype(), status: Sexp.Status) c.SEXP {
    const scalar = switch (T) {
        .logical => c.Rf_ScalarLogical(value),
        .integer => c.Rf_ScalarInteger(value),
        .real => c.Rf_ScalarReal(value),
        .complex => c.Rf_ScalarComplex(value),
        .raw => c.Rf_ScalarRaw(value),
        .string => c.Rf_ScalarString(value),
        else => @panic("Unsupported type"),
    };
    if (status == .protected)
        return protect(scalar);
    return scalar;
}

pub const warn = c.Rf_warning;
pub const err = c.Rf_error;
pub const protect = c.Rf_protect;
pub const unprotect = c.Rf_unprotect;
pub const setAttribute = c.Rf_setAttrib;
pub const getAttribute = c.Rf_getAttrib;
pub const install = c.Rf_install;

pub const CallMethodDef = c.R_CallMethodDef;
pub const DllInfo = c.DllInfo;
pub const registerRoutines = c.R_registerRoutines;
pub const useDynamicSymbols = c.R_useDynamicSymbols;
pub const forceSymbols = c.R_forceSymbols;
